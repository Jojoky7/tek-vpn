// geotrim builds the small geoip.dat and geosite.dat that ship inside the
// apps. Tek's routing only needs Russian sites and addresses and private
// networks, so the files hold just those lists instead of the full
// multi-megabyte databases.
//
//	geotrim -dlc <domain-list-community data dir> -ripe <delegated-ripencc-extended file> -out <dir>
//
// Sources: github.com/v2fly/domain-list-community (the "data" folder) and
// ftp.ripe.net/pub/stats/ripencc/delegated-ripencc-extended-latest.
package main

import (
	"bufio"
	"flag"
	"fmt"
	"math/big"
	"net/netip"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"

	"github.com/xtls/xray-core/app/router"
	"google.golang.org/protobuf/proto"
)

func main() {
	dlcDir := flag.String("dlc", "", "domain-list-community data folder")
	ripeFile := flag.String("ripe", "", "RIPE NCC delegated-extended statistics file")
	outDir := flag.String("out", ".", "where to write geoip.dat and geosite.dat")
	sites := flag.String("sites", "category-ru", "comma-separated lists for geosite.dat")
	country := flag.String("country", "RU", "country for geoip.dat")
	flag.Parse()
	if *dlcDir == "" || *ripeFile == "" {
		flag.Usage()
		os.Exit(2)
	}

	siteList, err := buildSites(*dlcDir, strings.Split(*sites, ","))
	check(err)
	ipList, err := buildIPs(*ripeFile, strings.ToUpper(*country))
	check(err)

	for name, msg := range map[string]proto.Message{"geosite.dat": siteList, "geoip.dat": ipList} {
		data, err := proto.Marshal(msg)
		check(err)
		check(os.WriteFile(filepath.Join(*outDir, name), data, 0o644))
		fmt.Printf("%s: %d bytes\n", name, len(data))
	}
}

func check(err error) {
	if err != nil {
		fmt.Fprintln(os.Stderr, "geotrim:", err)
		os.Exit(1)
	}
}

// --- domain lists ---------------------------------------------------------

type rule struct {
	typ   string // domain, full, keyword, regexp
	value string
	attrs []string
}

type inclusion struct {
	source    string
	must, ban []string
}

type list struct {
	rules      []rule
	inclusions []inclusion
}

func buildSites(dir string, names []string) (*router.GeoSiteList, error) {
	lists := map[string]*list{}
	get := func(name string) *list {
		if lists[name] == nil {
			lists[name] = &list{}
		}
		return lists[name]
	}
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		if err := loadList(filepath.Join(dir, e.Name()), strings.ToUpper(e.Name()), get); err != nil {
			return nil, err
		}
	}

	out := &router.GeoSiteList{}
	for _, name := range names {
		name = strings.ToUpper(strings.TrimSpace(name))
		rules, err := resolve(lists, name, map[string]bool{})
		if err != nil {
			return nil, err
		}
		site := &router.GeoSite{CountryCode: name}
		for _, r := range trim(rules) {
			d := &router.Domain{Value: r.value}
			switch r.typ {
			case "domain":
				d.Type = router.Domain_Domain
			case "full":
				d.Type = router.Domain_Full
			case "keyword":
				d.Type = router.Domain_Plain
			case "regexp":
				d.Type = router.Domain_Regex
			}
			site.Domain = append(site.Domain, d)
		}
		fmt.Printf("%s: %d rules\n", name, len(site.Domain))
		out.Entry = append(out.Entry, site)
	}
	return out, nil
}

func loadList(path, name string, get func(string) *list) error {
	f, err := os.Open(path)
	if err != nil {
		return err
	}
	defer f.Close()
	l := get(name)
	sc := bufio.NewScanner(f)
	for n := 1; sc.Scan(); n++ {
		line, _, _ := strings.Cut(sc.Text(), "#")
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		typ, body, ok := strings.Cut(line, ":")
		if !ok {
			typ, body = "domain", line
		}
		typ = strings.ToLower(typ)
		fields := strings.Fields(body)
		if len(fields) == 0 {
			return fmt.Errorf("%s:%d: empty rule", path, n)
		}
		if typ == "include" {
			inc := inclusion{source: strings.ToUpper(fields[0])}
			for _, f := range fields[1:] {
				if a, ok := strings.CutPrefix(f, "@-"); ok {
					inc.ban = append(inc.ban, strings.ToLower(a))
				} else if a, ok := strings.CutPrefix(f, "@"); ok {
					inc.must = append(inc.must, strings.ToLower(a))
				}
			}
			l.inclusions = append(l.inclusions, inc)
			continue
		}
		switch typ {
		case "domain", "full", "keyword", "regexp":
		default:
			return fmt.Errorf("%s:%d: unknown rule type %q", path, n, typ)
		}
		r := rule{typ: typ, value: fields[0]}
		if typ != "regexp" {
			r.value = strings.ToLower(r.value)
		}
		var affiliations []string
		for _, f := range fields[1:] {
			switch f[0] {
			case '@':
				r.attrs = append(r.attrs, strings.ToLower(f[1:]))
			case '&':
				affiliations = append(affiliations, strings.ToUpper(f[1:]))
			}
		}
		l.rules = append(l.rules, r)
		for _, a := range affiliations {
			get(a).rules = append(get(a).rules, r)
		}
	}
	return sc.Err()
}

func resolve(lists map[string]*list, name string, visiting map[string]bool) ([]rule, error) {
	l, ok := lists[name]
	if !ok {
		return nil, fmt.Errorf("list %q not found", name)
	}
	if visiting[name] {
		return nil, fmt.Errorf("circular inclusion of %q", name)
	}
	visiting[name] = true
	defer delete(visiting, name)

	out := slices.Clone(l.rules)
	for _, inc := range l.inclusions {
		rules, err := resolve(lists, inc.source, visiting)
		if err != nil {
			return nil, err
		}
		for _, r := range rules {
			if matchAttrs(r, inc) {
				out = append(out, r)
			}
		}
	}
	return out, nil
}

func matchAttrs(r rule, inc inclusion) bool {
	for _, m := range inc.must {
		if !slices.Contains(r.attrs, m) {
			return false
		}
	}
	for _, b := range inc.ban {
		if slices.Contains(r.attrs, b) {
			return false
		}
	}
	return true
}

// trim drops duplicates and rules already covered by a parent domain rule
// (with "domain:ru" in the list, "domain:yandex.ru" adds nothing).
func trim(rules []rule) []rule {
	parents := map[string]bool{}
	for _, r := range rules {
		if r.typ == "domain" {
			parents[r.value] = true
		}
	}
	seen := map[string]bool{}
	var out []rule
	for _, r := range rules {
		key := r.typ + ":" + r.value
		if seen[key] {
			continue
		}
		seen[key] = true
		if r.typ == "domain" || r.typ == "full" {
			covered := r.typ == "full" && parents[r.value]
			for d := r.value; !covered; {
				_, rest, ok := strings.Cut(d, ".")
				if !ok {
					break
				}
				covered = parents[rest]
				d = rest
			}
			if covered {
				continue
			}
		}
		out = append(out, r)
	}
	slices.SortFunc(out, func(a, b rule) int {
		return strings.Compare(a.typ+":"+a.value, b.typ+":"+b.value)
	})
	return out
}

// --- addresses --------------------------------------------------------------

var privateNets = []string{
	"0.0.0.0/8", "10.0.0.0/8", "100.64.0.0/10", "127.0.0.0/8", "169.254.0.0/16",
	"172.16.0.0/12", "192.0.0.0/24", "192.0.2.0/24", "192.88.99.0/24",
	"192.168.0.0/16", "198.18.0.0/15", "198.51.100.0/24", "203.0.113.0/24",
	"224.0.0.0/4", "240.0.0.0/4", "255.255.255.255/32",
	"::/128", "::1/128", "fc00::/7", "fe80::/10", "ff00::/8",
}

type ipRange struct{ from, to netip.Addr }

func buildIPs(ripeFile, country string) (*router.GeoIPList, error) {
	f, err := os.Open(ripeFile)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	var ranges []ipRange
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		parts := strings.Split(sc.Text(), "|")
		if len(parts) < 7 || parts[1] != country {
			continue
		}
		if parts[6] != "allocated" && parts[6] != "assigned" {
			continue
		}
		start, err := netip.ParseAddr(parts[3])
		if err != nil {
			continue
		}
		n, err := strconv.ParseUint(parts[4], 10, 64)
		if err != nil || n == 0 {
			continue
		}
		switch parts[2] {
		case "ipv4":
			ranges = append(ranges, ipRange{start, addOffset(start, new(big.Int).SetUint64(n-1))})
		case "ipv6":
			if n > 128 {
				continue
			}
			p := netip.PrefixFrom(start, int(n)).Masked()
			ranges = append(ranges, ipRange{p.Addr(), lastAddr(p)})
		}
	}
	if err := sc.Err(); err != nil {
		return nil, err
	}
	if len(ranges) == 0 {
		return nil, fmt.Errorf("no %s addresses in %s", country, ripeFile)
	}

	countryIP := &router.GeoIP{CountryCode: country}
	for _, p := range toPrefixes(merge(ranges)) {
		countryIP.Cidr = append(countryIP.Cidr, &router.CIDR{Ip: p.Addr().AsSlice(), Prefix: uint32(p.Bits())})
	}
	private := &router.GeoIP{CountryCode: "PRIVATE"}
	for _, s := range privateNets {
		p := netip.MustParsePrefix(s)
		private.Cidr = append(private.Cidr, &router.CIDR{Ip: p.Addr().AsSlice(), Prefix: uint32(p.Bits())})
	}
	fmt.Printf("%s: %d networks, PRIVATE: %d networks\n", country, len(countryIP.Cidr), len(private.Cidr))
	return &router.GeoIPList{Entry: []*router.GeoIP{countryIP, private}}, nil
}

func toInt(a netip.Addr) *big.Int { return new(big.Int).SetBytes(a.AsSlice()) }

func fromInt(v *big.Int, is4 bool) netip.Addr {
	size := 16
	if is4 {
		size = 4
	}
	b := v.FillBytes(make([]byte, size))
	a, _ := netip.AddrFromSlice(b)
	return a
}

func addOffset(a netip.Addr, off *big.Int) netip.Addr {
	return fromInt(new(big.Int).Add(toInt(a), off), a.Is4())
}

func lastAddr(p netip.Prefix) netip.Addr {
	bits := p.Addr().BitLen()
	hostBits := bits - p.Bits()
	span := new(big.Int).Sub(new(big.Int).Lsh(big.NewInt(1), uint(hostBits)), big.NewInt(1))
	return fromInt(new(big.Int).Add(toInt(p.Addr()), span), p.Addr().Is4())
}

// merge sorts the ranges and joins those that overlap or touch.
func merge(in []ipRange) []ipRange {
	slices.SortFunc(in, func(a, b ipRange) int {
		if a.from.Is4() != b.from.Is4() {
			if a.from.Is4() {
				return -1
			}
			return 1
		}
		return a.from.Compare(b.from)
	})
	var out []ipRange
	for _, r := range in {
		if n := len(out); n > 0 && out[n-1].from.Is4() == r.from.Is4() {
			last := &out[n-1]
			next := last.to.Next()
			if r.from.Compare(last.to) <= 0 || (next.IsValid() && r.from == next) {
				if r.to.Compare(last.to) > 0 {
					last.to = r.to
				}
				continue
			}
		}
		out = append(out, r)
	}
	return out
}

// toPrefixes cuts each range into the fewest CIDR blocks.
func toPrefixes(ranges []ipRange) []netip.Prefix {
	var out []netip.Prefix
	for _, r := range ranges {
		from, to := toInt(r.from), toInt(r.to)
		bits := r.from.BitLen()
		for from.Cmp(to) <= 0 {
			// The largest block that starts at "from" and stays inside the range.
			size := bits
			for size > 0 {
				p := netip.PrefixFrom(fromInt(from, r.from.Is4()), size-1)
				if p.Masked().Addr() != p.Addr() || toInt(lastAddr(p)).Cmp(to) > 0 {
					break
				}
				size--
			}
			p := netip.PrefixFrom(fromInt(from, r.from.Is4()), size)
			out = append(out, p)
			from = new(big.Int).Add(toInt(lastAddr(p)), big.NewInt(1))
		}
	}
	return out
}
