#!/usr/bin/env bash
# Prints VERSION and BUILD for the build: the tag's version (v1.2.3) when
# the build runs for a tag, otherwise the one in app/pubspec.yaml.
set -euo pipefail
line=$(grep -E '^version:' "$(dirname "$0")/../../app/pubspec.yaml" | head -1)
pub=${line#version: }
version=${pub%%+*}
build=${pub#*+}
[ "$build" = "$pub" ] && build=1
if [[ "${GITHUB_REF:-}" == refs/tags/v* ]]; then
  version=${GITHUB_REF#refs/tags/v}
fi
echo "VERSION=$version"
echo "BUILD=$build"
