//go:build !windows && !linux && !darwin

// Tek: this file replaces Xray's own in the macOS build of tek-core
// (go build -overlay), so that find_process_darwin.go can take its place.

package net

import (
	"github.com/xtls/xray-core/common/errors"
)

func FindProcess(dest Destination) (int, string, string, error) {
	return 0, "", "", errors.New("process lookup is not supported on this platform")
}
