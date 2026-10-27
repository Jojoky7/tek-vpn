//go:build darwin

package main

import (
	"errors"
	"strconv"
	"strings"
)

// proxyState holds every network service's proxy settings from before connecting.
type proxyState struct {
	Services []serviceProxy `json:"services"`
}

type serviceProxy struct {
	Name   string    `json:"name"`
	Web    proxyKind `json:"web"`
	Secure proxyKind `json:"secure"`
	Socks  proxyKind `json:"socks"`
	Bypass []string  `json:"bypass"`
}

type proxyKind struct {
	Enabled bool   `json:"enabled"`
	Server  string `json:"server"`
	Port    string `json:"port"`
}

func networkServices() ([]string, error) {
	out, err := run("/usr/sbin/networksetup", "-listallnetworkservices")
	if err != nil {
		return nil, err
	}
	var services []string
	for i, line := range strings.Split(out, "\n") {
		line = strings.TrimSpace(line)
		// The first line explains that "*" marks disabled services.
		if i == 0 || line == "" || strings.HasPrefix(line, "*") {
			continue
		}
		services = append(services, line)
	}
	return services, nil
}

func readKind(flag, service string) proxyKind {
	out, err := run("/usr/sbin/networksetup", flag, service)
	if err != nil {
		return proxyKind{}
	}
	var k proxyKind
	for _, line := range strings.Split(out, "\n") {
		key, value, ok := strings.Cut(line, ":")
		if !ok {
			continue
		}
		value = strings.TrimSpace(value)
		switch strings.TrimSpace(key) {
		case "Enabled":
			k.Enabled = value == "Yes"
		case "Server":
			k.Server = value
		case "Port":
			k.Port = value
		}
	}
	return k
}

func readBypass(service string) []string {
	out, err := run("/usr/sbin/networksetup", "-getproxybypassdomains", service)
	if err != nil || strings.Contains(out, "aren't any") {
		return []string{"Empty"}
	}
	var list []string
	for _, l := range strings.Split(out, "\n") {
		if l = strings.TrimSpace(l); l != "" {
			list = append(list, l)
		}
	}
	return list
}

func setSystemProxy(p proxySettings) (*proxyState, error) {
	services, err := networkServices()
	if err != nil {
		return nil, err
	}
	if len(services) == 0 {
		return nil, errors.New("no network services")
	}
	saved := &proxyState{}
	for _, s := range services {
		saved.Services = append(saved.Services, serviceProxy{
			Name:   s,
			Web:    readKind("-getwebproxy", s),
			Secure: readKind("-getsecurewebproxy", s),
			Socks:  readKind("-getsocksfirewallproxy", s),
			Bypass: readBypass(s),
		})
	}
	httpPort := strconv.Itoa(p.HTTPPort)
	bypass := append([]string{"localhost", "127.0.0.1", "*.local", "169.254/16"}, p.Bypass...)
	var firstErr error
	for _, s := range services {
		steps := [][]string{
			{"-setwebproxy", s, "127.0.0.1", httpPort},
			{"-setsecurewebproxy", s, "127.0.0.1", httpPort},
		}
		if p.SocksPort > 0 {
			steps = append(steps, []string{"-setsocksfirewallproxy", s, "127.0.0.1", strconv.Itoa(p.SocksPort)})
		}
		steps = append(steps, append([]string{"-setproxybypassdomains", s}, bypass...))
		for _, args := range steps {
			if _, err := run("/usr/sbin/networksetup", args...); err != nil && firstErr == nil {
				firstErr = err
			}
		}
	}
	if firstErr != nil {
		restoreSystemProxy(saved)
		// A standard (non-administrator) account may not change network
		// settings: the app then starts the core with administrator rights.
		if strings.Contains(firstErr.Error(), "admin") && !isElevated() {
			return nil, errNeedsAdmin
		}
		return nil, firstErr
	}
	return saved, nil
}

func restoreKind(setFlag, stateFlag, service string, k proxyKind) {
	if k.Server != "" && k.Port != "" && k.Port != "0" {
		_, _ = run("/usr/sbin/networksetup", setFlag, service, k.Server, k.Port)
	}
	state := "off"
	if k.Enabled {
		state = "on"
	}
	_, _ = run("/usr/sbin/networksetup", stateFlag, service, state)
}

func restoreSystemProxy(st *proxyState) {
	for _, s := range st.Services {
		restoreKind("-setwebproxy", "-setwebproxystate", s.Name, s.Web)
		restoreKind("-setsecurewebproxy", "-setsecurewebproxystate", s.Name, s.Secure)
		restoreKind("-setsocksfirewallproxy", "-setsocksfirewallproxystate", s.Name, s.Socks)
		if len(s.Bypass) > 0 {
			_, _ = run("/usr/sbin/networksetup", append([]string{"-setproxybypassdomains", s.Name}, s.Bypass...)...)
		}
	}
}
