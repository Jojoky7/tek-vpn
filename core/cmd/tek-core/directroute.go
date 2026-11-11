package main

import "net/netip"

// cgnatNet is the carrier-grade NAT range, which Tailscale and similar
// networks use on their own interfaces.
var cgnatNet = netip.MustParsePrefix("100.64.0.0/10")

// needsDirectRoute tells whether a connection to ip that goes around the
// tunnel needs a host route through the real gateway: only public IPv4
// addresses do, the local ones already have routes of their own.
func needsDirectRoute(ip netip.Addr) bool {
	return ip.Is4() && !ip.IsLoopback() && !ip.IsPrivate() && !ip.IsLinkLocalUnicast() &&
		!ip.IsMulticast() && !ip.IsUnspecified() && !cgnatNet.Contains(ip) &&
		ip != netip.AddrFrom4([4]byte{255, 255, 255, 255})
}
