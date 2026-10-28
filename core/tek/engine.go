// Package tek runs Xray-core for the Tek app: one long-lived instance for the
// VPN itself and, when that is not running, a short-lived instance for
// checking servers.
package tek

import (
	"bytes"
	"crypto/sha256"
	"errors"
	"sync"
	"time"

	"github.com/xtls/xray-core/core"
	"github.com/xtls/xray-core/features/stats"
	"github.com/xtls/xray-core/infra/conf/serial"
)

// Version of the bundled Xray-core.
func Version() string {
	return core.Version()
}

// BuildConfig parses Xray JSON and builds it with Xray's own config builder,
// so a config that passes here is exactly what Xray will run.
func BuildConfig(configJSON []byte) (*core.Config, error) {
	jsonConfig, err := serial.DecodeJSONConfig(bytes.NewReader(configJSON))
	if err != nil {
		return nil, err
	}
	return jsonConfig.Build()
}

// Validate reports whether Xray accepts the config, without starting it.
func Validate(configJSON []byte) error {
	_, err := BuildConfig(configJSON)
	return err
}

// Engine owns the Xray instances of the process. Xray-core keeps some state
// process-wide, so the engine never runs two instances at the same time: the
// probe instance is closed before the VPN instance starts, and while the VPN
// runs, server checks go through the running instance.
type Engine struct {
	mu        sync.Mutex
	inst      *core.Instance
	startedAt time.Time

	probe     *core.Instance
	probeHash [32]byte
	probeUsed time.Time
}

// Default is the engine used by the app.
var Default = &Engine{}

// Start replaces any running instance with a new one built from the config.
func (e *Engine) Start(configJSON []byte) error {
	e.mu.Lock()
	defer e.mu.Unlock()

	e.closeProbeLocked()
	if e.inst != nil {
		closeInstance(e.inst)
		e.inst = nil
	}

	config, err := BuildConfig(configJSON)
	if err != nil {
		return err
	}
	inst, err := core.New(config)
	Logs.Install()
	if err != nil {
		return err
	}
	if err := inst.Start(); err != nil {
		closeInstance(inst)
		return err
	}
	e.inst = inst
	e.startedAt = time.Now()
	Logs.Printf("info", "Xray %s started", core.Version())
	return nil
}

// Stop closes the running instance, if any.
func (e *Engine) Stop() error {
	e.mu.Lock()
	defer e.mu.Unlock()
	e.closeProbeLocked()
	if e.inst == nil {
		return nil
	}
	err := closeInstance(e.inst)
	e.inst = nil
	Logs.Printf("info", "Xray stopped")
	return err
}

// closeInstance closes an instance together with its tun device, which
// Xray itself leaves open.
func closeInstance(inst *core.Instance) error {
	tuns := tunInbounds(inst)
	err := inst.Close()
	for _, t := range tuns {
		closeTun(t)
	}
	return err
}

// Running reports whether the VPN instance is up, and since when.
func (e *Engine) Running() (bool, time.Time) {
	e.mu.Lock()
	defer e.mu.Unlock()
	return e.inst != nil, e.startedAt
}

// Traffic returns the bytes sent and received through the outbound with the
// given tag since the VPN started. The config has to turn on outbound stats
// (policy.system.statsOutboundUplink and statsOutboundDownlink).
func (e *Engine) Traffic(tag string) (up, down int64) {
	e.mu.Lock()
	defer e.mu.Unlock()
	if e.inst == nil {
		return 0, 0
	}
	m, ok := e.inst.GetFeature(stats.ManagerType()).(stats.Manager)
	if !ok || m == nil {
		return 0, 0
	}
	if c := m.GetCounter("outbound>>>" + tag + ">>>traffic>>>uplink"); c != nil {
		up = c.Value()
	}
	if c := m.GetCounter("outbound>>>" + tag + ">>>traffic>>>downlink"); c != nil {
		down = c.Value()
	}
	return up, down
}

// instanceForProbe returns the running instance, or a probe instance built
// from probeConfig. The caller must hold e.mu.
func (e *Engine) instanceForProbe(probeConfig []byte) (*core.Instance, error) {
	if e.inst != nil {
		return e.inst, nil
	}
	if len(probeConfig) == 0 {
		return nil, errors.New("no config to check servers with")
	}
	hash := sha256.Sum256(probeConfig)
	if e.probe != nil && hash == e.probeHash {
		e.probeUsed = time.Now()
		return e.probe, nil
	}
	e.closeProbeLocked()
	config, err := BuildConfig(probeConfig)
	if err != nil {
		return nil, err
	}
	inst, err := core.New(config)
	Logs.Install()
	if err != nil {
		return nil, err
	}
	if err := inst.Start(); err != nil {
		_ = inst.Close()
		return nil, err
	}
	e.probe, e.probeHash, e.probeUsed = inst, hash, time.Now()
	go e.closeIdleProbe(inst)
	return inst, nil
}

// closeIdleProbe closes the probe instance once nobody used it for a while.
func (e *Engine) closeIdleProbe(inst *core.Instance) {
	for {
		time.Sleep(10 * time.Second)
		e.mu.Lock()
		if e.probe != inst {
			e.mu.Unlock()
			return
		}
		if time.Since(e.probeUsed) > 45*time.Second {
			e.closeProbeLocked()
			e.mu.Unlock()
			return
		}
		e.mu.Unlock()
	}
}

func (e *Engine) closeProbeLocked() {
	if e.probe != nil {
		_ = e.probe.Close()
		e.probe = nil
	}
}
