//go:build !android

package tek

import (
	"context"
	"reflect"
	"unsafe"

	"github.com/xtls/xray-core/core"
	"github.com/xtls/xray-core/features/inbound"
	"github.com/xtls/xray-core/proxy"
	xtun "github.com/xtls/xray-core/proxy/tun"
)

// Xray 26.3.27 opens the tun device when the instance is built and never
// closes it: the tun inbound has no Close. The device then stays open in
// the process, and the next start fails to open it again ("device or
// resource busy" on Linux, ERROR_ALREADY_INITIALIZED from Wintun on
// Windows). The engine closes it itself, through fields Xray keeps private.

type closer interface{ Close() error }

// tunInbounds lists the tun inbounds of an instance. Call it before the
// instance is closed: closing forgets the handlers.
func tunInbounds(inst *core.Instance) []*xtun.Handler {
	m, ok := inst.GetFeature(inbound.ManagerType()).(inbound.Manager)
	if !ok || m == nil {
		return nil
	}
	var out []*xtun.Handler
	for _, h := range m.ListHandlers(context.Background()) {
		g, ok := h.(interface{ GetInbound() proxy.Inbound })
		if !ok {
			continue
		}
		if t, ok := g.GetInbound().(*xtun.Handler); ok && t != nil {
			out = append(out, t)
		}
	}
	return out
}

// closeTun stops the inbound's network stack and closes its device.
func closeTun(h *xtun.Handler) {
	stack, _ := private(reflect.ValueOf(h), "stack").(closer)
	if stack == nil {
		return
	}
	device, _ := private(reflect.ValueOf(stack), "tun").(closer)
	_ = stack.Close()
	if device != nil {
		wakeReader(device)
		_ = device.Close()
	}
}

// private reads an unexported field of the struct a pointer points to.
func private(ptr reflect.Value, name string) any {
	if ptr.Kind() != reflect.Pointer || ptr.IsNil() || ptr.Elem().Kind() != reflect.Struct {
		return nil
	}
	f := ptr.Elem().FieldByName(name)
	if !f.IsValid() {
		return nil
	}
	return reflect.NewAt(f.Type(), unsafe.Pointer(f.UnsafeAddr())).Elem().Interface()
}
