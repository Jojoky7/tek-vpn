package main

import (
	"net"
	"sync/atomic"
	"time"
	_ "unsafe" // for go:linkname

	_ "github.com/xtls/xray-core/common/net"
)

// xrayLocalIPs is Xray's copy of this computer's addresses, which it keeps
// for a minute. Rules by program only look up connections that come from
// one of these addresses, so right after the tunnel gets its address they
// would miss for up to a minute; tek-core drops the copy instead.
//
//go:linkname xrayLocalIPs github.com/xtls/xray-core/common/net.localIPCache
var xrayLocalIPs atomic.Pointer[struct {
	addrs      []net.Addr
	lastUpdate time.Time
}]

func forgetLocalIPs() { xrayLocalIPs.Store(nil) }
