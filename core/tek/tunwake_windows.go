package tek

import (
	"reflect"
	"time"

	"golang.org/x/sys/windows"
)

// wakeReader lets Xray's packet loop, which sleeps on Wintun's read event,
// see that the stack has stopped and return before the session is ended:
// a read after the end touches freed memory.
func wakeReader(device closer) {
	h, ok := private(reflect.ValueOf(device), "readWait").(windows.Handle)
	if !ok || h == 0 {
		return
	}
	_ = windows.SetEvent(h)
	time.Sleep(200 * time.Millisecond)
}
