#!/usr/bin/env ruby
# Uploads the App Store review screenshot of an in-app purchase (App Store
# Connect's three steps: reserve, PUT the bytes to each upload operation,
# commit with the MD5). Run ON THE MAC, where the API key lives:
#   ruby upload-iap-review-shot.rb <iap id> <png path>            # dry run: prints the plan
#   ruby upload-iap-review-shot.rb <iap id> <png path> --upload   # does it
# An IAP write: only with Jackson's okay for that exact purchase and image.
# Replaces nothing: refuses if the purchase already has a review screenshot.
require 'json'; require 'net/http'; require 'uri'; require 'digest'; require 'open3'

iap, png, flag = ARGV
abort 'usage: upload-iap-review-shot.rb <iap id> <png> [--upload]' unless iap && png && File.file?(png)
api = File.join(__dir__, 'asc-api.rb')

def call(api, *args, body: nil)
  out, status = Open3.capture2('ruby', api, *args, stdin_data: body.to_s)
  abort "asc-api failed: #{out}" unless status.success?
  code = out[/\AHTTP (\d+)/, 1].to_i
  json = out.sub(/\AHTTP \d+\n?/, '')
  [code, json.strip.empty? ? {} : JSON.parse(json)]
end

code, existing = call(api, 'GET', "/v2/inAppPurchases/#{iap}/appStoreReviewScreenshot")
if code == 200 && existing['data']
  abort "refused: #{iap} already has a review screenshot (#{existing['data']['id']}); nothing changed"
end

bytes = File.binread(png)
name = File.basename(png)
puts "purchase #{iap}: #{name}, #{bytes.bytesize} bytes, md5 #{Digest::MD5.hexdigest(bytes)}"
unless flag == '--upload'
  puts 'dry run: add --upload to send it'
  exit 0
end

reserve = { data: { type: 'inAppPurchaseAppStoreReviewScreenshots',
                    attributes: { fileName: name, fileSize: bytes.bytesize },
                    relationships: { inAppPurchaseV2: { data: { type: 'inAppPurchases', id: iap } } } } }
code, res = call(api, 'POST', '/v1/inAppPurchaseAppStoreReviewScreenshots', '-', body: reserve.to_json)
abort "reserve failed (HTTP #{code}): #{res}" unless code == 201
shot = res['data']['id']
res['data']['attributes']['uploadOperations'].each do |op|
  uri = URI(op['url'])
  req = Net::HTTP.const_get(op['method'].capitalize).new(uri)
  op['requestHeaders'].each { |h| req[h['name']] = h['value'] }
  req.body = bytes.byteslice(op['offset'], op['length'])
  r = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(req) }
  abort "upload part at #{op['offset']} failed: HTTP #{r.code}" unless r.code.to_i.between?(200, 299)
end
commit = { data: { type: 'inAppPurchaseAppStoreReviewScreenshots', id: shot,
                   attributes: { uploaded: true, sourceFileChecksum: Digest::MD5.hexdigest(bytes) } } }
code, res = call(api, 'PATCH', "/v1/inAppPurchaseAppStoreReviewScreenshots/#{shot}", '-', body: commit.to_json)
abort "commit failed (HTTP #{code}): #{res}" unless code == 200
puts "uploaded: screenshot #{shot}, state #{res.dig('data', 'attributes', 'assetDeliveryState', 'state')}"
