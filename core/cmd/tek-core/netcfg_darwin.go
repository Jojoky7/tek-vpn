//go:build darwin

package main

import (
	"bufio"
	"bytes"
	"errors"
	"fmt"
	"net"
	"net/netip"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/jojoky7/tek-vpn/core/tek"
)

// tunState is what setupTun changed, kept so it can be undone after a crash.
type tunState struct {
	Name       string   `json:"name"`
	Gateway    string   `json:"gateway"`
	HostRoutes []string `json:"hostRoutes"`
	NetRoutes  []string `json:"netRoutes"`
	// DNSService is the network service whose DNS servers were replaced;
	// SavedDNS are its previous servers ("Empty" means automatic).
	DNSService string   `json:"dnsService,omitempty"`
	SavedDNS   []string `json:"savedDns,omitempty"`
}

func isElevated() bool {
	return os.Geteuid() == 0
}

// tunName picks a free utunN; macOS requires the "utun" prefix.
func tunName(requested string) string {
	if strings.HasPrefix(requested, "utun") {
		if _, err := net.InterfaceByName(requested); err != nil {
			return requested
		}
	}
	for n := 10; n < 256; n++ {
		name := "utun" + strconv.Itoa(n)
		if _, err := net.InterfaceByName(name); err != nil {
			return name
		}
	}
	return "utun99"
}

func run(name string, args ...string) (string, error) {
	cmd := exec.Command(name, args...)
	var out bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &out
	err := cmd.Run()
	text := strings.TrimSpace(out.String())
	// networksetup reports some failures, such as missing rights, with
	// exit status 0 and an "** Error:" line.
	if err == nil && strings.Contains(text, "** Error") {
		err = errors.New("failed")
	}
	if err != nil {
		if text != "" {
			return text, fmt.Errorf("%s %s: %s", name, strings.Join(args, " "), text)
		}
		return text, fmt.Errorf("%s %s: %w", name, strings.Join(args, " "), err)
	}
	return text, nil
}

func detectUplink() (uplink, error) {
	out, err := run("/sbin/route", "-n", "get", "default")
	if err != nil {
		return uplink{}, err
	}
	var up uplink
	sc := bufio.NewScanner(strings.NewReader(out))
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if v, ok := strings.CutPrefix(line, "interface:"); ok {
			up.Name = strings.TrimSpace(v)
		}
		if v, ok := strings.CutPrefix(line, "gateway:"); ok {
			if ip, err := netip.ParseAddr(strings.TrimSpace(v)); err == nil {
				up.Gateway = ip
			}
		}
	}
	if up.Name == "" || strings.HasPrefix(up.Name, "utun") {
		return uplink{}, errors.New("no default route on a real interface")
	}
	if iface, err := net.InterfaceByName(up.Name); err == nil {
		up.Index = iface.Index
	}
	return up, nil
}

// serviceForInterface maps a device such as en0 to its network service
// name such as "Wi-Fi", as networksetup expects.
func serviceForInterface(device string) string {
	out, err := run("/usr/sbin/networksetup", "-listnetworkserviceorder")
	if err != nil {
		return ""
	}
	var current string
	for _, line := range strings.Split(out, "\n") {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, "(") && !strings.HasPrefix(line, "(Hardware Port") {
			if i := strings.Index(line, ") "); i > 0 {
				current = strings.TrimPrefix(strings.TrimSpace(line[i+2:]), "*")
			}
			continue
		}
		if strings.Contains(line, "Device: "+device+")") {
			return current
		}
	}
	return ""
}

func getDNS(service string) []string {
	out, err := run("/usr/sbin/networksetup", "-getdnsservers", service)
	if err != nil || strings.Contains(out, "aren't any") {
		return []string{"Empty"}
	}
	var servers []string
	for _, l := range strings.Split(out, "\n") {
		if ip, err := netip.ParseAddr(strings.TrimSpace(l)); err == nil {
			servers = append(servers, ip.String())
		}
	}
	if len(servers) == 0 {
		return []string{"Empty"}
	}
	return servers
}

func setupTun(name string, up uplink, servers []netip.Addr, opts tunOptions) (*tunState, error) {
	st := &tunState{Name: name, Gateway: up.Gateway.String()}

	// Wait for Xray to bring the utun interface up.
	deadline := time.Now().Add(5 * time.Second)
	for {
		if _, err := net.InterfaceByName(name); err == nil {
			break
		}
		if time.Now().After(deadline) {
			return st, fmt.Errorf("interface %s did not appear", name)
		}
		time.Sleep(100 * time.Millisecond)
	}

	if up.Gateway.Is4() {
		for _, ip := range servers {
			if !ip.Is4() {
				continue
			}
			if _, err := run("/sbin/route", "-q", "-n", "add", "-host", ip.String(), up.Gateway.String()); err == nil {
				st.HostRoutes = append(st.HostRoutes, ip.String())
			} else {
				tek.Logs.Printf("warning", "%v", err)
			}
		}
	}

	nets := []string{"0.0.0.0/1", "128.0.0.0/1"}
	for _, n := range nets {
		if _, err := run("/sbin/route", "-q", "-n", "add", "-net", n, "-interface", name); err != nil {
			return st, err
		}
		st.NetRoutes = append(st.NetRoutes, n)
	}
	if opts.IPv6 {
		for _, n := range []string{"::/1", "8000::/1"} {
			if _, err := run("/sbin/route", "-q", "-n", "add", "-inet6", "-net", n, "-interface", name); err == nil {
				st.NetRoutes = append(st.NetRoutes, n)
			} else {
				tek.Logs.Printf("warning", "%v", err)
			}
		}
	}

	// Point the system resolver into the tunnel, where Xray answers it.
	if service := serviceForInterface(up.Name); service != "" && opts.DNS != "" {
		st.DNSService = service
		st.SavedDNS = getDNS(service)
		if _, err := run("/usr/sbin/networksetup", "-setdnsservers", service, opts.DNS); err != nil {
			tek.Logs.Printf("warning", "%v", err)
			st.DNSService, st.SavedDNS = "", nil
		}
		flushDNSCache()
	}
	tek.Logs.Printf("info", "tunnel %s is up, %d server route(s)", name, len(st.HostRoutes))
	return st, nil
}

func flushDNSCache() {
	_, _ = run("/usr/bin/dscacheutil", "-flushcache")
	_, _ = run("/usr/bin/killall", "-HUP", "mDNSResponder")
}

func teardownTun(st *tunState) {
	if st.DNSService != "" && len(st.SavedDNS) > 0 {
		args := append([]string{"-setdnsservers", st.DNSService}, st.SavedDNS...)
		_, _ = run("/usr/sbin/networksetup", args...)
		flushDNSCache()
	}
	for _, ip := range st.HostRoutes {
		_, _ = run("/sbin/route", "-q", "-n", "delete", "-host", ip, st.Gateway)
	}
	if _, err := net.InterfaceByName(st.Name); err == nil {
		for _, n := range st.NetRoutes {
			if strings.Contains(n, ":") {
				_, _ = run("/sbin/route", "-q", "-n", "delete", "-inet6", "-net", n, "-interface", st.Name)
			} else {
				_, _ = run("/sbin/route", "-q", "-n", "delete", "-net", n, "-interface", st.Name)
			}
		}
	}
}

func watchParent(pid int, onExit func()) {
	for {
		if err := syscall.Kill(pid, 0); err != nil && !errors.Is(err, syscall.EPERM) {
			onExit()
			return
		}
		time.Sleep(2 * time.Second)
	}
}
