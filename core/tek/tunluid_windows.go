package tek

import (
	"errors"
	"reflect"

	"golang.zx2c4.com/wintun"
)

// TunLUID returns the LUID of the Wintun adapter the running instance
// opened. Windows may keep an older adapter with the same GUID from an
// earlier run that is no longer present; addresses can still be written to
// that one, but routes fail with "Element not found". The handle Xray holds
// names the adapter that is actually up.
func (e *Engine) TunLUID() (uint64, error) {
	e.mu.Lock()
	defer e.mu.Unlock()
	if e.inst == nil {
		return 0, errors.New("not running")
	}
	for _, h := range tunInbounds(e.inst) {
		stack := private(reflect.ValueOf(h), "stack")
		if stack == nil {
			continue
		}
		device := private(reflect.ValueOf(stack), "tun")
		if device == nil {
			continue
		}
		if a, ok := private(reflect.ValueOf(device), "adapter").(*wintun.Adapter); ok && a != nil {
			return a.LUID(), nil
		}
	}
	return 0, errors.New("no Wintun adapter in the running instance")
}
