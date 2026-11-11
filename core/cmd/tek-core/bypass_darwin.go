//go:build darwin

package main

import (
	"context"
	"net/netip"
	"strings"
	"sync"

	xnet "github.com/xtls/xray-core/common/net"
	"github.com/xtls/xray-core/transport/internet"

	"github.com/jojoky7/tek-vpn/core/tek"
)

// In the "all traffic" mode Xray's own sockets are bound to the real
// network interface, and macOS then refuses every address that has no
// route of its own on that interface: the two halves of the default route
// that lead into the tunnel hide the real default route from the bound
// socket, and the connection fails at once with "network is unreachable"
// (Rofl's log from 1.1.0: every site that goes around the VPN and the DNS
// query to 77.88.8.8 failed, while the servers, which have host routes,
// worked). So, as on Windows (see bypass_windows.go), every address Xray
// dials gets the same kind of host route through the real gateway, just
// before the dial, for as long as the tunnel is up.

func init() {
	internet.UseAlternativeSystemDialer(bypassDialer{inner: &internet.DefaultSystemDialer{}})
}

type bypassDialer struct {
	inner internet.SystemDialer
}

func (d bypassDialer) Dial(ctx context.Context, src xnet.Address, dest xnet.Destination, sockopt *internet.SocketConfig) (xnet.Conn, error) {
	if dest.Address != nil && dest.Address.Family().IsIP() {
		if ip, ok := netip.AddrFromSlice(dest.Address.IP()); ok {
			bypass.route(ip.Unmap())
		}
	}
	return d.inner.Dial(ctx, src, dest, sockopt)
}

func (d bypassDialer) DestIpAddress() xnet.IP {
	return d.inner.DestIpAddress()
}

type bypassRoutes struct {
	mu      sync.Mutex
	armed   bool
	gateway string
	known   map[netip.Addr]bool // routed already, by us or by the system
	added   []string            // created by us, removed on disarm
}

var bypass = &bypassRoutes{}

// arm starts adding host routes through the uplink. skip lists the routes
// set up with the tunnel itself.
func (b *bypassRoutes) arm(up uplink, skip []netip.Addr) {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.armed = up.Gateway.Is4()
	b.gateway = up.Gateway.String()
	b.known = map[netip.Addr]bool{}
	b.added = nil
	for _, ip := range skip {
		b.known[ip] = true
	}
}

// disarm stops adding routes and removes the ones it added.
func (b *bypassRoutes) disarm() {
	b.mu.Lock()
	defer b.mu.Unlock()
	for _, ip := range b.added {
		_, _ = run("/sbin/route", "-q", "-n", "delete", "-host", ip, b.gateway)
	}
	if len(b.added) > 0 {
		tek.Logs.Printf("info", "removed %d direct route(s)", len(b.added))
	}
	b.armed = false
	b.known = nil
	b.added = nil
}

func (b *bypassRoutes) route(ip netip.Addr) {
	if !needsDirectRoute(ip) {
		return
	}
	b.mu.Lock()
	defer b.mu.Unlock()
	if !b.armed || b.known[ip] {
		return
	}
	_, err := run("/sbin/route", "-q", "-n", "add", "-host", ip.String(), b.gateway)
	switch {
	case err == nil:
		b.added = append(b.added, ip.String())
		b.known[ip] = true
	case strings.Contains(err.Error(), "File exists"):
		b.known[ip] = true
	default:
		tek.Logs.Printf("warning", "direct route: %v", err)
	}
}
