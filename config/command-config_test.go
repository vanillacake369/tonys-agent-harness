package config

import (
	"testing"
	"tonys-agent-harness/core"
)

func TestConfigLifecycleCommandRoutes(t *testing.T) {
	cmd := Command(core.NewApplication())
	for _, route := range [][]string{
		{"init"},
		{"graph"},
		{"runtime", "reset"},
	} {
		found, _, err := cmd.Find(route)
		if err != nil || found == cmd {
			t.Fatalf("missing config route %v: %v", route, err)
		}
	}

	for _, route := range [][]string{
		{"status"}, {"edit"}, {"apply"}, {"scaffold"}, {"validate"}, {"workspace"},
		{"sync"}, {"unlock"}, {"lock"}, {"purge"},
	} {
		found, _, err := cmd.Find(route)
		if err == nil && found != cmd {
			t.Fatalf("legacy route still available: %v", route)
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
