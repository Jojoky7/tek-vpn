package tek

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net"
	"net/http"
	"strconv"
	"sync"
	"time"

	xnet "github.com/xtls/xray-core/common/net"
	"github.com/xtls/xray-core/common/session"
	"github.com/xtls/xray-core/core"
)

// DefaultProbeURL answers 204 and is reachable from every server location.
const DefaultProbeURL = "https://www.gstatic.com/generate_204"

// RealPingRequest asks to check servers by making a real request through them.
type RealPingRequest struct {
	// Config is used only when the VPN is not running. It must contain the
	// outbounds named in Tags.
	Config    json.RawMessage `json:"config"`
	Tags      []string        `json:"tags"`
	URL       string          `json:"url"`
	TimeoutMs int             `json:"timeoutMs"`
	Attempts  int             `json:"attempts"`
}

// PingResult is the outcome for one server. Ms is -1 when every attempt failed.
type PingResult struct {
	Tag      string `json:"tag,omitempty"`
	Host     string `json:"host,omitempty"`
	Port     int    `json:"port,omitempty"`
	Ms       int64  `json:"ms"`
	Attempts int    `json:"attempts"`
	Error    string `json:"error,omitempty"`
}

var (
	pingMu     sync.Mutex
	pingCancel context.CancelFunc
)

// CancelPing aborts a running check, so connecting is never delayed by it.
func CancelPing() {
	pingMu.Lock()
	defer pingMu.Unlock()
	if pingCancel != nil {
		pingCancel()
	}
}

func pingContext() (context.Context, func()) {
	ctx, cancel := context.WithCancel(context.Background())
	pingMu.Lock()
	pingCancel = cancel
	pingMu.Unlock()
	return ctx, func() {
		cancel()
		pingMu.Lock()
		pingCancel = nil
		pingMu.Unlock()
	}
}

// RealPing checks the servers one after another. Checking them all at once
// makes some Russian providers drop part of the handshakes, which is why
// Happ sometimes shows "n/a"; one at a time with retries gives a stable answer.
func (e *Engine) RealPing(req RealPingRequest) []PingResult {
	if req.URL == "" {
		req.URL = DefaultProbeURL
	}
	if req.TimeoutMs <= 0 {
		req.TimeoutMs = 5000
	}
	if req.Attempts <= 0 {
		req.Attempts = 3
	}
	ctx, done := pingContext()
	defer done()

	results := make([]PingResult, 0, len(req.Tags))
	for _, tag := range req.Tags {
		res := PingResult{Tag: tag, Ms: -1}
		for attempt := 1; attempt <= req.Attempts; attempt++ {
			if ctx.Err() != nil {
				res.Error = "cancelled"
				break
			}
			res.Attempts = attempt
			ms, err := e.realPingOnce(ctx, req.Config, tag, req.URL, time.Duration(req.TimeoutMs)*time.Millisecond)
			if err == nil {
				res.Ms, res.Error = ms, ""
				break
			}
			res.Error = err.Error()
		}
		results = append(results, res)
	}
	return results
}

func (e *Engine) realPingOnce(ctx context.Context, probeConfig []byte, tag, url string, timeout time.Duration) (int64, error) {
	e.mu.Lock()
	inst, err := e.instanceForProbe(probeConfig)
	e.mu.Unlock()
	if err != nil {
		return -1, err
	}

	transport := &http.Transport{
		Proxy:             nil,
		DisableKeepAlives: true,
		DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
			dest, err := xnet.ParseDestination(network + ":" + addr)
			if err != nil {
				return nil, err
			}
			content := &session.Content{SkipDNSResolve: true}
			ctx = session.ContextWithContent(ctx, content)
			ctx = session.SetForcedOutboundTagToContext(ctx, tag)
			return core.Dial(ctx, inst, dest)
		},
		TLSHandshakeTimeout: timeout,
	}
	defer transport.CloseIdleConnections()
	client := &http.Client{
		Transport: transport,
		Timeout:   timeout,
		CheckRedirect: func(*http.Request, []*http.Request) error {
			return http.ErrUseLastResponse
		},
	}

	reqCtx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	request, err := http.NewRequestWithContext(reqCtx, http.MethodGet, url, nil)
	if err != nil {
		return -1, err
	}
	request.Header.Set("User-Agent", "Mozilla/5.0")
	start := time.Now()
	resp, err := client.Do(request)
	if err != nil {
		return -1, simplifyError(err)
	}
	_, _ = io.Copy(io.Discard, io.LimitReader(resp.Body, 64<<10))
	_ = resp.Body.Close()
	if resp.StatusCode >= 500 {
		return -1, errors.New("HTTP " + strconv.Itoa(resp.StatusCode))
	}
	return time.Since(start).Milliseconds(), nil
}

// TCPTarget is a server address for TCPPing.
type TCPTarget struct {
	Host string `json:"host"`
	Port int    `json:"port"`
}

// TCPPing measures how long it takes to open a TCP connection to each server.
// It only shows the distance to the server, not whether the VPN works there.
func TCPPing(targets []TCPTarget, timeout time.Duration, attempts int, dialer *net.Dialer) []PingResult {
	if timeout <= 0 {
		timeout = 3 * time.Second
	}
	if attempts <= 0 {
		attempts = 2
	}
	if dialer == nil {
		dialer = &net.Dialer{}
	}
	ctx, done := pingContext()
	defer done()

	results := make([]PingResult, 0, len(targets))
	for _, t := range targets {
		res := PingResult{Host: t.Host, Port: t.Port, Ms: -1}
		for attempt := 1; attempt <= attempts; attempt++ {
			if ctx.Err() != nil {
				res.Error = "cancelled"
				break
			}
			res.Attempts = attempt
			dctx, cancel := context.WithTimeout(ctx, timeout)
			start := time.Now()
			conn, err := dialer.DialContext(dctx, "tcp", net.JoinHostPort(t.Host, strconv.Itoa(t.Port)))
			elapsed := time.Since(start)
			cancel()
			if err == nil {
				_ = conn.Close()
				if res.Ms < 0 || elapsed.Milliseconds() < res.Ms {
					res.Ms = elapsed.Milliseconds()
				}
				res.Error = ""
				break
			}
			res.Error = simplifyError(err).Error()
		}
		results = append(results, res)
	}
	return results
}

// simplifyError keeps the last, most specific part of nested network errors.
func simplifyError(err error) error {
	var netErr net.Error
	if errors.As(err, &netErr) && netErr.Timeout() {
		return errors.New("timeout")
	}
	msg := err.Error()
	if len(msg) > 300 {
		msg = msg[len(msg)-300:]
	}
	return errors.New(msg)
}
