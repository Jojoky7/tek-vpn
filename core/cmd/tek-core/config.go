package main

import (
	"context"
	"encoding/json"
	"errors"
	"net"
	"net/netip"
	"time"
)

// xrayConfig is an Xray JSON config handled as plain maps, so tek-core can
// adjust the parts it owns (tun inbound, socket binding) and pass everything
// else through untouched.
type xrayConfig map[string]any

func parseConfig(raw json.RawMessage) (xrayConfig, error) {
	var cfg xrayConfig
	if err := json.Unmarshal(raw, &cfg); err != nil {
		return nil, err
	}
	if cfg == nil {
		return nil, errors.New("empty config")
	}
	return cfg, nil
}

func (c xrayConfig) bytes() ([]byte, error) {
	return json.Marshal(map[string]any(c))
}

func (c xrayConfig) list(key string) []any {
	v, _ := c[key].([]any)
	return v
}

func asMap(v any) map[string]any {
	m, _ := v.(map[string]any)
	return m
}

func child(m map[string]any, key string) map[string]any {
	if existing := asMap(m[key]); existing != nil {
		return existing
	}
	created := map[string]any{}
	m[key] = created
	return created
}

// bindOutbounds makes every outbound that opens real sockets use the given
// interface. In TUN mode the default route points into the tunnel, so
// without this Xray's own connections would loop back into it.
func (c xrayConfig) bindOutbounds(iface string) {
	for _, item := range c.list("outbounds") {
		ob := asMap(item)
		if ob == nil {
			continue
		}
		switch ob["protocol"] {
		case "blackhole", "dns", "loopback":
			continue
		}
		stream := child(ob, "streamSettings")
		sockopt := child(stream, "sockopt")
		sockopt["interface"] = iface
	}
}

// setTunName sets the interface name of every tun inbound.
func (c xrayConfig) setTunName(name string) bool {
	found := false
	for _, item := range c.list("inbounds") {
		in := asMap(item)
		if in == nil || in["protocol"] != "tun" {
			continue
		}
		settings := child(in, "settings")
		settings["name"] = name
		found = true
	}
	return found
}

// serverHosts lists the addresses of the remote servers in the outbounds.
func (c xrayConfig) serverHosts() []string {
	seen := map[string]bool{}
	var hosts []string
	add := func(v any) {
		if s, ok := v.(string); ok && s != "" && !seen[s] {
			seen[s] = true
			hosts = append(hosts, s)
		}
	}
	for _, item := range c.list("outbounds") {
		ob := asMap(item)
		settings := asMap(ob["settings"])
		if settings == nil {
			continue
		}
		add(settings["address"])
		for _, key := range []string{"vnext", "servers"} {
			list, _ := settings[key].([]any)
			for _, s := range list {
				add(asMap(s)["address"])
			}
		}
	}
	return hosts
}

// resolveHosts turns server hosts into IP addresses, before the tunnel exists.
func resolveHosts(hosts []string) []netip.Addr {
	var out []netip.Addr
	seen := map[netip.Addr]bool{}
	for _, h := range hosts {
		if ip, err := netip.ParseAddr(h); err == nil {
			if !seen[ip] {
				seen[ip] = true
				out = append(out, ip.Unmap())
			}
			continue
		}
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		ips, err := net.DefaultResolver.LookupNetIP(ctx, "ip", h)
		cancel()
		if err != nil {
			continue
		}
		for _, ip := range ips {
			ip = ip.Unmap()
			if !seen[ip] {
				seen[ip] = true
				out = append(out, ip)
			}
		}
	}
	return out
}
