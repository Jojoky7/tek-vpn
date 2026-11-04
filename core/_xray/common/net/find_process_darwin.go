//go:build darwin

// Tek: added to Xray's common/net in the macOS build of tek-core
// (go build -overlay), so that "process" routing rules work on macOS too.

package net

import (
	"net/netip"
	"path/filepath"
	"sync"
	"syscall"

	"github.com/jojoky7/tek-vpn/core/darwinproc"
	"github.com/xtls/xray-core/common/errors"
)

var darwinMajor = sync.OnceValue(darwinproc.DarwinMajor)

func FindProcess(dest Destination) (PID int, Name string, AbsolutePath string, err error) {
	if dest.Address.Family() == AddressFamilyDomain {
		return 0, "", "", errors.New("process lookup needs an IP address")
	}
	isLocal, err := IsLocal(dest.Address.IP())
	if err != nil {
		return 0, "", "", errors.New("failed to determine if address is local: ", err)
	}
	if !isLocal {
		return 0, "", "", ErrNotLocal
	}
	var sysctl string
	switch dest.Network {
	case Network_TCP:
		sysctl = "net.inet.tcp.pcblist_n"
	case Network_UDP:
		sysctl = "net.inet.udp.pcblist_n"
	default:
		return 0, "", "", errors.New("process lookup works only for TCP and UDP")
	}
	addr, ok := netip.AddrFromSlice(dest.Address.IP())
	if !ok {
		return 0, "", "", errors.New("invalid IP address")
	}
	list, err := syscall.Sysctl(sysctl)
	if err != nil {
		return 0, "", "", errors.New("cannot read ", sysctl).Base(err)
	}
	pid, ok := darwinproc.Search([]byte(list), dest.Network == Network_TCP, addr, uint16(dest.Port), darwinMajor())
	if !ok {
		return 0, "", "", errors.New("no process has this socket")
	}
	path, err := darwinproc.ExecPath(pid)
	if err != nil {
		return int(pid), "", "", errors.New("cannot get the path of process ", pid).Base(err)
	}
	return int(pid), filepath.Base(path), path, nil
}
