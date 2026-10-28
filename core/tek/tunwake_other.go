//go:build !windows && !android

package tek

// Elsewhere the device is a file, and closing it ends a pending read.
func wakeReader(closer) {}
