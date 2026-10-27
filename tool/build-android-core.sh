#!/usr/bin/env bash
# Builds the core for Android (app/android/app/libs/tekcore.aar) with
# gomobile. Needs Go, the Android SDK with NDK 28, and
#   go install golang.org/x/mobile/cmd/gomobile@latest && gomobile init
set -euo pipefail
cd "$(dirname "$0")/../core"
gomobile bind \
  -target=android/arm64,android/arm \
  -androidapi 24 \
  -javapkg com.tekvpn \
  -trimpath \
  -ldflags="-s -w -buildid=" \
  -o ../app/android/app/libs/tekcore.aar \
  ./mobile
ls -la ../app/android/app/libs/
