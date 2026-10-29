// tek-core is the desktop side of Tek: the app starts it in the background
// and talks to it over a local HTTP API. It runs Xray and, depending on the
// mode, sets the system proxy or brings up the TUN interface and routes
// ("весь трафик" mode, which needs administrator rights).
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"

	"github.com/jojoky7/tek-vpn/core/tek"
)

// version of tek-core itself; the build sets it with -ldflags -X.
var version = "dev"

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(2)
	}
	switch os.Args[1] {
	case "version":
		_ = json.NewEncoder(os.Stdout).Encode(map[string]string{"tek": version, "xray": tek.Version()})
	case "validate":
		fs := flag.NewFlagSet("validate", flag.ExitOnError)
		path := fs.String("config", "", "Xray JSON config to check")
		_ = fs.Parse(os.Args[2:])
		data, err := os.ReadFile(*path)
		if err == nil {
			err = tek.Validate(data)
		}
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		fmt.Println("ok")
	case "serve":
		if err := serve(os.Args[2:]); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
	case "daemon":
		if err := daemon(os.Args[2:]); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
	case "restore":
		// Undo system changes left by a crashed session (proxy, routes, DNS).
		fs := flag.NewFlagSet("restore", flag.ExitOnError)
		data := fs.String("data", "", "data directory")
		_ = fs.Parse(os.Args[2:])
		recoverLeftovers(*data)
	default:
		usage()
		os.Exit(2)
	}
}

func usage() {
	fmt.Fprintln(os.Stderr, `usage:
  tek-core version
  tek-core validate -config FILE
  tek-core serve -data DIR -token-file FILE -ready-file FILE [-parent PID]
  tek-core daemon -owner UID -dir DIR
  tek-core restore -data DIR`)
}
