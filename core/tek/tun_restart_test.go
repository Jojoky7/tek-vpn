package tek

import (
	"os"
	"reflect"
	"runtime"
	"testing"

	xtun "github.com/xtls/xray-core/proxy/tun"
)

// Xray never closes its tun inbound, so a second start in the same process
// used to fail: "device or resource busy" on Linux, ERROR_ALREADY_INITIALIZED
// on Windows. The engine closes the tunnel itself.
func TestTunCanStartAgain(t *testing.T) {
	if runtime.GOOS != "linux" || os.Geteuid() != 0 {
		t.Skip("needs root on Linux to create a tun device")
	}
	if _, err := os.Stat("/dev/net/tun"); err != nil {
		t.Skip("no /dev/net/tun")
	}
	cfg := []byte(`{
		"inbounds": [{"tag": "tun-in", "protocol": "tun", "settings": {"name": "tektest0", "MTU": 1500}}],
		"outbounds": [{"tag": "direct", "protocol": "freedom"}]
	}`)
	e := &Engine{}
	for i := 0; i < 3; i++ {
		if err := e.Start(cfg); err != nil {
			t.Fatalf("start %d: %v", i+1, err)
		}
		if err := e.Stop(); err != nil {
			t.Fatalf("stop %d: %v", i+1, err)
		}
	}
}

// The fields closeTun reads must still exist after an Xray update.
func TestTunPrivateFields(t *testing.T) {
	h := reflect.TypeOf(xtun.Handler{})
	if _, ok := h.FieldByName("stack"); !ok {
		t.Fatal("tun.Handler has no stack field")
	}
}
