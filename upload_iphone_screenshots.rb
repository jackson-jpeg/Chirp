# Upload the six iPhone screenshots to the en-US 6.5" and 6.9" sets.
#
# RUN ON THE MAC:
#   source ~/.sanger-build/secrets.env && ruby upload_iphone_screenshots.rb
#
# deliver is supposed to do this — the appstore_submit lane purges first and
# passes overwrite_screenshots — but on 2026-09-15 the purge silently did
# nothing and deliver APPENDED instead. The sets ended up holding the previous
# six plus four of the new six, because Apple caps a set at 10 and the upload
# ran out of slots partway through. The visible damage was the worst kind: the
# only 05-map in the set was the STALE one, so a resubmission about a changed
# Map screen would have shipped the old Map screenshot while reporting success.
#
# So the iPhone sets are managed the same explicit way as the iPad set: delete
# every screenshot by id, upload the six in filename order, then re-read and
# print what ASC actually holds. Same code path, same guarantees, one place to
# look when a set is wrong.

require "spaceship"

SETS = {
  "APP_IPHONE_67" => "/Users/jackson/Chirp/fastlane/screenshots/en-US/*-69.png",
  "APP_IPHONE_65" => "/Users/jackson/Chirp/fastlane/screenshots/en-US/*-65.png",
}.freeze

Spaceship::ConnectAPI.token = Spaceship::ConnectAPI::Token.create(
  key_id: ENV.fetch("APP_STORE_CONNECT_API_KEY_KEY_ID"),
  issuer_id: ENV.fetch("APP_STORE_CONNECT_API_KEY_ISSUER_ID"),
  filepath: ENV.fetch("APP_STORE_CONNECT_API_KEY_KEY_FILEPATH")
)

app = Spaceship::ConnectAPI::App.get(app_id: "6761436901")
version = app.get_edit_app_store_version
abort "No editable version" unless version

loc = version.get_app_store_version_localizations.find { |l| l.locale == "en-US" }
abort "No en-US localization" unless loc

SETS.each do |display_type, glob|
  set = loc.get_app_screenshot_sets.find { |s| s.screenshot_display_type == display_type }
  set ||= loc.create_app_screenshot_set(attributes: { screenshotDisplayType: display_type })
  puts "== #{display_type} (set #{set.id})"

  (set.app_screenshots || []).each { |s| puts "  purging #{s.file_name}"; s.delete! }

  paths = Dir.glob(glob).sort
  abort "no files matched #{glob}" if paths.empty?
  abort "#{paths.size} files matched #{glob}, expected 6" unless paths.size == 6

  paths.each do |path|
    puts "  uploading #{File.basename(path)}"
    Spaceship::ConnectAPI::AppScreenshot.create(
      app_screenshot_set_id: set.id, path: path, wait_for_processing: true
    )
  end
end

# Verify by re-reading. The whole reason this file exists is that an upload
# reporting success is not evidence the set is right.
puts "\nfinal state:"
loc.get_app_screenshot_sets.each do |set|
  shots = set.app_screenshots || []
  puts "== #{set.screenshot_display_type}: #{shots.size} shots"
  shots.each do |s|
    state = s.asset_delivery_state ? s.asset_delivery_state["state"] : "?"
    puts "  #{s.file_name}  #{state}"
  end
  warn "  WARNING: expected 6, found #{shots.size}" unless shots.size == 6
end
