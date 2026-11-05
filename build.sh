#!/bin/zsh
# Build-only check for the simulator (never boots one). Usage: ./build.sh [derivedDataPath]
DD=${1:-/tmp/pawmiaw-negocios-dd}
xcodebuild build -project "$(dirname $0)/PawMiawNegocios.xcodeproj" -scheme PawMiawNegocios \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath "$DD" CODE_SIGNING_ALLOWED=NO 2>&1 \
  | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | grep -v "^\s*|" | sort -u | head -80
