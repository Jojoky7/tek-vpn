// Package darwinproc finds the process that owns a local TCP or UDP socket
// on macOS, for Xray's "process" routing rules (apps that go around the VPN
// or through it). Xray 26.3.27 does this only on Windows and Linux; the
// macOS build of tek-core adds it with a build overlay, see core/_xray.
package darwinproc

import (
	"encoding/binary"
	"net/netip"
)

// The sysctls net.inet.tcp.pcblist_n and net.inet.udp.pcblist_n return a
// struct xinpgen, then one record per socket, then a closing xinpgen
// (xnu, bsd/netinet/in_pcblist.c, get_pcblist_n). A record is made of
// struct xinpcb_n, xsocket_n, two xsockbuf_n, xsockstat_n and, for TCP,
// xtcpcb_n, each padded to 8 bytes; every part starts with its own length.
// The structs are packed to 4 bytes, which gives these offsets.
const (
	headerLen = 24 // sizeof(struct xinpgen)

	inpLocalPort = 18 // xinpcb_n.inp_lport, network byte order
	inpVFlag     = 44 // xinpcb_n.inp_vflag
	inpLocal6    = 64 // xinpcb_n.inp_dependladdr.inp6_local
	inpLocal4    = 76 // xinpcb_n.inp_dependladdr.inp46_local.ia46_addr4
	soLastPID    = 68 // xsocket_n.so_last_pid

	vflagIPv4 = 0x1
	vflagIPv6 = 0x2
)

func roundUp8(n int) int { return (n + 7) &^ 7 }

func u32(b []byte, off int) int { return int(binary.LittleEndian.Uint32(b[off : off+4])) }

// layout is the size of one record and the place of its parts.
type layout struct {
	item   int // bytes per record
	inpLen int // xinpcb_n.xi_len
	soOff  int // where xsocket_n starts in the record
	soLen  int // xsocket_n.xso_len
}

// readLayout takes the sizes from the first record, so a new macOS whose
// structs grew is still read right. When that record cannot be read, the
// sizes of the known macOS versions are used: 384 bytes before macOS 13
// (Darwin 22), 408 since, plus 208 for TCP.
func readLayout(buf []byte, tcp bool, darwinMajor int) layout {
	parts := 5
	if tcp {
		parts = 6
	}
	l := layout{}
	off := headerLen
	ok := true
	for k := 0; k < parts; k++ {
		if off+8 > len(buf) {
			ok = false
			break
		}
		n := u32(buf, off)
		if n < 8 || n > 4096 || off+n > len(buf) {
			ok = false
			break
		}
		switch k {
		case 0:
			l.inpLen = n
			l.soOff = roundUp8(n)
		case 1:
			l.soLen = n
		}
		off += roundUp8(n)
	}
	if ok && l.inpLen >= inpLocal4+4 && l.soLen >= soLastPID+4 {
		l.item = off - headerLen
		return l
	}
	item := 384
	if darwinMajor >= 22 {
		item = 408
	}
	if tcp {
		item += 208
	}
	return layout{item: item, soOff: 104}
}

// Search returns the pid of the socket bound to ip:port in a pcblist_n
// buffer. For UDP a socket bound to any address on that port counts too,
// because an unconnected UDP socket has no local address of its own.
func Search(buf []byte, tcp bool, ip netip.Addr, port uint16, darwinMajor int) (uint32, bool) {
	if len(buf) < headerLen {
		return 0, false
	}
	ip = ip.Unmap()
	want4 := ip.Is4()
	l := readLayout(buf, tcp, darwinMajor)
	var fallback uint32
	found := false
	for off := headerLen; off+l.item <= len(buf); off += l.item {
		rec := buf[off : off+l.item]
		// A part that the kernel left empty, or a record that does not
		// start where it should, is skipped rather than misread.
		if l.inpLen > 0 && (u32(rec, 0) != l.inpLen || u32(rec, l.soOff) != l.soLen) {
			continue
		}
		if binary.BigEndian.Uint16(rec[inpLocalPort:inpLocalPort+2]) != port {
			continue
		}
		flag := rec[inpVFlag]
		var local netip.Addr
		switch {
		case want4 && flag&vflagIPv4 != 0:
			local = netip.AddrFrom4([4]byte(rec[inpLocal4 : inpLocal4+4]))
		case !want4 && flag&vflagIPv6 != 0:
			local = netip.AddrFrom16([16]byte(rec[inpLocal6 : inpLocal6+16]))
		default:
			continue
		}
		pid := binary.LittleEndian.Uint32(rec[l.soOff+soLastPID : l.soOff+soLastPID+4])
		if local == ip {
			return pid, true
		}
		if !tcp && local.IsUnspecified() && !found {
			fallback, found = pid, true
		}
	}
	return fallback, found
}
