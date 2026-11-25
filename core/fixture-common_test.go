package core

import (
	"os"
	"path/filepath"
	"testing"
)

func must(t testing.TB, err error) {
	t.Helper()
	if err != nil {
		t.Fatal(err)
	}
}

func put(t testing.TB, path, body string) {
	t.Helper()
	must(t, os.MkdirAll(filepath.Dir(path), 0700))
	must(t, os.WriteFile(path, []byte(body), 0600))
}

func temp(t testing.TB) string {
	t.Helper()
	p, err := filepath.EvalSymlinks(t.TempDir())
	must(t, err)
	return p
}

func fixtureConfig(t testing.TB) config {
	root := temp(t)
	c := config{
		repo: filepath.Join(root, "repo"), state: filepath.Join(root, "state"), key: filepath.Join(root, "key"),
	}
	c.workspace = filepath.Join(c.state, "capability")
	c.runtime = filepath.Join(c.state, "runtime")
	c.archive = filepath.Join(c.repo, "capability.enc")
	must(t, os.MkdirAll(c.repo, 0700))
	must(t, privateDir(c.state))
	put(t, filepath.Join(c.repo, "source/registry-sources.json"), `{}`)
	put(t, filepath.Join(c.repo, "provider/provider-catalog.json"), `{
  "providers": [
    {"name": "claude", "skills_path": ".claude/skills"},
    {"name": "codex", "skills_path": ".codex/skills", "default": true},
    {"name": "kiro", "skills_path": ".kiro/skills"}
  ]
}`)
	put(t, filepath.Join(c.repo, "core/environment-public.txt"), "fixture marker\n")
	put(t, c.key, "test-only-not-an-age-key")
	return c
}

func fixtureTree(t testing.TB, root string) {
	must(t, emptyTree(root))
	put(t, filepath.Join(root, "agent/reviewer.md"),
		"# Fixture\n\n```json composition\n{\"requires\":[],\"hints\":[]}\n```\n")
}

func integrationOnly(t *testing.T) {
	t.Helper()
	if testing.Short() {
		t.Skip("integration test")
	}
}
