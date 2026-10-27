//go:build !windows && !darwin

package main

import (
	"errors"
	"net/netip"
	"os"
	"syscall"
	"time"
)

// Linux is not a release target; tek-core builds there for tests, with the
// proxy mode only.

type tunState struct {
	Name string `json:"name"`
}

type proxyState struct{}

func isElevated() bool { return os.Geteuid() == 0 }

func tunName(requested string) string {
	if requested == "" {
		return "tek0"
	}
	return requested
}

func detectUplink() (uplink, error) {
	return uplink{}, errors.New("the TUN mode is not supported on this system")
}

func setupTun(string, uplink, []netip.Addr, tunOptions) (*tunState, error) {
	return nil, errors.New("the TUN mode is not supported on this system")
}

func teardownTun(*tunState) {}

func setSystemProxy(proxySettings) (*proxyState, error) {
	return nil, nil
}

func restoreSystemProxy(*proxyState) {}

func watchParent(pid int, onExit func()) {
	for {
		if err := syscall.Kill(pid, 0); err != nil && !errors.Is(err, syscall.EPERM) {
			onExit()
			return
		}
		time.Sleep(2 * time.Second)
	}
}
