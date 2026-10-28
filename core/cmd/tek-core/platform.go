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
	// Addr is the interface's IPv4 address (Windows only). Windows picks the
	// source address from the routing table even for a socket bound to an
	// interface, and with the tunnel up that is the tunnel's address, so
	// direct connections are also bound to this one.
	Addr netip.Addr
}

func handleSignals(quit func()) {
	ch := make(chan os.Signal, 1)
	signal.Notify(ch, os.Interrupt, syscall.SIGTERM)
	<-ch
	quit()
}
