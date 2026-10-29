package main

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"path/filepath"

	"github.com/jojoky7/tek-vpn/core/tek"
)

// daemon runs tek-core as the macOS helper: a launchd service with root
// rights that the app installs once, so the "all traffic" mode no longer
// asks for the administrator password on every connection. It serves the
// same API as "serve" for one user: its port and a fresh token go into a
// file only that user can read.
func daemon(args []string) error {
	fs := flag.NewFlagSet("daemon", flag.ContinueOnError)
	owner := fs.Int("owner", -1, "user id of the person who installed the helper")
	dir := fs.String("dir", "", "directory for the helper's files")
	logLevel := fs.String("log-level", "warning", "journal level")
	if err := fs.Parse(args); err != nil {
		return err
	}
	if *owner < 0 || *dir == "" {
		return errors.New("-owner and -dir are required")
	}
	if !isElevated() {
		return errors.New("the helper has to run as root")
	}
	if err := os.MkdirAll(*dir, 0o755); err != nil {
		return err
	}
	tek.Logs.SetLevel(*logLevel)

	raw := make([]byte, 32)
	if _, err := rand.Read(raw); err != nil {
		return err
	}
	token := hex.EncodeToString(raw)
	path := filepath.Join(*dir, fmt.Sprintf("helper-%d.json", *owner))
	ready := func(port int) error {
		data, _ := json.Marshal(map[string]any{
			"port": port, "pid": os.Getpid(), "elevated": true, "version": version, "token": token,
		})
		return writeFileAtomic(path, data, 0o600, *owner)
	}
	return runAPI(apiOptions{dataDir: *dir, token: token, daemon: true, ready: ready})
}
