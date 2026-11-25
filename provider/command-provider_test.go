package provider

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"tonys-agent-harness/core"

	"github.com/spf13/cobra"
)

func TestProviderCompletionReadsCatalog(t *testing.T) {
	repo := t.TempDir()
	mustProviderTest(t, os.MkdirAll(filepath.Join(repo, "core"), 0700))
	mustProviderTest(t, os.MkdirAll(filepath.Join(repo, "provider"), 0700))
	mustProviderTest(t, os.WriteFile(filepath.Join(repo, "core/environment-public.txt"), []byte("fixture\n"), 0600))
	catalog := `{"providers":[
  {"name":"alpha","skills_path":".alpha/skills","default":true},
  {"name":"beta","skills_path":".beta/skills"}
]}`
	mustProviderTest(t, os.WriteFile(filepath.Join(repo, "provider/provider-catalog.json"), []byte(catalog), 0600))
	t.Setenv("HARNESS_REPO", repo)

	names, directive := providerCompletion(core.NewApplication())(&cobra.Command{}, nil, "b")
	if directive != cobra.ShellCompDirectiveNoFileComp || strings.Join(names, ",") != "beta" {
		t.Fatalf("unexpected completion: %v directive=%d", names, directive)
	}
}

func mustProviderTest(t *testing.T, err error) {
	t.Helper()
	if err != nil {
		t.Fatal(err)
	}
}
