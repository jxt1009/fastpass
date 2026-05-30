#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
project_dir="$(cd "$script_dir/.." && pwd)"
env_file="$project_dir/.env.fastlane"
keychain_service="com.toper.FastTrack.fastlane"

prompt() {
  local label="$1"
  local current_value="${2:-}"
  local input

  if [[ -n "$current_value" ]]; then
    read -r -p "$label [$current_value]: " input
    printf '%s' "${input:-$current_value}"
  else
    read -r -p "$label: " input
    printf '%s' "$input"
  fi
}

prompt_secret() {
  local label="$1"
  local input
  read -r -s -p "$label: " input
  echo >&2
  printf '%s' "$input"
}

store_in_keychain() {
  local account="$1"
  local secret="$2"
  security add-generic-password -U -s "$keychain_service" -a "$account" -w "$secret" >/dev/null
}

echo "Configuring FastTrack Apple release settings..."

bundle_id="$(prompt "App bundle ID" "com.toper.FastTrack")"
apple_id="$(prompt "Apple ID email" "${APPLE_ID:-}")"
team_id="$(prompt "Apple Developer Team ID" "${TEAM_ID:-}")"
itc_team_id="$(prompt "App Store Connect Team ID" "${ITC_TEAM_ID:-}")"
match_repo_url="$(prompt "Match repo URL" "${MATCH_GIT_URL:-}")"
match_password="$(prompt_secret "Match password")"
app_store_connect_key_id="$(prompt "App Store Connect API key ID" "${APP_STORE_CONNECT_KEY_ID:-}")"
app_store_connect_issuer_id="$(prompt "App Store Connect issuer ID" "${APP_STORE_CONNECT_ISSUER_ID:-}")"
app_store_connect_key_path="$(prompt "Path to the App Store Connect .p8 file" "${APP_STORE_CONNECT_API_KEY_PATH:-}")"
apple_key_id="$(prompt "Sign in with Apple key ID (optional, for account deletion revocation)" "${APPLE_KEY_ID:-}")"
apple_private_key_path=""
if [[ -n "$apple_key_id" ]]; then
  apple_private_key_path="$(prompt "Path to the Sign in with Apple .p8 file" "")"
fi

cat > "$env_file" <<EOF
FASTTRACK_APP_IDENTIFIER=$bundle_id
APPLE_ID=$apple_id
TEAM_ID=$team_id
ITC_TEAM_ID=$itc_team_id
MATCH_GIT_URL=$match_repo_url
MATCH_PASSWORD_KEYCHAIN_ACCOUNT=match_password
APP_STORE_CONNECT_KEY_ID=$app_store_connect_key_id
APP_STORE_CONNECT_ISSUER_ID=$app_store_connect_issuer_id
APP_STORE_CONNECT_API_KEY_PATH=$app_store_connect_key_path
EOF

store_in_keychain "match_password" "$match_password"

echo "Wrote $env_file"
echo
echo "Stored MATCH_PASSWORD in macOS Keychain service: $keychain_service"
echo
echo "GitHub Actions secrets still need to be added separately for CI/TestFlight uploads."
if [[ -n "$app_store_connect_key_path" && -f "$app_store_connect_key_path" ]]; then
  app_store_connect_key_content="$(sed ':a;N;$!ba;s/\n/\\n/g' "$app_store_connect_key_path")"
  echo "Add these GitHub Actions secrets for ios-release:"
  echo "APP_STORE_CONNECT_API_KEY=$app_store_connect_key_content"
  echo "APP_STORE_CONNECT_KEY_ID=$app_store_connect_key_id"
  echo "APP_STORE_CONNECT_ISSUER_ID=$app_store_connect_issuer_id"
else
  echo "Warning: $app_store_connect_key_path was not found, so App Store Connect GitHub secret output was skipped." >&2
fi

if [[ -n "$apple_key_id" && -n "$apple_private_key_path" ]]; then
  if [[ ! -f "$apple_private_key_path" ]]; then
    echo "Warning: $apple_private_key_path was not found, so backend Apple revocation secrets were not generated." >&2
    exit 0
  fi

  apple_private_key="$(sed ':a;N;$!ba;s/\n/\\n/g' "$apple_private_key_path")"

  echo
  echo "Add these backend secrets where FastTrack runs so Apple account deletion can revoke authorization:"
  echo "APPLE_APP_BUNDLE_ID=$bundle_id"
  echo "APPLE_TEAM_ID=$team_id"
  echo "APPLE_KEY_ID=$apple_key_id"
  echo "APPLE_PRIVATE_KEY=$apple_private_key"
fi
