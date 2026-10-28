package main

import (
	"context"
	"errors"
	"net/netip"
	"sync"

	xnet "github.com/xtls/xray-core/common/net"
	"github.com/xtls/xray-core/transport/internet"
	"golang.org/x/sys/windows"
	"golang.zx2c4.com/wireguard/windows/tunnel/winipcfg"

	"github.com/jojoky7/tek-vpn/core/tek"
)

// In the "all traffic" mode Windows sends Xray's own direct connections
// into the tunnel even when the socket is bound to the real network card
// and its address (Rofl's logs from 1.0.4 and 1.0.5: every site that goes
// around the VPN hung, while the servers, which have host routes, worked).
// So every address Xray dials gets the same kind of host route through the
// real gateway, just before the dial, for as long as the tunnel is up.

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
	luid    winipcfg.LUID
	gateway netip.Addr
	known   map[netip.Addr]bool // routed already, by us or by the system
	added   []netip.Prefix      // created by us, removed on disarm
}

var bypass = &bypassRoutes{}

// cgnat is the carrier-grade NAT range, which Tailscale and similar
// networks use on their own interfaces.
var cgnat = netip.MustParsePrefix("100.64.0.0/10")

// arm starts adding host routes through the uplink. skip lists the routes
// set up with the tunnel itself.
func (b *bypassRoutes) arm(up uplink, skip []netip.Addr) {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.armed = up.Gateway.Is4()
	b.luid = winipcfg.LUID(up.LUID)
	b.gateway = up.Gateway
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
	if b.armed || len(b.added) > 0 {
		for _, p := range b.added {
			_ = b.luid.DeleteRoute(p, b.gateway)
		}
		if len(b.added) > 0 {
			tek.Logs.Printf("info", "removed %d direct route(s)", len(b.added))
		}
	}
	b.armed = false
	b.known = nil
	b.added = nil
}

func (b *bypassRoutes) route(ip netip.Addr) {
	if !ip.Is4() || ip.IsLoopback() || ip.IsPrivate() || ip.IsLinkLocalUnicast() ||
		ip.IsMulticast() || ip.IsUnspecified() || cgnat.Contains(ip) ||
		ip == netip.AddrFrom4([4]byte{255, 255, 255, 255}) {
		return
	}
	b.mu.Lock()
	defer b.mu.Unlock()
	if !b.armed || b.known[ip] {
		return
	}
	prefix := netip.PrefixFrom(ip, 32)
	err := b.luid.AddRoute(prefix, b.gateway, 0)
	switch {
	case err == nil:
		b.added = append(b.added, prefix)
		b.known[ip] = true
	case errors.Is(err, windows.ERROR_OBJECT_ALREADY_EXISTS):
		b.known[ip] = true
	default:
		tek.Logs.Printf("warning", "direct route to %s: %v", ip, err)
	}
}
