package tek

import (
	"fmt"
	"strings"
	"sync"
	"time"

	xlog "github.com/xtls/xray-core/common/log"
)

// LogLine is one entry of the in-memory journal shown in the app.
type LogLine struct {
	ID    int64  `json:"id"`
	Time  string `json:"time"`
	Level string `json:"level"`
	Text  string `json:"text"`
}

const logCapacity = 3000

// Journal keeps the latest Xray and Tek messages in memory. Nothing is written
// to disk: the app shows the journal on demand and the user decides whether
// to copy it.
type Journal struct {
	mu      sync.Mutex
	lines   []LogLine
	nextID  int64
	level   xlog.Severity
	access  bool
}

// Logs is the process-wide journal.
var Logs = &Journal{level: xlog.Severity_Warning}

// SetLevel accepts "error", "warning", "info" or "debug". "debug" also records
// connection (access) messages.
func (j *Journal) SetLevel(level string) {
	j.mu.Lock()
	defer j.mu.Unlock()
	switch strings.ToLower(level) {
	case "error":
		j.level, j.access = xlog.Severity_Error, false
	case "info":
		j.level, j.access = xlog.Severity_Info, false
	case "debug":
		j.level, j.access = xlog.Severity_Debug, true
	default:
		j.level, j.access = xlog.Severity_Warning, false
	}
}

// Handle implements the Xray log handler interface.
func (j *Journal) Handle(msg xlog.Message) {
	switch m := msg.(type) {
	case *xlog.GeneralMessage:
		j.mu.Lock()
		allowed := m.Severity <= j.level
		j.mu.Unlock()
		if allowed {
			j.add(severityName(m.Severity), fmt.Sprint(m.Content))
		}
	case *xlog.AccessMessage, *xlog.DNSLog:
		j.mu.Lock()
		allowed := j.access
		j.mu.Unlock()
		if allowed {
			j.add("access", msg.String())
		}
	}
}

// Printf adds a Tek message (not from Xray) to the journal.
func (j *Journal) Printf(level, format string, args ...any) {
	j.add(level, fmt.Sprintf(format, args...))
}

func (j *Journal) add(level, text string) {
	j.mu.Lock()
	defer j.mu.Unlock()
	j.nextID++
	j.lines = append(j.lines, LogLine{
		ID:    j.nextID,
		Time:  time.Now().Format("15:04:05.000"),
		Level: level,
		Text:  text,
	})
	if len(j.lines) > logCapacity {
		j.lines = append([]LogLine(nil), j.lines[len(j.lines)-logCapacity:]...)
	}
}

// Since returns the lines with an ID greater than the given one.
func (j *Journal) Since(id int64) []LogLine {
	j.mu.Lock()
	defer j.mu.Unlock()
	out := make([]LogLine, 0, 64)
	for _, l := range j.lines {
		if l.ID > id {
			out = append(out, l)
		}
	}
	return out
}

// Install makes the journal the current Xray log handler. Xray replaces the
// handler whenever a new instance is created, so the engine calls this after
// every core.New.
func (j *Journal) Install() {
	xlog.RegisterHandler(j)
}

func severityName(s xlog.Severity) string {
	switch s {
	case xlog.Severity_Error:
		return "error"
	case xlog.Severity_Warning:
		return "warning"
	case xlog.Severity_Info:
		return "info"
	case xlog.Severity_Debug:
		return "debug"
	default:
		return "unknown"
	}
}
