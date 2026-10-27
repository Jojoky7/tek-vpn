//go:build windows

package main

import (
	"fmt"
	"runtime"
	"strings"
	"unsafe"

	"golang.org/x/sys/windows"
)

// proxyState holds the user's WinINET proxy settings from before connecting.
type proxyState struct {
	Flags         uint32 `json:"flags"`
	Server        string `json:"server"`
	Bypass        string `json:"bypass"`
	AutoConfigURL string `json:"autoConfigUrl"`
}

const (
	internetOptionRefresh             = 37
	internetOptionSettingsChanged     = 39
	internetOptionPerConnectionOption = 75

	perConnFlags         = 1
	perConnProxyServer   = 2
	perConnProxyBypass   = 3
	perConnAutoConfigURL = 4

	proxyTypeDirect = 0x1
	proxyTypeProxy  = 0x2
	proxyTypeAuto   = 0x4
)

var (
	wininet               = windows.NewLazySystemDLL("wininet.dll")
	procInternetSetOption = wininet.NewProc("InternetSetOptionW")
	procInternetQueryOpt  = wininet.NewProc("InternetQueryOptionW")
	kernel32              = windows.NewLazySystemDLL("kernel32.dll")
	procGlobalFree        = kernel32.NewProc("GlobalFree")
)

// perConnOption mirrors INTERNET_PER_CONN_OPTIONW: a DWORD option followed
// by a union of DWORD, LPWSTR and FILETIME.
type perConnOption struct {
	option uint32
	value  uint64
}

type perConnOptionList struct {
	size        uint32
	connection  *uint16
	optionCount uint32
	optionError uint32
	options     *perConnOption
}

func (o *perConnOption) setDword(v uint32) { o.value = uint64(v) }

// setString stores a pointer to buf, which the caller keeps alive until the
// system call returns.
func (o *perConnOption) setString(buf []uint16) {
	o.value = uint64(uintptr(unsafe.Pointer(&buf[0])))
}

func (o *perConnOption) dword() uint32 { return uint32(o.value) }

func (o *perConnOption) takeString() string {
	p := uintptr(o.value)
	if p == 0 {
		return ""
	}
	// The string was allocated by WinINet, not by Go: read the field as the
	// pointer it holds.
	s := windows.UTF16PtrToString(*(**uint16)(unsafe.Pointer(&o.value)))
	_, _, _ = procGlobalFree.Call(p)
	return s
}

func queryProxy() (*proxyState, error) {
	opts := []perConnOption{{option: perConnFlags}, {option: perConnProxyServer}, {option: perConnProxyBypass}, {option: perConnAutoConfigURL}}
	list := perConnOptionList{optionCount: uint32(len(opts)), options: &opts[0]}
	list.size = uint32(unsafe.Sizeof(list))
	size := list.size
	r, _, err := procInternetQueryOpt.Call(0, internetOptionPerConnectionOption, uintptr(unsafe.Pointer(&list)), uintptr(unsafe.Pointer(&size)))
	if r == 0 {
		return nil, fmt.Errorf("InternetQueryOption: %v", err)
	}
	return &proxyState{
		Flags:         opts[0].dword(),
		Server:        opts[1].takeString(),
		Bypass:        opts[2].takeString(),
		AutoConfigURL: opts[3].takeString(),
	}, nil
}

func applyProxy(st *proxyState) error {
	opts := []perConnOption{{option: perConnFlags}, {option: perConnProxyServer}, {option: perConnProxyBypass}, {option: perConnAutoConfigURL}}
	server, _ := windows.UTF16FromString(st.Server)
	bypass, _ := windows.UTF16FromString(st.Bypass)
	autoURL, _ := windows.UTF16FromString(st.AutoConfigURL)
	opts[0].setDword(st.Flags)
	opts[1].setString(server)
	opts[2].setString(bypass)
	opts[3].setString(autoURL)
	list := perConnOptionList{optionCount: uint32(len(opts)), options: &opts[0]}
	list.size = uint32(unsafe.Sizeof(list))
	r, _, err := procInternetSetOption.Call(0, internetOptionPerConnectionOption, uintptr(unsafe.Pointer(&list)), uintptr(list.size))
	runtime.KeepAlive(server)
	runtime.KeepAlive(bypass)
	runtime.KeepAlive(autoURL)
	runtime.KeepAlive(opts)
	if r == 0 {
		return fmt.Errorf("InternetSetOption: %v", err)
	}
	_, _, _ = procInternetSetOption.Call(0, internetOptionSettingsChanged, 0, 0)
	_, _, _ = procInternetSetOption.Call(0, internetOptionRefresh, 0, 0)
	return nil
}

func setSystemProxy(p proxySettings) (*proxyState, error) {
	saved, err := queryProxy()
	if err != nil {
		return nil, err
	}
	bypass := append([]string{}, p.Bypass...)
	bypass = append(bypass, "<local>")
	err = applyProxy(&proxyState{
		Flags:  proxyTypeDirect | proxyTypeProxy,
		Server: fmt.Sprintf("127.0.0.1:%d", p.HTTPPort),
		Bypass: strings.Join(bypass, ";"),
	})
	if err != nil {
		return nil, err
	}
	return saved, nil
}

func restoreSystemProxy(st *proxyState) {
	_ = applyProxy(st)
}
