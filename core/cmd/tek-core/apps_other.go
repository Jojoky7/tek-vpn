//go:build !windows

package main

type appInfo struct {
	Name        string `json:"name"`
	Path        string `json:"path"`
	Description string `json:"description,omitempty"`
}

// runningApps: on macOS the app lists the programs itself.
func runningApps() []appInfo { return nil }
