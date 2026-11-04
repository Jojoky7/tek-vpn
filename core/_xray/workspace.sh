#!/bin/sh
# Prepares a copy of Xray with macOS process lookup (see darwinproc) and
# prints a go.work file that builds tek-core against it. Run from core/:
#   GOWORK="$(_xray/workspace.sh)" GOOS=darwin go build ./cmd/tek-core
# Go does not allow -overlay on the module cache, so the files are copied.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
core=$(dirname "$here")
GOWORK=off go mod download github.com/xtls/xray-core
src=$(GOWORK=off go list -m -f '{{.Dir}}' github.com/xtls/xray-core)
work=${TMPDIR:-/tmp}/tek-xray
rm -rf "$work"
mkdir -p "$work"
cp -R "$src" "$work/xray-core"
chmod -R u+w "$work/xray-core"
cp "$here/common/net/find_process_others.go" "$here/common/net/find_process_darwin.go" \
  "$work/xray-core/common/net/"
gover=$(sed -n 's/^go //p' "$core/go.mod")
cat > "$work/go.work" <<WORK
go $gover

use (
	$core
	$work/xray-core
)
WORK
echo "$work/go.work"
