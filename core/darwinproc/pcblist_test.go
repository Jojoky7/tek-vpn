package darwinproc

import (
	"encoding/binary"
	"net/netip"
	"testing"
)

type sock struct {
	ip   netip.Addr
	port uint16
	pid  uint32
	v6   bool
}

// list builds a pcblist_n buffer the way xnu lays it out, with the part
// sizes of a recent macOS.
func list(tcp bool, socks ...sock) []byte {
	parts := []int{104, 124, 24, 24, 128}
	if tcp {
		parts = append(parts, 204)
	}
	buf := make([]byte, headerLen)
	binary.LittleEndian.PutUint32(buf, headerLen)
	for _, s := range socks {
		var rec []byte
		for i, n := range parts {
			p := make([]byte, roundUp8(n))
			binary.LittleEndian.PutUint32(p, uint32(n))
			binary.LittleEndian.PutUint32(p[4:], uint32(1<<i))
			if i == 0 {
				binary.BigEndian.PutUint16(p[inpLocalPort:], s.port)
				if s.v6 {
					p[inpVFlag] = vflagIPv6
					a := s.ip.As16()
					copy(p[inpLocal6:], a[:])
				} else {
					p[inpVFlag] = vflagIPv4
					a := s.ip.As4()
					copy(p[inpLocal4:], a[:])
				}
			}
			if i == 1 {
				binary.LittleEndian.PutUint32(p[soLastPID:], s.pid)
			}
			rec = append(rec, p...)
		}
		buf = append(buf, rec...)
	}
	trailer := make([]byte, headerLen)
	binary.LittleEndian.PutUint32(trailer, headerLen)
	binary.LittleEndian.PutUint32(trailer[4:], uint32(len(socks)))
	return append(buf, trailer...)
}

func TestSearch(t *testing.T) {
	tun := netip.MustParseAddr("172.19.0.1")
	other := netip.MustParseAddr("192.168.1.5")
	any4 := netip.IPv4Unspecified()
	v6 := netip.MustParseAddr("fd00::1")

	tcp := list(true,
		sock{ip: other, port: 50000, pid: 11},
		sock{ip: any4, port: 50001, pid: 12}, // a listening socket
		sock{ip: tun, port: 50001, pid: 13},
		sock{ip: v6, port: 50002, pid: 14, v6: true},
	)
	cases := []struct {
		name string
		buf  []byte
		tcp  bool
		ip   netip.Addr
		port uint16
		pid  uint32
		ok   bool
	}{
		{"tcp", tcp, true, tun, 50001, 13, true},
		{"tcp other address", tcp, true, other, 50000, 11, true},
		{"tcp mapped address", tcp, true, netip.AddrFrom16(tun.As16()), 50001, 13, true},
		{"tcp wrong port", tcp, true, tun, 50003, 0, false},
		{"tcp ignores any address", tcp, true, tun, 50000, 0, false},
		{"tcp ipv6", tcp, true, v6, 50002, 14, true},
		{"udp exact", list(false, sock{ip: any4, port: 6000, pid: 21}, sock{ip: tun, port: 6000, pid: 22}), false, tun, 6000, 22, true},
		{"udp any address", list(false, sock{ip: any4, port: 6000, pid: 21}), false, tun, 6000, 21, true},
		{"empty", list(true), true, tun, 1, 0, false},
		{"short", []byte{1, 2, 3}, true, tun, 1, 0, false},
	}
	for _, c := range cases {
		pid, ok := Search(c.buf, c.tcp, c.ip, c.port, 24)
		if pid != c.pid || ok != c.ok {
			t.Errorf("%s: got %d %v, want %d %v", c.name, pid, ok, c.pid, c.ok)
		}
	}
}

// When the first record cannot be read, the known sizes are used.
func TestSearchFallbackLayout(t *testing.T) {
	tun := netip.MustParseAddr("172.19.0.1")
	buf := list(true, sock{ip: tun, port: 1, pid: 1}, sock{ip: tun, port: 7000, pid: 31})
	// The real layout is 104+128+24+24+128+208 = 616 bytes, the same as
	// the fallback for Darwin 22+; break the first record's lengths.
	binary.LittleEndian.PutUint32(buf[headerLen:], 0)
	if l := readLayout(buf, true, 24); l.item != 616 || l.soOff != 104 {
		t.Fatalf("layout %+v", l)
	}
	if pid, ok := Search(buf, true, tun, 7000, 24); !ok || pid != 31 {
		t.Fatalf("got %d %v", pid, ok)
	}
}
