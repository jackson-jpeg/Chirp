#!/usr/bin/env ruby
# Attach an uploaded, processed build to an App Store version.
#
# RUN ON THE MAC (asc-api.rb needs the .p8 in ~/.sanger-build):
#   ruby scripts/asc/attach-build.rb 202609151723            # dry run
#   ruby scripts/asc/attach-build.rb 202609151723 --apply
#
# Exists because `deliver`'s `build_number:` option does NOT reattach the build
# on a version that already has one: it reported success, and version 1.0 was
# still pointing at the previously rejected binary. Attaching is a one-line
# PATCH of the version's `build` relationship, so do it explicitly and verify
# by re-reading rather than trusting a 200.
#
# Submitting for review is deliberately NOT part of this script.

require 'json'
require 'open3'

APP_ID  = '6761436901'
ASC     = File.join(__dir__, 'asc-api.rb')

def api(method, path, body = nil)
  cmd = ['ruby', ASC, method, path]
  cmd << '-' if body
  out, err, status = Open3.capture3(*cmd, stdin_data: body || '')
  abort "asc-api.rb #{method} #{path} failed: #{err}" unless status.success?
  code = out.lines.first.to_s[/HTTP (\d+)/, 1].to_i
  json = out.split("\n", 2)[1]
  [code, (JSON.parse(json) rescue nil)]
end

build_number = ARGV[0] or abort 'usage: attach-build.rb <buildNumber> [--apply]'
apply = ARGV.include?('--apply')

# Find the build. filter[version] is the CFBundleVersion (the build number).
code, builds = api('GET', "/v1/builds?filter[app]=#{APP_ID}&filter[version]=#{build_number}&limit=1")
abort "builds query -> HTTP #{code}" unless code == 200
build = builds['data'].first or abort "no build numbered #{build_number} for app #{APP_ID}"

state = build.dig('attributes', 'processingState')
abort "build #{build_number} is #{state}, not VALID — refusing to attach" unless state == 'VALID'
puts "build #{build_number} -> #{build['id']} (#{state})"

# The editable version. There is exactly one that is not RELEASED.
code, versions = api('GET', "/v1/apps/#{APP_ID}/appStoreVersions?limit=5")
abort "versions query -> HTTP #{code}" unless code == 200
version = versions['data'].find { |v| v.dig('attributes', 'appStoreState') != 'READY_FOR_SALE' }
abort 'no editable App Store version' unless version
puts "version #{version.dig('attributes', 'versionString')} -> #{version['id']} " \
     "(#{version.dig('attributes', 'appStoreState')})"

_, current = api('GET', "/v1/appStoreVersions/#{version['id']}/build")
puts "currently attached: #{current&.dig('data', 'attributes', 'version') || 'none'}"

unless apply
  puts "\ndry run — pass --apply to attach"
  exit 0
end

body = { data: { type: 'builds', id: build['id'] } }.to_json
code, = api('PATCH', "/v1/appStoreVersions/#{version['id']}/relationships/build", body)
abort "attach PATCH -> HTTP #{code}" unless [200, 204].include?(code)
puts "\nPATCH build relationship -> #{code}"

# Verify by re-reading. A relationship PATCH that quietly did nothing also
# returns 204.
_, now = api('GET', "/v1/appStoreVersions/#{version['id']}/build")
attached = now&.dig('data', 'attributes', 'version')
if attached == build_number
  puts "verified: version #{version.dig('attributes', 'versionString')} now holds build #{attached}"
else
  abort "NOT attached — version still holds #{attached.inspect}"
end
