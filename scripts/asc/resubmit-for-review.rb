#!/usr/bin/env ruby
# Resubmit the app for App Store review after a rejection.
#
# RUN ON THE MAC (asc-api.rb needs the .p8 in ~/.sanger-build):
#   ruby scripts/asc/resubmit-for-review.rb            # dry run
#   ruby scripts/asc/resubmit-for-review.rb --apply
#
# fastlane cannot do this. `deliver`'s submit_for_review dies with "Cannot
# submit for review - A review submission is already in progress", because a
# rejection leaves the original reviewSubmission open in UNRESOLVED_ISSUES.
#
# Three things that look like they should work, and do not (all observed
# against the live API on 2026-09-15):
#
#   PATCH submitted=true on the rejected submission
#     409 ENTITY_STATE_INVALID — a submission holding a REJECTED item cannot
#     be flipped back to submitted, whatever you do to the version.
#   DELETE the rejected item, to reuse the submission
#     409 "Item was already submitted".
#   POST a new submission and add the version to it
#     201 for the submission, then 409 ITEM_PART_OF_ANOTHER_SUBMISSION on the
#     item — the version is still held by the rejected submission.
#
# So the working order is: cancel the rejected submission, wait for it to reach
# a terminal state (it passes through CANCELING and settles as COMPLETE, which
# releases the version), create a new submission, add the version, submit.
# Cancelling is what the App Store Connect UI does for you when you resubmit
# after a rejection; the submission is already dead, and the version has
# already returned to PREPARE_FOR_SUBMISSION by the time this runs.
#
# Every step verifies by re-reading. Several of these calls return a success
# code for a change that did not happen.

require 'json'
require 'open3'

APP_ID = '6761436901'
ASC    = File.join(__dir__, 'asc-api.rb')

TERMINAL = %w[COMPLETE CANCELED].freeze
IN_FLIGHT = %w[WAITING_FOR_REVIEW IN_REVIEW COMPLETING].freeze

def api(method, path, body = nil)
  cmd = ['ruby', ASC, method, path]
  cmd << '-' if body
  out, err, status = Open3.capture3(*cmd, stdin_data: body || '')
  abort "asc-api.rb #{method} #{path} failed: #{err}" unless status.success?
  code = out.lines.first.to_s[/HTTP (\d+)/, 1].to_i
  json = out.split("\n", 2)[1]
  [code, (JSON.parse(json) rescue nil)]
end

def submissions
  code, body = api('GET', "/v1/reviewSubmissions?filter[app]=#{APP_ID}&limit=20")
  abort "reviewSubmissions query -> HTTP #{code}" unless code == 200
  body['data']
end

def editable_version
  code, body = api('GET', "/v1/apps/#{APP_ID}/appStoreVersions?limit=5")
  abort "versions query -> HTTP #{code}" unless code == 200
  body['data'].find { |v| v.dig('attributes', 'appStoreState') != 'READY_FOR_SALE' }
end

apply = ARGV.include?('--apply')

version = editable_version or abort 'no editable App Store version'
version_id = version['id']
_, build = api('GET', "/v1/appStoreVersions/#{version_id}/build")
build_number = build&.dig('data', 'attributes', 'version')
build_state  = build&.dig('data', 'attributes', 'processingState')

puts "version #{version.dig('attributes', 'versionString')} (#{version_id})"
puts "  state: #{version.dig('attributes', 'appStoreState')}"
puts "  build: #{build_number || 'NONE'} (#{build_state})"
abort 'version has no build attached — run attach-build.rb first' unless build_number
abort "build #{build_number} is #{build_state}, not VALID" unless build_state == 'VALID'

open = submissions.reject { |s| TERMINAL.include?(s.dig('attributes', 'state')) }
open.each { |s| puts "open submission #{s['id']} state=#{s.dig('attributes', 'state')}" }

if (live = open.find { |s| IN_FLIGHT.include?(s.dig('attributes', 'state')) })
  puts "already submitted and waiting on Apple (#{live.dig('attributes', 'state')}) — nothing to do"
  exit 0
end

unless apply
  puts "\ndry run — pass --apply to resubmit"
  exit 0
end

# 1. Clear anything still holding the version.
open.each do |s|
  next if s.dig('attributes', 'state') == 'READY_FOR_REVIEW' && s['id'] != nil &&
          (api('GET', "/v1/reviewSubmissions/#{s['id']}/items")[1]['data'] || []).empty?
  puts "cancelling submission #{s['id']}"
  body = { data: { type: 'reviewSubmissions', id: s['id'], attributes: { canceled: true } } }.to_json
  code, = api('PATCH', "/v1/reviewSubmissions/#{s['id']}", body)
  abort "cancel -> HTTP #{code}" unless code == 200

  # CANCELING is not terminal, and the version is not released until it is.
  30.times do
    _, now = api('GET', "/v1/reviewSubmissions/#{s['id']}")
    state = now.dig('data', 'attributes', 'state')
    break puts("  settled as #{state}") if TERMINAL.include?(state)
    sleep 10
  end
end

# 2. A fresh submission, or the empty one a previous run left behind.
empty = submissions.find do |s|
  s.dig('attributes', 'state') == 'READY_FOR_REVIEW' &&
    (api('GET', "/v1/reviewSubmissions/#{s['id']}/items")[1]['data'] || []).empty?
end

if empty
  submission_id = empty['id']
  puts "reusing empty submission #{submission_id}"
else
  body = {
    data: {
      type: 'reviewSubmissions',
      attributes: { platform: 'IOS' },
      relationships: { app: { data: { type: 'apps', id: APP_ID } } },
    },
  }.to_json
  code, created = api('POST', '/v1/reviewSubmissions', body)
  abort "create submission -> HTTP #{code}" unless code == 201
  submission_id = created['data']['id']
  puts "created submission #{submission_id}"
end

# 3. The version becomes the submission's only item.
body = {
  data: {
    type: 'reviewSubmissionItems',
    relationships: {
      reviewSubmission: { data: { type: 'reviewSubmissions', id: submission_id } },
      appStoreVersion: { data: { type: 'appStoreVersions', id: version_id } },
    },
  },
}.to_json
code, = api('POST', '/v1/reviewSubmissionItems', body)
abort "add item -> HTTP #{code}" unless code == 201
puts 'added version as submission item'

# 4. Submit, and confirm by re-reading.
body = {
  data: { type: 'reviewSubmissions', id: submission_id, attributes: { submitted: true } },
}.to_json
code, = api('PATCH', "/v1/reviewSubmissions/#{submission_id}", body)
abort "submit -> HTTP #{code}" unless code == 200

_, now = api('GET', "/v1/reviewSubmissions/#{submission_id}")
state = now.dig('data', 'attributes', 'state')
abort "NOT submitted — state is #{state.inspect}" unless IN_FLIGHT.include?(state)
puts "\nverified: submission #{submission_id} is #{state}, " \
     "submitted #{now.dig('data', 'attributes', 'submittedDate')}"
puts "version 1.0 is with Apple holding build #{build_number}"
