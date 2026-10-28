//go:build windows

package main

import (
	"crypto/md5"
	"errors"
	"fmt"
	"math"
	"net/netip"
	"time"
	"unsafe"

	"golang.org/x/sys/windows"
	"golang.zx2c4.com/wireguard/windows/tunnel/winipcfg"

	"github.com/jojoky7/tek-vpn/core/tek"
)

// tunState is what setupTun changed, kept so it can be undone after a crash.
type tunState struct {
	Name       string   `json:"name"`
	UplinkLUID uint64   `json:"uplinkLuid"`
	Gateway    string   `json:"gateway"`
	HostRoutes []string `json:"hostRoutes"`
}

func isElevated() bool {
	return windows.GetCurrentProcessToken().IsElevated()
}

func tunName(requested string) string {
	if requested == "" {
		return "Tek"
	}
	return requested
}

// detectUplink finds the interface of the IPv4 default route with the best metric.
func detectUplink() (uplink, error) {
	rows, err := winipcfg.GetIPForwardTable2(windows.AF_INET)
	if err != nil {
		return uplink{}, err
	}
	best := uplink{}
	bestMetric := uint32(math.MaxUint32)
	for i := range rows {
		row := &rows[i]
		if row.DestinationPrefix.PrefixLength != 0 {
			continue
		}
		iface, err := row.InterfaceLUID.Interface()
		if err != nil || iface.OperStatus != winipcfg.IfOperStatusUp {
			continue
		}
		if iface.Type == winipcfg.IfTypeSoftwareLoopback || iface.Alias() == tunName("") {
			continue
		}
		ipif, err := row.InterfaceLUID.IPInterface(windows.AF_INET)
		if err != nil {
			continue
		}
		metric := row.Metric + ipif.Metric
		if metric < bestMetric {
			bestMetric = metric
			best = uplink{
				Name:    iface.Alias(),
				Index:   int(row.InterfaceIndex),
				Gateway: row.NextHop.Addr(),
				LUID:    uint64(row.InterfaceLUID),
			}
		}
	}
	if best.Name == "" {
		return uplink{}, errors.New("no default route")
	}
	best.Addr = interfaceIPv4(winipcfg.LUID(best.LUID))
	return best, nil
}

// interfaceIPv4 returns the interface's IPv4 address, preferring a routable
// one over a link-local one.
func interfaceIPv4(luid winipcfg.LUID) netip.Addr {
	rows, err := winipcfg.GetUnicastIPAddressTable(windows.AF_INET)
	if err != nil {
		return netip.Addr{}
	}
	var found netip.Addr
	for i := range rows {
		if rows[i].InterfaceLUID != luid {
			continue
		}
		ip := rows[i].Address.Addr()
		if !ip.Is4() {
			continue
		}
		if !ip.IsLinkLocalUnicast() {
			return ip
		}
		if !found.IsValid() {
			found = ip
		}
	}
	return found
}

// tunLUID finds the Wintun adapter Xray created. Xray derives the adapter
// GUID from the MD5 of its name, so the same derivation finds it.
func tunLUID(name string) (winipcfg.LUID, error) {
	id := md5.Sum([]byte(name))
	guid := (*windows.GUID)(unsafe.Pointer(&id[0]))
	var lastErr error
	for i := 0; i < 50; i++ {
		luid, err := winipcfg.LUIDFromGUID(guid)
		if err == nil {
			return luid, nil
		}
		lastErr = err
		time.Sleep(100 * time.Millisecond)
	}
	return 0, fmt.Errorf("tunnel adapter not found: %w", lastErr)
}

// adapterLUID finds the adapter Xray is running on and waits until Windows
// has brought up its IPv4 side: the adapter appears before that, and
// addresses and routes written too early are refused.
func adapterLUID(name string) (winipcfg.LUID, error) {
	var luid winipcfg.LUID
	if v, err := tek.Default.TunLUID(); err == nil {
		luid = winipcfg.LUID(v)
	} else {
		tek.Logs.Printf("warning", "adapter from Xray: %v; looking it up by name", err)
		if luid, err = tunLUID(name); err != nil {
			return 0, err
		}
	}
	var lastErr error
	for i := 0; i < 50; i++ {
		if _, err := luid.IPInterface(windows.AF_INET); err == nil {
			return luid, nil
		} else {
			lastErr = err
		}
		time.Sleep(100 * time.Millisecond)
	}
	return 0, fmt.Errorf("tunnel adapter has no IPv4 interface: %w", lastErr)
}

// retryNotFound repeats a network change that Windows refuses with "Element
// not found" while the adapter is still settling.
func retryNotFound(f func() error) error {
	var err error
	for i := 0; i < 20; i++ {
		if err = f(); !errors.Is(err, windows.ERROR_NOT_FOUND) {
			return err
		}
		time.Sleep(150 * time.Millisecond)
	}
	return err
}

func setupTun(name string, up uplink, servers []netip.Addr, opts tunOptions) (*tunState, error) {
	st := &tunState{Name: name, UplinkLUID: up.LUID, Gateway: up.Gateway.String()}
	upLUID := winipcfg.LUID(up.LUID)

	// Keep the servers themselves on the real connection.
	if up.Gateway.Is4() {
		for _, ip := range servers {
			if !ip.Is4() {
				continue
			}
			prefix := netip.PrefixFrom(ip, 32)
			err := upLUID.AddRoute(prefix, up.Gateway, 0)
			if err == nil {
				st.HostRoutes = append(st.HostRoutes, prefix.String())
			} else if !errors.Is(err, windows.ERROR_OBJECT_ALREADY_EXISTS) {
				tek.Logs.Printf("warning", "route to %s: %v", ip, err)
			}
		}
	}

	luid, err := adapterLUID(name)
	if err != nil {
		return st, err
	}
	address, err := netip.ParsePrefix(opts.Address)
	if err != nil {
		return st, err
	}
	dns, err := netip.ParseAddr(opts.DNS)
	if err != nil {
		return st, err
	}

	if err := retryNotFound(func() error {
		return luid.SetIPAddressesForFamily(windows.AF_INET, []netip.Prefix{address})
	}); err != nil {
		return st, fmt.Errorf("set address: %w", err)
	}
	routes4 := []*winipcfg.RouteData{
		{Destination: netip.MustParsePrefix("0.0.0.0/1"), NextHop: netip.IPv4Unspecified()},
		{Destination: netip.MustParsePrefix("128.0.0.0/1"), NextHop: netip.IPv4Unspecified()},
	}
	if err := retryNotFound(func() error { return luid.SetRoutesForFamily(windows.AF_INET, routes4) }); err != nil {
		return st, fmt.Errorf("set routes: %w", err)
	}
	if err := retryNotFound(func() error { return luid.SetDNS(windows.AF_INET, []netip.Addr{dns}, nil) }); err != nil {
		return st, fmt.Errorf("set dns: %w", err)
	}
	if err := tuneInterface(luid, windows.AF_INET, opts.MTU); err != nil {
		return st, err
	}

	if opts.IPv6 {
		// IPv6 is captured so it cannot leak past the tunnel; the routing
		// rules then refuse it quickly and apps fall back to IPv4.
		addr6 := netip.MustParsePrefix("fdfe:dcba:9876::1/126")
		if err := luid.SetIPAddressesForFamily(windows.AF_INET6, []netip.Prefix{addr6}); err == nil {
			routes6 := []*winipcfg.RouteData{
				{Destination: netip.MustParsePrefix("::/1"), NextHop: netip.IPv6Unspecified()},
				{Destination: netip.MustParsePrefix("8000::/1"), NextHop: netip.IPv6Unspecified()},
			}
			if err := luid.SetRoutesForFamily(windows.AF_INET6, routes6); err != nil {
				tek.Logs.Printf("warning", "ipv6 routes: %v", err)
			}
			_ = tuneInterface(luid, windows.AF_INET6, opts.MTU)
		} else {
			tek.Logs.Printf("warning", "ipv6 address: %v", err)
		}
	}
	tek.Logs.Printf("info", "tunnel %s is up, %d server route(s)", name, len(st.HostRoutes))
	return st, nil
}

func tuneInterface(luid winipcfg.LUID, family winipcfg.AddressFamily, mtu int) error {
	ipif, err := luid.IPInterface(family)
	if err != nil {
		return err
	}
	ipif.RouterDiscoveryBehavior = winipcfg.RouterDiscoveryDisabled
	ipif.DadTransmits = 0
	ipif.ManagedAddressConfigurationSupported = false
	ipif.OtherStatefulConfigurationSupported = false
	ipif.UseAutomaticMetric = false
	ipif.Metric = 0
	if mtu > 0 {
		ipif.NLMTU = uint32(mtu)
	}
	return ipif.Set()
}

func teardownTun(st *tunState) {
	upLUID := winipcfg.LUID(st.UplinkLUID)
	gateway, err := netip.ParseAddr(st.Gateway)
	if err == nil {
		for _, r := range st.HostRoutes {
			if prefix, err := netip.ParsePrefix(r); err == nil {
				_ = upLUID.DeleteRoute(prefix, gateway)
			}
		}
	}
	// Xray removes the adapter it created, and its routes go with it. An
	// adapter that survived a crash is reused next time, so clear it.
	id := md5.Sum([]byte(st.Name))
	guid := (*windows.GUID)(unsafe.Pointer(&id[0]))
	if luid, err := winipcfg.LUIDFromGUID(guid); err == nil {
		_ = luid.FlushRoutes(windows.AF_INET)
		_ = luid.FlushRoutes(windows.AF_INET6)
		_ = luid.FlushDNS(windows.AF_INET)
	}
}

func watchParent(pid int, onExit func()) {
	h, err := windows.OpenProcess(windows.SYNCHRONIZE, false, uint32(pid))
	if err != nil {
		onExit()
		return
	}
	defer windows.CloseHandle(h)
	_, _ = windows.WaitForSingleObject(h, windows.INFINITE)
	onExit()
}
