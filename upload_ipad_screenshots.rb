# Upload the six iPad 12.9" screenshots to the en-US APP_IPAD_PRO_3GEN_129 set,
# and set the app-level contentRightsDeclaration the ASC API demanded.
require "spaceship"

Spaceship::ConnectAPI.token = Spaceship::ConnectAPI::Token.create(
  key_id: ENV.fetch("APP_STORE_CONNECT_API_KEY_KEY_ID"),
  issuer_id: ENV.fetch("APP_STORE_CONNECT_API_KEY_ISSUER_ID"),
  filepath: ENV.fetch("APP_STORE_CONNECT_API_KEY_KEY_FILEPATH")
)

app = Spaceship::ConnectAPI::App.get(app_id: "6761436901")

# The app displays OpenStreetMap-derived map tiles (MapLibre) — third-party
# content used under its open license, with attribution shown in-app.
app.update(attributes: { contentRightsDeclaration: "USES_THIRD_PARTY_CONTENT" })
app_check = Spaceship::ConnectAPI::App.get(app_id: "6761436901")
puts "contentRightsDeclaration: #{app_check.content_rights_declaration.inspect}"

version = app.get_edit_app_store_version
abort "No editable version" unless version

loc = version.get_app_store_version_localizations.find { |l| l.locale == "en-US" }
abort "No en-US localization" unless loc

set = loc.get_app_screenshot_sets.find { |s| s.screenshot_display_type == "APP_IPAD_PRO_3GEN_129" }
set ||= loc.create_app_screenshot_set(attributes: { screenshotDisplayType: "APP_IPAD_PRO_3GEN_129" })
puts "Set #{set.id} (#{set.screenshot_display_type})"

# Idempotent: purge whatever is there, then upload the six in order.
# (A freshly created set has a nil app_screenshots relation.)
(set.app_screenshots || []).each { |s| puts "purging #{s.file_name}"; s.delete! }

Dir.glob("/Users/jackson/Chirp/screenshots/ipad/*-ipad129.png").sort.each do |path|
  puts "uploading #{File.basename(path)}"
  Spaceship::ConnectAPI::AppScreenshot.create(
    app_screenshot_set_id: set.id, path: path, wait_for_processing: true
  )
end

final_set = loc.get_app_screenshot_sets.find { |s| s.screenshot_display_type == "APP_IPAD_PRO_3GEN_129" }
(final_set.app_screenshots || []).each do |s|
  state = s.asset_delivery_state ? s.asset_delivery_state["state"] : "?"
  puts "  #{s.file_name}  #{state}"
end
