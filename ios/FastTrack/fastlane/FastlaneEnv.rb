require "json"
require "tmpdir"

env_file = File.expand_path("../.env.fastlane", __dir__)
keychain_services = ["com.toper.FastTrack.fastlane", "dev.toper.FastTrack.fastlane"]

if File.exist?(env_file)
  File.readlines(env_file, chomp: true).each do |line|
    next if line.strip.empty? || line.lstrip.start_with?("#")

    key, value = line.split("=", 2)
    next if key.nil? || value.nil? || !ENV[key].to_s.empty?

    ENV[key] = value
  end
end

app_store_connect_key_path = ENV["APP_STORE_CONNECT_API_KEY_PATH"].to_s
if !app_store_connect_key_path.empty?
  app_store_connect_key_path = File.expand_path(app_store_connect_key_path)
  ENV["APP_STORE_CONNECT_API_KEY_PATH"] = app_store_connect_key_path
end

if !app_store_connect_key_path.empty? && File.extname(app_store_connect_key_path) == ".p8"
  ENV["APP_STORE_CONNECT_P8_PATH"] ||= app_store_connect_key_path
  File.write(
    File.join(Dir.tmpdir, "fasttrack-app-store-connect-key.json"),
    JSON.pretty_generate(
      key_id: ENV["APP_STORE_CONNECT_KEY_ID"],
      issuer_id: ENV["APP_STORE_CONNECT_ISSUER_ID"],
      key: File.read(app_store_connect_key_path),
      in_house: false
    )
  )
  ENV["APP_STORE_CONNECT_API_KEY_PATH"] = File.join(Dir.tmpdir, "fasttrack-app-store-connect-key.json")
end

def keychain_secret(key, services)
  account = ENV["#{key}_KEYCHAIN_ACCOUNT"].to_s
  return "" if account.empty?

  Array(services).each do |service|
    secret = `security find-generic-password -s "#{service}" -a "#{account}" -w 2>/dev/null`.to_s.strip
    return secret unless secret.empty?
  end

  ""
end

match_password = ENV["MATCH_PASSWORD"].to_s
if match_password.empty?
  match_password = keychain_secret("MATCH_PASSWORD", keychain_services)
  ENV["MATCH_PASSWORD"] = match_password unless match_password.empty?
end

def fastlane_env!(key)
  value = ENV[key].to_s
  if value.empty?
    value = keychain_secret(key, ["com.toper.FastTrack.fastlane", "dev.toper.FastTrack.fastlane"])
    ENV[key] = value unless value.empty?
  end
  UI.user_error!("Missing required Fastlane env var: #{key}") if value.empty?
  value
end
