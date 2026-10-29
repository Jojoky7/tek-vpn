package main

import (
	"crypto/subtle"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/jojoky7/tek-vpn/core/tek"
)

// StartRequest is what the app sends to connect.
type StartRequest struct {
	Config      json.RawMessage `json:"config"`
	Mode        string          `json:"mode"` // "proxy" or "tun"
	SystemProxy *proxySettings  `json:"systemProxy,omitempty"`
	Tun         *tunOptions     `json:"tun,omitempty"`
	AssetDir    string          `json:"assetDir,omitempty"`
}

type proxySettings struct {
	HTTPPort  int      `json:"httpPort"`
	SocksPort int      `json:"socksPort"`
	Bypass    []string `json:"bypass"`
}

type tunOptions struct {
	Name string `json:"name"`
	MTU  int    `json:"mtu"`
	// Address of the tunnel interface, e.g. 172.19.0.1/30.
	Address string `json:"address"`
	// DNS server the system should use; Xray answers it inside the tunnel.
	DNS  string `json:"dns"`
	IPv6 bool   `json:"ipv6"`
}

var errNeedsAdmin = errors.New("needs_admin")

type session struct {
	mu        sync.Mutex
	dataDir   string
	mode      string
	since     time.Time
	lastError string
	tun       *tunState
	proxy     *proxyState
}

func (s *session) leftoversPath() string {
	return filepath.Join(s.dataDir, "leftovers.json")
}

type leftovers struct {
	Tun   *tunState   `json:"tun,omitempty"`
	Proxy *proxyState `json:"proxy,omitempty"`
}

// saveLeftovers records the system changes in effect, so a crash can be
// undone on the next start.
func (s *session) saveLeftovers() {
	if s.dataDir == "" {
		return
	}
	if s.tun == nil && s.proxy == nil {
		_ = os.Remove(s.leftoversPath())
		return
	}
	data, _ := json.Marshal(leftovers{Tun: s.tun, Proxy: s.proxy})
	_ = os.WriteFile(s.leftoversPath(), data, 0o600)
}

func recoverLeftovers(dataDir string) {
	if dataDir == "" {
		return
	}
	path := filepath.Join(dataDir, "leftovers.json")
	data, err := os.ReadFile(path)
	if err != nil {
		return
	}
	var l leftovers
	if json.Unmarshal(data, &l) == nil {
		if l.Proxy != nil {
			restoreSystemProxy(l.Proxy)
			disarmProxyRestore()
			tek.Logs.Printf("info", "restored system proxy left by a previous session")
		}
		if l.Tun != nil {
			teardownTun(l.Tun)
			tek.Logs.Printf("info", "removed routes left by a previous session")
		}
	}
	_ = os.Remove(path)
}

func (s *session) start(req StartRequest) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.stopLocked()

	if req.AssetDir != "" {
		_ = os.Setenv("XRAY_LOCATION_ASSET", req.AssetDir)
	}
	cfg, err := parseConfig(req.Config)
	if err != nil {
		return err
	}
	cfg.sanitize()

	switch req.Mode {
	case "tun":
		if !isElevated() {
			return errNeedsAdmin
		}
		opts := tunOptions{}
		if req.Tun != nil {
			opts = *req.Tun
		}
		if opts.MTU <= 0 {
			opts.MTU = 1500
		}
		if opts.Address == "" {
			opts.Address = "172.19.0.1/30"
		}
		if opts.DNS == "" {
			opts.DNS = "172.19.0.2"
		}
		up, err := detectUplink()
		if err != nil {
			return fmt.Errorf("cannot find the network connection: %w", err)
		}
		tek.Logs.Printf("info", "uplink %s (index %d, gateway %s, address %s)", up.Name, up.Index, up.Gateway, up.Addr)
		servers := resolveHosts(cfg.serverHosts())
		name := tunName(opts.Name)
		if !cfg.setTunName(name) {
			return errors.New("config has no tun inbound")
		}
		cfg.bindOutbounds(up.Name, up.Addr)
		data, err := cfg.bytes()
		if err != nil {
			return err
		}
		if err := tek.Default.Start(data); err != nil {
			return err
		}
		st, err := setupTun(name, up, servers, opts)
		if st != nil {
			s.tun = st
			s.saveLeftovers()
		}
		if err != nil {
			s.stopLocked()
			return fmt.Errorf("cannot set up the tunnel: %w", err)
		}
	case "proxy", "":
		data, err := cfg.bytes()
		if err != nil {
			return err
		}
		if err := tek.Default.Start(data); err != nil {
			return err
		}
		if req.SystemProxy != nil {
			st, err := setSystemProxy(*req.SystemProxy)
			if st != nil {
				s.proxy = st
				s.saveLeftovers()
				armProxyRestore(s.dataDir)
			}
			if err != nil {
				s.stopLocked()
				return fmt.Errorf("cannot set the system proxy: %w", err)
			}
		}
	default:
		return fmt.Errorf("unknown mode %q", req.Mode)
	}
	s.mode = req.Mode
	s.since = time.Now()
	s.lastError = ""
	return nil
}

func (s *session) stop() {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.stopLocked()
}

func (s *session) stopLocked() {
	if s.proxy != nil {
		restoreSystemProxy(s.proxy)
		s.proxy = nil
		disarmProxyRestore()
	}
	_ = tek.Default.Stop()
	if s.tun != nil {
		teardownTun(s.tun)
		s.tun = nil
	}
	s.mode = ""
	s.saveLeftovers()
}

type statusReply struct {
	Running   bool   `json:"running"`
	Mode      string `json:"mode"`
	Since     int64  `json:"since,omitempty"`
	Elevated  bool   `json:"elevated"`
	Xray      string `json:"xray"`
	Tek       string `json:"tek"`
	LastError string `json:"lastError,omitempty"`
	PID       int    `json:"pid"`
	Up        int64  `json:"up"`
	Down      int64  `json:"down"`
}

func (s *session) status() statusReply {
	s.mu.Lock()
	defer s.mu.Unlock()
	running, _ := tek.Default.Running()
	r := statusReply{
		Running:   running,
		Mode:      s.mode,
		Elevated:  isElevated(),
		Xray:      tek.Version(),
		Tek:       version,
		LastError: s.lastError,
		PID:       os.Getpid(),
	}
	if running {
		r.Since = s.since.UnixMilli()
		r.Up, r.Down = tek.Default.Traffic("proxy")
	}
	return r
}

func serve(args []string) error {
	fs := flag.NewFlagSet("serve", flag.ContinueOnError)
	dataDir := fs.String("data", "", "directory for runtime files")
	tokenFile := fs.String("token-file", "", "file with the API token (deleted after reading)")
	readyFile := fs.String("ready-file", "", "file to write the listening port to")
	parent := fs.Int("parent", 0, "exit when this process exits")
	logLevel := fs.String("log-level", "warning", "journal level")
	if err := fs.Parse(args); err != nil {
		return err
	}
	if *dataDir == "" || *tokenFile == "" || *readyFile == "" {
		return errors.New("-data, -token-file and -ready-file are required")
	}
	tek.Logs.SetLevel(*logLevel)
	raw, err := os.ReadFile(*tokenFile)
	if err != nil {
		return fmt.Errorf("read token: %w", err)
	}
	_ = os.Remove(*tokenFile)
	token := strings.TrimSpace(string(raw))
	if len(token) < 16 {
		return errors.New("token is too short")
	}

	ready := func(port int) error {
		data, _ := json.Marshal(map[string]any{"port": port, "pid": os.Getpid(), "elevated": isElevated(), "version": version})
		return writeFileAtomic(*readyFile, data, 0o644, -1)
	}
	return runAPI(apiOptions{dataDir: *dataDir, token: token, parent: *parent, ready: ready})
}

type apiOptions struct {
	dataDir string
	token   string
	// parent is the app's process: tek-core stops when it exits.
	parent int
	// daemon is the macOS helper that launchd keeps running: "shutdown"
	// only disconnects, the service itself stays for the next connection.
	daemon bool
	// ready publishes the port once the API listens.
	ready func(port int) error
}

// writeFileAtomic writes the file next to its final name and renames it,
// so a reader never sees half of it. owner >= 0 hands the file to that
// user (the helper runs as root but its file is for the app).
func writeFileAtomic(path string, data []byte, mode os.FileMode, owner int) error {
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, data, mode); err != nil {
		return err
	}
	if owner >= 0 {
		if err := os.Chown(tmp, owner, -1); err != nil {
			_ = os.Remove(tmp)
			return err
		}
	}
	return os.Rename(tmp, path)
}

func runAPI(o apiOptions) error {
	token := o.token
	recoverLeftovers(o.dataDir)
	sess := &session{dataDir: o.dataDir}

	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return err
	}
	port := listener.Addr().(*net.TCPAddr).Port

	shutdown := make(chan struct{})
	var once sync.Once
	quit := func() { once.Do(func() { close(shutdown) }) }

	mux := http.NewServeMux()
	handle := func(path string, fn func(w http.ResponseWriter, r *http.Request)) {
		mux.HandleFunc(path, func(w http.ResponseWriter, r *http.Request) {
			got := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
			if subtle.ConstantTimeCompare([]byte(got), []byte(token)) != 1 {
				http.Error(w, "unauthorized", http.StatusUnauthorized)
				return
			}
			fn(w, r)
		})
	}

	handle("/v1/status", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, sess.status())
	})
	handle("/v1/start", func(w http.ResponseWriter, r *http.Request) {
		var req StartRequest
		if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 8<<20)).Decode(&req); err != nil {
			writeError(w, err)
			return
		}
		if err := sess.start(req); err != nil {
			sess.mu.Lock()
			sess.lastError = err.Error()
			sess.mu.Unlock()
			tek.Logs.Printf("error", "connect failed: %v", err)
			writeError(w, err)
			return
		}
		writeJSON(w, sess.status())
	})
	handle("/v1/stop", func(w http.ResponseWriter, r *http.Request) {
		sess.stop()
		writeJSON(w, sess.status())
	})
	handle("/v1/validate", func(w http.ResponseWriter, r *http.Request) {
		var req struct {
			Config json.RawMessage `json:"config"`
		}
		if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 8<<20)).Decode(&req); err != nil {
			writeError(w, err)
			return
		}
		if err := tek.Validate(req.Config); err != nil {
			writeError(w, err)
			return
		}
		writeJSON(w, map[string]bool{"ok": true})
	})
	handle("/v1/ping/real", func(w http.ResponseWriter, r *http.Request) {
		var req tek.RealPingRequest
		if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 8<<20)).Decode(&req); err != nil {
			writeError(w, err)
			return
		}
		if len(req.Config) > 0 {
			cfg, err := parseConfig(req.Config)
			if err != nil {
				writeError(w, err)
				return
			}
			cfg.sanitize()
			if req.Config, err = cfg.bytes(); err != nil {
				writeError(w, err)
				return
			}
		}
		writeJSON(w, tek.Default.RealPing(req))
	})
	handle("/v1/ping/tcp", func(w http.ResponseWriter, r *http.Request) {
		var req struct {
			Targets   []tek.TCPTarget `json:"targets"`
			TimeoutMs int             `json:"timeoutMs"`
			Attempts  int             `json:"attempts"`
		}
		if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<20)).Decode(&req); err != nil {
			writeError(w, err)
			return
		}
		writeJSON(w, tek.TCPPing(req.Targets, time.Duration(req.TimeoutMs)*time.Millisecond, req.Attempts, nil))
	})
	handle("/v1/ping/cancel", func(w http.ResponseWriter, r *http.Request) {
		tek.CancelPing()
		writeJSON(w, map[string]bool{"ok": true})
	})
	handle("/v1/logs", func(w http.ResponseWriter, r *http.Request) {
		since, _ := strconv.ParseInt(r.URL.Query().Get("since"), 10, 64)
		writeJSON(w, tek.Logs.Since(since))
	})
	handle("/v1/loglevel", func(w http.ResponseWriter, r *http.Request) {
		var req struct {
			Level string `json:"level"`
		}
		_ = json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<10)).Decode(&req)
		tek.Logs.SetLevel(req.Level)
		writeJSON(w, map[string]bool{"ok": true})
	})
	handle("/v1/shutdown", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, map[string]bool{"ok": true})
		if o.daemon {
			go sess.stop()
			return
		}
		go quit()
	})

	server := &http.Server{Handler: mux, ReadHeaderTimeout: 10 * time.Second}
	go func() {
		if err := server.Serve(listener); err != nil && !errors.Is(err, http.ErrServerClosed) {
			tek.Logs.Printf("error", "api: %v", err)
			quit()
		}
	}()

	if err := o.ready(port); err != nil {
		return err
	}

	if o.parent > 0 {
		go watchParent(o.parent, func() {
			tek.Logs.Printf("info", "the app has exited, stopping")
			quit()
		})
	}
	go handleSignals(quit)

	<-shutdown
	sess.stop()
	_ = server.Close()
	return nil
}

func writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(v)
}

func writeError(w http.ResponseWriter, err error) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusBadRequest)
	_ = json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
}
