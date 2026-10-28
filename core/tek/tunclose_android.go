package tek

import (
	"github.com/xtls/xray-core/core"
	xtun "github.com/xtls/xray-core/proxy/tun"
)

// On Android the tun file belongs to the VpnService, which closes it.
func tunInbounds(*core.Instance) []*xtun.Handler { return nil }
func closeTun(*xtun.Handler)                     {}
