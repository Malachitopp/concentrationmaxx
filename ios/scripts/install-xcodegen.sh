#!/usr/bin/env bash
# Downloads a pinned XcodeGen release, verifies its checksum and puts it on the PATH
# of the following GitHub Actions steps.
#
# Usage: ios/scripts/install-xcodegen.sh <version> <sha256 of xcodegen.zip>
set -euo pipefail

version="$1"
expected_sha="$2"
dir="${RUNNER_TEMP:-/tmp}/xcodegen-${version}"

if [ ! -x "${dir}/xcodegen/bin/xcodegen" ]; then
  mkdir -p "${dir}"
  curl --fail --silent --show-error --location --retry 3 \
    --output "${dir}/xcodegen.zip" \
    "https://github.com/yonaskolb/XcodeGen/releases/download/${version}/xcodegen.zip"
  actual_sha="$(shasum -a 256 "${dir}/xcodegen.zip" | awk '{print $1}')"
  if [ "${actual_sha}" != "${expected_sha}" ]; then
    echo "::error::xcodegen.zip checksum mismatch: expected ${expected_sha}, got ${actual_sha}"
    exit 1
  fi
  unzip -q -o "${dir}/xcodegen.zip" -d "${dir}"
fi

if [ -n "${GITHUB_PATH:-}" ]; then
  echo "${dir}/xcodegen/bin" >> "${GITHUB_PATH}"
fi
"${dir}/xcodegen/bin/xcodegen" --version
