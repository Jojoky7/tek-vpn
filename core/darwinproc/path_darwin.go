//go:build darwin

package darwinproc

import (
	"strconv"
	"strings"
	"syscall"
	"unsafe"
)

// ExecPath is the full path of the program that runs as pid (libproc's
// proc_pidpath).
func ExecPath(pid uint32) (string, error) {
	const (
		callPidInfo   = 2    // PROC_INFO_CALL_PIDINFO
		pidPathInfo   = 11   // PROC_PIDPATHINFO
		pathInfoBytes = 4096 // PROC_PIDPATHINFO_MAXSIZE
	)
	buf := make([]byte, pathInfoBytes)
	_, _, errno := syscall.Syscall6(syscall.SYS_PROC_INFO, callPidInfo, uintptr(pid),
		pidPathInfo, 0, uintptr(unsafe.Pointer(&buf[0])), pathInfoBytes)
	if errno != 0 {
		return "", errno
	}
	if i := strings.IndexByte(string(buf), 0); i >= 0 {
		buf = buf[:i]
	}
	return string(buf), nil
}

// DarwinMajor is the major version of the kernel (22 for macOS 13).
func DarwinMajor() int {
	release, _ := syscall.Sysctl("kern.osrelease")
	major, _, _ := strings.Cut(release, ".")
	n, _ := strconv.Atoi(major)
	return n
}
