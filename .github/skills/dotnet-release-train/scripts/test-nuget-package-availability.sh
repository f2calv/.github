#!/usr/bin/env bash
# Poll NuGet's restore endpoint until an exact version is available for every package ID.
# Optional environment variables: NUGET_TIMEOUT_SECONDS, NUGET_INITIAL_DELAY_SECONDS,
# NUGET_MAXIMUM_DELAY_SECONDS.

set -euo pipefail

usage() {
  echo "Usage: $0 <version> <package-id> [package-id ...]"
}

if [[ $# -lt 2 ]]; then
  usage
  exit 1
fi

for command_name in curl jq; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "::error::Required command is unavailable: $command_name"
    exit 1
  fi
done

version="$1"
shift
package_ids=("$@")
timeout_seconds="${NUGET_TIMEOUT_SECONDS:-600}"
initial_delay_seconds="${NUGET_INITIAL_DELAY_SECONDS:-5}"
maximum_delay_seconds="${NUGET_MAXIMUM_DELAY_SECONDS:-30}"
base_uri="https://api.nuget.org/v3-flatcontainer/"

if [[ ! "$version" =~ ^[0-9A-Za-z.+-]+$ ]]; then
  echo "::error::Invalid NuGet version: $version"
  exit 1
fi

for package_id in "${package_ids[@]}"; do
  if [[ ! "$package_id" =~ ^[A-Za-z0-9_.-]+$ ]]; then
    echo "::error::Invalid NuGet package ID: $package_id"
    exit 1
  fi
done

if [[ ! "$timeout_seconds" =~ ^[1-9][0-9]*$ \
  || ! "$initial_delay_seconds" =~ ^[1-9][0-9]*$ \
  || ! "$maximum_delay_seconds" =~ ^[1-9][0-9]*$ ]]; then
  echo "::error::Polling delays and timeout must be positive integers."
  exit 1
fi

base_uri="${base_uri%/}/"
normalized_version="${version,,}"
declare -A available=()
start_seconds=$SECONDS
delay_seconds=$initial_delay_seconds
response_file=$(mktemp)
trap 'rm -f "$response_file"' EXIT

while true; do
  pending_count=0

  for package_id in "${package_ids[@]}"; do
    if [[ "${available[$package_id]:-false}" == "true" ]]; then
      continue
    fi

    normalized_id="${package_id,,}"
    index_uri="${base_uri}${normalized_id}/index.json"
    elapsed_seconds=$((SECONDS - start_seconds))
    remaining_seconds=$((timeout_seconds - elapsed_seconds))
    if ((remaining_seconds <= 0)); then
      pending_count=$((pending_count + 1))
      continue
    fi

    request_timeout=$remaining_seconds
    if ((request_timeout > 30)); then
      request_timeout=30
    fi

    http_code=$(curl --silent --show-error --max-time "$request_timeout" \
      --output "$response_file" --write-out '%{http_code}' "$index_uri" || true)
    if [[ "$http_code" =~ ^2[0-9][0-9]$ ]] \
      && jq --exit-status --arg version "$normalized_version" \
        '.versions | map(ascii_downcase) | index($version) != null' \
        "$response_file" >/dev/null; then
      available[$package_id]=true
      echo "$package_id $version is available."
    elif [[ "$http_code" != "000" && "$http_code" != "404" && "$http_code" != "429" ]]; then
      echo "::error::NuGet request for $package_id failed permanently with HTTP $http_code."
      exit 1
    else
      pending_count=$((pending_count + 1))
    fi
  done

  if ((pending_count == 0)); then
    exit 0
  fi

  elapsed_seconds=$((SECONDS - start_seconds))
  if ((elapsed_seconds >= timeout_seconds)); then
    for package_id in "${package_ids[@]}"; do
      if [[ "${available[$package_id]:-false}" != "true" ]]; then
        echo "::error::$package_id $version was unavailable after ${timeout_seconds}s."
      fi
    done
    exit 2
  fi

  remaining_seconds=$((timeout_seconds - elapsed_seconds))
  sleep_seconds=$delay_seconds
  if ((sleep_seconds > remaining_seconds)); then
    sleep_seconds=$remaining_seconds
  fi

  sleep "$sleep_seconds"
  delay_seconds=$((delay_seconds * 2))
  if ((delay_seconds > maximum_delay_seconds)); then
    delay_seconds=$maximum_delay_seconds
  fi
done
