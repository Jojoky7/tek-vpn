package main

import (
	"net/netip"
	"os"
	"os/signal"
	"syscall"
)

// uplink is the real network connection the tunnel's own traffic leaves through.
type uplink struct {
	Name    string     // interface name, as Xray's sockopt "interface" expects it
	Index   int        // interface index
	Gateway netip.Addr // default gateway on that interface
	LUID    uint64     // Windows only
}

func handleSignals(quit func()) {
	ch := make(chan os.Signal, 1)
	signal.Notify(ch, os.Interrupt, syscall.SIGTERM)
	<-ch
	quit()
}
