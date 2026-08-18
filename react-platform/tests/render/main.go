// Rendert de Go-templates uit de react-tenants ApplicationSet voor een gegeven
// tenant-vorm, zodat run-tests.sh de uitvoer tegen golden files kan leggen.
//
// Alleen de standaardbibliotheek. De sprig-functies die de template gebruikt
// zijn hier nagebouwd; komt er een sprig-functie bij die hier ontbreekt, dan
// FAALT het parsen met "function ... not defined". Die divergentie is dus
// luidruchtig en niet stil — dat is bewust, want dit harnas benadert Argo's
// engine en is er niet identiek aan.
//
// Usage: render <template-bestand> <params.json>
package main

import (
	"encoding/json"
	"fmt"
	"os"
	"reflect"
	"strings"
	"text/template"
)

// isEmpty spiegelt sprig's notie van "leeg" voor de default-functie.
func isEmpty(v any) bool {
	if v == nil {
		return true
	}
	rv := reflect.ValueOf(v)
	switch rv.Kind() {
	case reflect.Map, reflect.Slice, reflect.Array, reflect.String:
		return rv.Len() == 0
	case reflect.Bool:
		return !rv.Bool()
	}
	return false
}

func indent(spaces int, v string) string {
	pad := strings.Repeat(" ", spaces)
	return pad + strings.ReplaceAll(v, "\n", "\n"+pad)
}

func funcs() template.FuncMap {
	return template.FuncMap{
		"default": func(d any, given ...any) any {
			if len(given) == 0 || isEmpty(given[0]) {
				return d
			}
			return given[0]
		},
		"dict": func(kv ...any) map[string]any {
			m := map[string]any{}
			for i := 0; i+1 < len(kv); i += 2 {
				m[fmt.Sprint(kv[i])] = kv[i+1]
			}
			return m
		},
		"list":       func(v ...any) []any { return v },
		"trimSuffix": func(suffix, s string) string { return strings.TrimSuffix(s, suffix) },
		// indent/nindent spiegelen sprig: élke regel krijgt de padding, ook een
		// lege regel. Dat is precies wat een YAML-blokscalar nodig heeft (een
		// regel met alleen padding leest als lege regel), en het houdt een
		// PGP-ondertekende tekst byte-exact.
		// hasKey onderscheidt "sleutel ontbreekt" van "sleutel staat op false".
		// `default` kan dat niet: die ziet false als leeg en geeft de default terug,
		// waardoor een expliciete `proxied: false` zou worden overruled.
		"hasKey": func(m any, k string) bool {
			mm, ok := m.(map[string]any)
			if !ok {
				return false
			}
			_, found := mm[k]
			return found
		},
		"indent":  indent,
		"nindent": func(spaces int, v string) string { return "\n" + indent(spaces, v) },
	}
}

func main() {
	if len(os.Args) != 3 {
		fmt.Fprintln(os.Stderr, "usage: render <template-bestand> <params.json>")
		os.Exit(2)
	}

	src, err := os.ReadFile(os.Args[1])
	if err != nil {
		fmt.Fprintf(os.Stderr, "kan template niet lezen: %v\n", err)
		os.Exit(1)
	}

	raw, err := os.ReadFile(os.Args[2])
	if err != nil {
		fmt.Fprintf(os.Stderr, "kan params niet lezen: %v\n", err)
		os.Exit(1)
	}

	var params map[string]any
	if err := json.Unmarshal(raw, &params); err != nil {
		fmt.Fprintf(os.Stderr, "params is geen geldige JSON: %v\n", err)
		os.Exit(1)
	}

	// missingkey=default spiegelt goTemplateOptions in de ApplicationSet.
	tmpl, err := template.New("t").Option("missingkey=default").Funcs(funcs()).Parse(string(src))
	if err != nil {
		fmt.Fprintf(os.Stderr, "template parst niet: %v\n", err)
		os.Exit(1)
	}

	if err := tmpl.Execute(os.Stdout, params); err != nil {
		fmt.Fprintf(os.Stderr, "template rendert niet: %v\n", err)
		os.Exit(1)
	}
}
