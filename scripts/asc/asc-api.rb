#!/usr/bin/env ruby
# Generic App Store Connect API client for ChirpChirps (app id 6761436901).
# Run ON THE MAC (the .p8 signing key lives in ~/.sanger-build):
#   ruby asc-api.rb GET  /v1/apps/6761436901/appStoreVersions
#   ruby asc-api.rb PATCH /v1/appStoreVersions/<id> '<json body>'
#   ruby asc-api.rb POST  /v1/... - < body.json     (dash => body from stdin)
# ES256 JWT signed exactly like asc-build-status.rb. Prints "HTTP <code>" then
# the response body (pretty-printed when JSON). Read or write depending on verb;
# this script performs NO submission on its own — a submission is a specific POST
# the caller must issue deliberately.
require 'openssl'; require 'base64'; require 'json'; require 'net/http'; require 'uri'

def b64(s); Base64.urlsafe_encode64(s).delete('='); end

secrets_path = File.expand_path('~/.sanger-build/secrets.env')
env = {}
File.read(secrets_path).each_line do |raw|
  next unless raw.chomp =~ /APP_STORE_CONNECT_API_KEY_(\w+)=(.*)\z/
  env[$1] = $2.strip.gsub(/\A["']|["']\z/, '')
end
kid = env['KEY_ID']; iss = env['ISSUER_ID']
keyfile = File.expand_path((env['KEY_FILEPATH'] || '~/.sanger-build/AuthKey_PJ8D2LN86F.p8')
  .gsub('$HOME', ENV['HOME']).gsub('${HOME}', ENV['HOME']))
abort "missing kid/iss (#{kid.inspect}/#{iss.inspect})" unless kid && iss

now = Time.now.to_i
signing_input = "#{b64({ alg: 'ES256', kid: kid, typ: 'JWT' }.to_json)}." \
                "#{b64({ iss: iss, iat: now, exp: now + 20 * 60, aud: 'appstoreconnect-v1' }.to_json)}"
key = OpenSSL::PKey::EC.new(File.read(keyfile))
der = key.sign(OpenSSL::Digest::SHA256.new, signing_input)
asn = OpenSSL::ASN1.decode(der)
r = asn.value[0].value.to_s(2).rjust(32, "\x00"); s = asn.value[1].value.to_s(2).rjust(32, "\x00")
jwt = "#{signing_input}.#{b64(r + s)}"

method = (ARGV[0] || 'GET').upcase
path   = ARGV[1] or abort 'usage: asc-api.rb <METHOD> <path> [json-body|-]'
body   = nil
if ARGV[2] == '-'
  body = $stdin.read
elsif ARGV[2]
  body = ARGV[2]
end

uri = URI("https://api.appstoreconnect.apple.com#{path}")
klass = { 'GET' => Net::HTTP::Get, 'POST' => Net::HTTP::Post,
          'PATCH' => Net::HTTP::Patch, 'DELETE' => Net::HTTP::Delete }.fetch(method)
req = klass.new(uri)
req['Authorization'] = "Bearer #{jwt}"
if body
  req['Content-Type'] = 'application/json'
  req.body = body
end
res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(req) }
puts "HTTP #{res.code}"
if res.body && !res.body.empty?
  begin
    puts JSON.pretty_generate(JSON.parse(res.body))
  rescue StandardError
    puts res.body
  end
end
