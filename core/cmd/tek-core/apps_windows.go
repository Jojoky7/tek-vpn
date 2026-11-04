package main

import (
	"os"
	"path/filepath"
	"sort"
	"strings"
	"unsafe"

	"golang.org/x/sys/windows"
)

// appInfo is a running program for the list of apps that go around the VPN
// or through it.
type appInfo struct {
	Name        string `json:"name"` // Telegram.exe
	Path        string `json:"path"`
	Description string `json:"description,omitempty"` // Telegram Desktop
}

// runningApps lists the programs that run now, one entry per program name,
// without Windows' own ones and without Tek.
func runningApps() []appInfo {
	snap, err := windows.CreateToolhelp32Snapshot(windows.TH32CS_SNAPPROCESS, 0)
	if err != nil {
		return nil
	}
	defer windows.CloseHandle(snap)
	winDir := strings.ToLower(os.Getenv("WINDIR"))
	if winDir == "" {
		winDir = `c:\windows`
	}
	self, _ := os.Executable()
	selfDir := strings.ToLower(filepath.Dir(self))
	seen := map[string]bool{}
	var out []appInfo
	var e windows.ProcessEntry32
	e.Size = uint32(unsafe.Sizeof(e))
	for err := windows.Process32First(snap, &e); err == nil; err = windows.Process32Next(snap, &e) {
		path := processPath(e.ProcessID)
		if path == "" {
			continue
		}
		lower := strings.ToLower(path)
		if strings.HasPrefix(lower, winDir+`\`) || strings.HasPrefix(lower, selfDir+`\`) {
			continue
		}
		name := filepath.Base(path)
		if seen[strings.ToLower(name)] {
			continue
		}
		seen[strings.ToLower(name)] = true
		out = append(out, appInfo{Name: name, Path: path, Description: fileDescription(path)})
	}
	sort.Slice(out, func(i, j int) bool { return strings.ToLower(out[i].Name) < strings.ToLower(out[j].Name) })
	return out
}

func processPath(pid uint32) string {
	if pid == 0 {
		return ""
	}
	h, err := windows.OpenProcess(windows.PROCESS_QUERY_LIMITED_INFORMATION, false, pid)
	if err != nil {
		return ""
	}
	defer windows.CloseHandle(h)
	buf := make([]uint16, 4096)
	n := uint32(len(buf))
	if err := windows.QueryFullProcessImageName(h, 0, &buf[0], &n); err != nil {
		return ""
	}
	return windows.UTF16ToString(buf[:n])
}

// fileDescription is the program's own name from its version resource
// ("Google Chrome" for chrome.exe), or "".
func fileDescription(path string) string {
	size, err := windows.GetFileVersionInfoSize(path, nil)
	if err != nil || size == 0 {
		return ""
	}
	info := make([]byte, size)
	if err := windows.GetFileVersionInfo(path, 0, size, unsafe.Pointer(&info[0])); err != nil {
		return ""
	}
	var trans *[2]uint16
	var transLen uint32
	if err := windows.VerQueryValue(unsafe.Pointer(&info[0]), `\VarFileInfo\Translation`,
		unsafe.Pointer(&trans), &transLen); err != nil || transLen < 4 || trans == nil {
		return ""
	}
	key := `\StringFileInfo\` + hex4(trans[0]) + hex4(trans[1]) + `\FileDescription`
	var desc *uint16
	var descLen uint32
	if err := windows.VerQueryValue(unsafe.Pointer(&info[0]), key, unsafe.Pointer(&desc), &descLen); err != nil ||
		desc == nil || descLen == 0 {
		return ""
	}
	return strings.TrimSpace(windows.UTF16PtrToString(desc))
}

func hex4(v uint16) string {
	const digits = "0123456789abcdef"
	return string([]byte{digits[v>>12&15], digits[v>>8&15], digits[v>>4&15], digits[v&15]})
}
