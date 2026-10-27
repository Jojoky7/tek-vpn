// Package tekcore is the Android binding of the Tek core, built with
// `gomobile bind`. Every call takes and returns plain strings so the Kotlin
// side stays simple.
package tekcore

import (
	"encoding/json"
	"os"
	"strconv"
	"time"

	"github.com/jojoky7/tek-vpn/core/tek"
)

// Start runs Xray with the given config. tunFd is the descriptor from
// VpnService.Builder.establish(); Xray's tun inbound reads it from the
// xray.tun.fd environment variable. assetDir holds geoip.dat and geosite.dat.
func Start(configJSON string, tunFd int, assetDir string) error {
	if tunFd > 0 {
		_ = os.Setenv("XRAY_TUN_FD", strconv.Itoa(tunFd))
	}
	if assetDir != "" {
		_ = os.Setenv("XRAY_LOCATION_ASSET", assetDir)
	}
	return tek.Default.Start([]byte(configJSON))
}

// Stop stops Xray.
func Stop() error {
	return tek.Default.Stop()
}

// IsRunning reports whether Xray is running.
func IsRunning() bool {
	running, _ := tek.Default.Running()
	return running
}

// Traffic returns {"up","down"} in bytes through the "proxy" outbound since
// the VPN started, as JSON.
func Traffic() string {
	up, down := tek.Default.Traffic("proxy")
	return mustJSON(map[string]int64{"up": up, "down": down})
}

// Validate returns an empty string when Xray accepts the config, or the error.
func Validate(configJSON string) string {
	if err := tek.Validate([]byte(configJSON)); err != nil {
		return err.Error()
	}
	return ""
}

// RealPing takes a tek.RealPingRequest as JSON and returns []tek.PingResult as JSON.
func RealPing(requestJSON string, assetDir string) string {
	if assetDir != "" {
		_ = os.Setenv("XRAY_LOCATION_ASSET", assetDir)
	}
	var req tek.RealPingRequest
	if err := json.Unmarshal([]byte(requestJSON), &req); err != nil {
		return errorJSON(err)
	}
	return mustJSON(tek.Default.RealPing(req))
}

// TCPPing takes {"targets":[{"host","port"}],"timeoutMs","attempts"} and
// returns []tek.PingResult as JSON.
func TCPPing(requestJSON string) string {
	var req struct {
		Targets   []tek.TCPTarget `json:"targets"`
		TimeoutMs int             `json:"timeoutMs"`
		Attempts  int             `json:"attempts"`
	}
	if err := json.Unmarshal([]byte(requestJSON), &req); err != nil {
		return errorJSON(err)
	}
	return mustJSON(tek.TCPPing(req.Targets, time.Duration(req.TimeoutMs)*time.Millisecond, req.Attempts, nil))
}

// CancelPing aborts a running check.
func CancelPing() {
	tek.CancelPing()
}

// Version returns the Xray-core version.
func Version() string {
	return tek.Version()
}

// SetLogLevel sets the journal level: error, warning, info or debug.
func SetLogLevel(level string) {
	tek.Logs.SetLevel(level)
}

// Log adds a line from the Android side to the journal.
func Log(level, text string) {
	tek.Logs.Printf(level, "%s", text)
}

// Logs returns the journal lines newer than sinceID as JSON.
func Logs(sinceID int64) string {
	return mustJSON(tek.Logs.Since(sinceID))
}

func mustJSON(v any) string {
	b, err := json.Marshal(v)
	if err != nil {
		return errorJSON(err)
	}
	return string(b)
}

func errorJSON(err error) string {
	b, _ := json.Marshal(map[string]string{"error": err.Error()})
	return string(b)
}
