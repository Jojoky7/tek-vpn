package main

import (
	"testing"

	xnet "github.com/xtls/xray-core/common/net"
)

func TestForgetLocalIPs(t *testing.T) {
	if _, err := xnet.IsLocal(xnet.ParseIP("127.0.0.1")); err != nil {
		t.Fatal(err)
	}
	if xrayLocalIPs.Load() == nil {
		t.Fatal("not bound to Xray's cache")
	}
	forgetLocalIPs()
	if xrayLocalIPs.Load() != nil {
		t.Fatal("the cache is still there")
	}
}
