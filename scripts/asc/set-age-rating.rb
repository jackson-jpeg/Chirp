#!/usr/bin/env ruby
# Set the age rating declaration to match what ChirpChirps actually is: an app
# whose entire purpose is unrestricted, unmoderated-at-the-source messaging
# between strangers who happen to be nearby, plus optional location sharing.
#
# RUN ON THE MAC (asc-api.rb needs the .p8 in ~/.sanger-build):
#   ruby scripts/asc/set-age-rating.rb           # dry run
#   ruby scripts/asc/set-age-rating.rb --apply
#
# Exists because `deliver` does not manage the age rating questionnaire at all,
# and because the declaration hangs off the app's appInfo rather than the
# version: the relationship `appStoreVersions/{id}/ageRatingDeclaration` does
# NOT exist and returns a PATH_ERROR. The path is
# `apps/{id}/appInfos` -> `appInfos/{id}/ageRatingDeclaration`.
#
# Like set-review-notes.rb this RE-READS after writing, because a PATCH that
# silently changed nothing looks exactly like one that worked.

require 'json'
require 'open3'

APP_ID = '6761436901'
ASC    = File.join(__dir__, 'asc-api.rb')

# Only these keys are asserted. Everything else in the declaration is left
# exactly as it is: this app has no gambling, no weapons, no medical advice,
# and answering questions it was never asked would be its own kind of wrong.
#
#   messagingAndChat / userGeneratedContent
#     Both true. Every message is written by a user and delivered to another
#     user with nothing in between, which is the definition Apple is asking
#     about. The on-device filter and the block list do not make this false:
#     they are mitigations, not a claim that the content is curated.
#   ageRatingOverrideV2
#     EIGHTEEN_PLUS. Unrestricted person-to-person contact with strangers and
#     optional real-world position sharing is not a seventeen-plus feature set.
DESIRED = {
  'messagingAndChat'    => true,
  'userGeneratedContent' => true,
  'ageRatingOverrideV2' => 'EIGHTEEN_PLUS'
}.freeze

def api(method, path, body = nil)
  cmd = ['ruby', ASC, method, path]
  cmd << '-' if body
  out, err, status = Open3.capture3(*cmd, stdin_data: body || '')
  abort "asc-api.rb #{method} #{path} failed: #{err}" unless status.success?
  code = out.lines.first.to_s[/HTTP (\d+)/, 1].to_i
  json = out.split("\n", 2)[1]
  [code, (JSON.parse(json) rescue nil)]
end

apply = ARGV.include?('--apply')

code, infos = api('GET', "/v1/apps/#{APP_ID}/appInfos")
abort "appInfos lookup failed (HTTP #{code})" unless code == 200
# The editable appInfo is the one that is not already live on the store.
info = infos['data'].find { |i| i['attributes']['state'] != 'READY_FOR_DISTRIBUTION' } ||
       infos['data'].first
abort 'no appInfo' unless info
puts "appInfo #{info['id']} state=#{info['attributes']['state']}"

code, decl = api('GET', "/v1/appInfos/#{info['id']}/ageRatingDeclaration")
abort "ageRatingDeclaration lookup failed (HTTP #{code})" unless code == 200
current = decl['data']
abort 'this appInfo has no ageRatingDeclaration' unless current
attrs = current['attributes']

puts "ageRatingDeclaration #{current['id']}"
DESIRED.each do |key, want|
  have = attrs[key]
  mark = have == want ? 'ok' : "CHANGE -> #{want.inspect}"
  puts format('  %-22s %-16s %s', key, have.inspect, mark)
end
puts "  (ageRatingOverride legacy: #{attrs['ageRatingOverride'].inspect})"

drift = DESIRED.reject { |k, v| attrs[k] == v }
if drift.empty?
  puts 'already correct; nothing to write'
  exit 0
end

unless apply
  puts "--- would PATCH (dry run): #{drift.keys.join(', ')} ---"
  puts '--- rerun with --apply ---'
  exit 0
end

body = {
  data: {
    type: 'ageRatingDeclarations',
    id: current['id'],
    attributes: drift
  }
}.to_json

code, _ = api('PATCH', "/v1/ageRatingDeclarations/#{current['id']}", body)
abort "PATCH failed (HTTP #{code})" unless (200..299).cover?(code)

# Re-read. This is the whole point of the script.
code, decl = api('GET', "/v1/appInfos/#{info['id']}/ageRatingDeclaration")
abort "re-read failed (HTTP #{code})" unless code == 200
saved = decl['data']['attributes']

bad = DESIRED.reject { |k, v| saved[k] == v }
DESIRED.each_key { |k| puts format('  saved %-22s %s', k, saved[k].inspect) }
if bad.empty?
  puts 'age rating saved and verified'
else
  abort "age rating did NOT stick: #{bad.keys.join(', ')}"
end
