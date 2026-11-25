package config

import (
	"testing"
	"tonys-agent-harness/core"
)

func TestConfigLifecycleCommandRoutes(t *testing.T) {
	cmd := Command(core.NewApplication())
	for _, route := range [][]string{
		{"apply"},
		{"workspace", "open"},
		{"workspace", "close"},
		{"runtime", "reset"},
	} {
		found, _, err := cmd.Find(route)
		if err != nil || found == cmd {
			t.Fatalf("missing config route %v: %v", route, err)
		}
	}

	for _, name := range []string{"sync", "unlock", "lock", "purge"} {
		found, _, err := cmd.Find([]string{name})
		if err != nil {
			t.Fatalf("missing compatibility route %s: %v", name, err)
		}
		if !found.Hidden {
			t.Fatalf("compatibility route %s is visible in normal help", name)
		}
	}
}

func TestInitRequiresExplicitSource(t *testing.T) {
	cmd := commandInit(core.NewApplication())
	if err := cmd.Args(cmd, nil); err == nil {
		t.Fatal("init accepted a missing source")
	}
	if err := cmd.Args(cmd, []string{"empty"}); err != nil {
		t.Fatalf("init rejected one explicit source: %v", err)
	}
}
