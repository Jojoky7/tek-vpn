package main

import (
	"net/netip"
	"testing"
)

func TestNeedsDirectRoute(t *testing.T) {
	for addr, want := range map[string]bool{
		"185.104.210.59":  true, // funpay.com
		"77.88.8.8":       true,
		"192.168.3.1":     false,
		"10.5.45.104":     false,
		"172.19.0.2":      false,
		"100.100.100.100": false,
		"169.254.10.1":    false,
		"127.0.0.1":       false,
		"224.0.0.251":     false,
		"255.255.255.255": false,
		"0.0.0.0":         false,
		"2a02:6b8::feed":  false,
	} {
		if got := needsDirectRoute(netip.MustParseAddr(addr)); got != want {
			t.Errorf("needsDirectRoute(%s) = %v, want %v", addr, got, want)
		}
	}
}
