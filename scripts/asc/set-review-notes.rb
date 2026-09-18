#!/usr/bin/env ruby
# Put fastlane/metadata/review_information/notes.txt into App Store Connect as
# the version's App Review notes, and set demoAccountRequired to false.
#
# RUN ON THE MAC (asc-api.rb needs the .p8 in ~/.sanger-build):
#   ruby scripts/asc/set-review-notes.rb           # dry run
#   ruby scripts/asc/set-review-notes.rb --apply
#
# Exists because `deliver` uploads review information only as part of a full
# metadata push, which would also rewrite the description, keywords and
# screenshots. This writes the one field and then RE-READS it: a PATCH that
# silently changes nothing looks exactly like one that worked.
#
# Submitting for review is deliberately NOT part of this script.

require 'json'
require 'open3'

APP_ID     = '6761436901'
VERSION    = '1.0'
ASC        = File.join(__dir__, 'asc-api.rb')
NOTES_FILE = File.expand_path('../../fastlane/metadata/review_information/notes.txt', __dir__)

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

notes = File.read(NOTES_FILE).strip
abort 'notes.txt is empty' if notes.empty?
# Plain text only: an em dash has a habit of reaching the reviewer's console as
# mojibake, and these notes are the one thing they are certain to read.
abort 'notes.txt contains an em dash; use plain punctuation' if notes.include?("—")
puts "notes.txt: #{notes.length} characters, #{notes.lines.count} lines"

code, versions = api('GET', "/v1/apps/#{APP_ID}/appStoreVersions?filter%5BversionString%5D=#{VERSION}")
abort "version lookup failed (HTTP #{code})" unless code == 200
version = versions['data'].first
abort "no version #{VERSION}" unless version
puts "version #{VERSION} #{version['id']} state=#{version['attributes']['appStoreState']}"

code, detail = api('GET', "/v1/appStoreVersions/#{version['id']}/appStoreReviewDetail")
abort "review detail lookup failed (HTTP #{code})" unless code == 200
existing = detail['data']
abort 'this version has no appStoreReviewDetail' unless existing
attrs = existing['attributes']

puts "review detail #{existing['id']}"
puts "  contact: #{attrs['contactFirstName']} #{attrs['contactLastName']} <#{attrs['contactEmail']}> #{attrs['contactPhone']}"
puts "  demoAccountRequired: #{attrs['demoAccountRequired'].inspect}"
puts "  notes stored: #{attrs['notes'].to_s.length} characters"

if attrs['notes'].to_s.strip == notes && attrs['demoAccountRequired'] == false
  puts 'already up to date'
  exit 0
end

unless apply
  puts '--- would write (dry run) ---'
  puts notes
  puts '--- rerun with --apply ---'
  exit 0
end

body = JSON.generate(
  data: {
    type: 'appStoreReviewDetails',
    id: existing['id'],
    attributes: { notes: notes, demoAccountRequired: false }
  }
)
code, = api('PATCH', "/v1/appStoreReviewDetails/#{existing['id']}", body)
abort "PATCH failed (HTTP #{code})" unless [200, 201].include?(code)

code, saved = api('GET', "/v1/appStoreVersions/#{version['id']}/appStoreReviewDetail")
abort "read-back failed (HTTP #{code})" unless code == 200
saved_attrs = saved['data']['attributes']
if saved_attrs['notes'].to_s.strip == notes && saved_attrs['demoAccountRequired'] == false
  puts "SAVED: #{saved_attrs['notes'].length} characters, demoAccountRequired=false"
  puts "contact unchanged: #{saved_attrs['contactFirstName']} #{saved_attrs['contactLastName']} <#{saved_attrs['contactEmail']}>"
else
  warn 'MISMATCH after write. Stored value begins:'
  warn saved_attrs['notes'].to_s[0, 400]
  warn "demoAccountRequired=#{saved_attrs['demoAccountRequired'].inspect}"
  exit 1
end
