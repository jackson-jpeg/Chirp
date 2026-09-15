#!/usr/bin/env ruby
# List recent TestFlight builds for ChirpChirps via the App Store Connect API.
# Run ON THE MAC: source ~/.sanger-build/secrets.env && ruby asc-builds.rb
# Read-only. Prints version, build number, processing state, upload date, expired flag.
require 'openssl'; require 'base64'; require 'json'; require 'net/http'; require 'uri'
kid = ENV.fetch('APP_STORE_CONNECT_API_KEY_KEY_ID')
iss = ENV.fetch('APP_STORE_CONNECT_API_KEY_ISSUER_ID')
p8  = File.read(File.expand_path(ENV.fetch('APP_STORE_CONNECT_API_KEY_KEY_FILEPATH')))
key = OpenSSL::PKey::EC.new(p8)
b64 = ->(s){ Base64.urlsafe_encode64(s, padding: false) }
hdr = b64.call({alg:'ES256',kid:kid,typ:'JWT'}.to_json)
now = Time.now.to_i
pay = b64.call({iss:iss,iat:now,exp:now+600,aud:'appstoreconnect-v1'}.to_json)
der = key.sign(OpenSSL::Digest::SHA256.new, "#{hdr}.#{pay}")
# DER -> raw r||s
seq = OpenSSL::ASN1.decode(der); r = seq.value[0].value.to_s(2).rjust(32,"\0")[-32..]; s = seq.value[1].value.to_s(2).rjust(32,"\0")[-32..]
jwt = "#{hdr}.#{pay}.#{b64.call(r+s)}"
app = ENV.fetch('ASC_APP_ID','6761436901')
uri = URI("https://api.appstoreconnect.apple.com/v1/builds?filter[app]=#{app}&sort=-uploadedDate&limit=#{ENV.fetch('LIMIT','5')}&include=preReleaseVersion")
req = Net::HTTP::Get.new(uri); req['Authorization']="Bearer #{jwt}"
res = Net::HTTP.start(uri.host, uri.port, use_ssl: true){|h| h.request(req)}
abort "HTTP #{res.code}: #{res.body[0,500]}" unless res.code=='200'
j = JSON.parse(res.body)
vers = {}
(j['included']||[]).each{|i| vers[i['id']]=i.dig('attributes','version') if i['type']=='preReleaseVersions'}
j['data'].each do |b|
  a=b['attributes']; v=vers[b.dig('relationships','preReleaseVersion','data','id')]
  puts [v, a['version'], a['processingState'], a['uploadedDate'], "expired=#{a['expired']}", "usesNonExemptEncryption=#{a['usesNonExemptEncryption'].inspect}"].join("  ")
end
