package source

import (
	"testing"
	"tonys-agent-harness/core"
)

func TestSourceCachePruneRoute(t *testing.T) {
	cmd := Command(core.NewApplication())
	found, _, err := cmd.Find([]string{"cache", "prune"})
	if err != nil || found == cmd {
		t.Fatalf("missing source cache prune route: %v", err)
	}
	if found.Flag("dry-run") == nil {
		t.Fatal("source cache prune has no dry-run flag")
	}
}
