package core

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestConnectUsesCodexSkillsDir(t *testing.T) {
	c := fixtureConfig(t)
	must(t, privateDir(c.runtime))
	generation := filepath.Join(c.runtime, "generation-test")
	must(t, os.Mkdir(generation, 0700))
	must(t, os.Mkdir(filepath.Join(generation, "example"), 0700))
	must(t, os.Symlink(generation, filepath.Join(c.runtime, "skills")))

	home := temp(t)
	t.Setenv("HOME", home)
	must(t, connect(c, []string{"codex"}))

	link := filepath.Join(home, ".codex", "skills")
	actual, err := os.Readlink(filepath.Join(link, "example"))
	must(t, err)
	if actual != filepath.Join(c.runtime, "skills", "example") {
		t.Fatalf("unexpected Codex Skills link: %s", actual)
	}
	if exists(filepath.Join(home, ".agents")) {
		t.Fatal("legacy Codex Skills directory created")
	}
}

func TestProviderCatalogOwnsNamesDefaultAndLinks(t *testing.T) {
	c := fixtureConfig(t)
	put(t, filepath.Join(c.repo, "provider/provider-catalog.json"), `{
  "providers": [
    {"name": "alpha", "skills_path": ".alpha/extensions", "default": true},
    {"name": "beta", "skills_path": ".config/beta/skills"}
  ]
}`)
	home := temp(t)
	t.Setenv("HOME", home)

	names, defaultName, err := providerNames(c)
	must(t, err)
	if strings.Join(names, ",") != "alpha,beta" || defaultName != "alpha" {
		t.Fatalf("unexpected provider catalog: %v default=%s", names, defaultName)
	}
	link, err := providerLink(c, "beta")
	must(t, err)
	if link != filepath.Join(home, ".config/beta/skills") {
		t.Fatalf("unexpected provider link: %s", link)
	}
}

func TestProviderCatalogRejectsUnsafePath(t *testing.T) {
	c := fixtureConfig(t)
	put(t, filepath.Join(c.repo, "provider/provider-catalog.json"), `{
  "providers": [
    {"name": "escape", "skills_path": "../outside", "default": true}
  ]
}`)
	if _, err := providerDefinitions(c); err == nil {
		t.Fatal("unsafe provider path accepted")
	}
}

func TestV17ProviderDisconnect(t *testing.T) {
	c := fixtureConfig(t)
	home := temp(t)
	t.Setenv("HOME", home)
	link := filepath.Join(home, ".codex", "skills")
	put(t, link, "unmanaged")
	if providerDisconnect(c, "codex") == nil {
		t.Fatal("unmanaged target removed")
	}
	must(t, os.Remove(link))
	must(t, os.Symlink(filepath.Join(c.runtime, "skills"), link))
	must(t, providerDisconnect(c, "codex"))
	if exists(link) {
		t.Fatal("managed link retained")
	}
	must(t, providerDisconnect(c, "codex"))
}

func TestProviderCoexistenceAndRepair(t *testing.T) {
	c := fixtureConfig(t)
	home := temp(t)
	t.Setenv("HOME", home)
	live := filepath.Join(c.runtime, "generation-test")
	must(t, os.MkdirAll(filepath.Join(live, "first"), 0700))
	must(t, os.Symlink(live, filepath.Join(c.runtime, "skills")))
	link, _ := providerLink(c, "codex")
	put(t, filepath.Join(link, "external", "SKILL.md"), "keep")
	state, err := providerState(c, "codex")
	must(t, err)
	if state != "DISABLED" {
		t.Fatal(state)
	}
	must(t, connect(c, []string{"codex"}))
	must(t, os.Remove(filepath.Join(link, "first")))
	state, err = providerState(c, "codex")
	must(t, err)
	if state != "DRIFTED" {
		t.Fatal(state)
	}
	links, err := providerPreflight(c, live)
	must(t, err)
	must(t, providerReconcile(c, links))
	must(t, os.Mkdir(filepath.Join(live, "second"), 0700))
	put(t, filepath.Join(link, "second", "SKILL.md"), "external collision")
	if _, err = providerPreflight(c, live); err == nil {
		t.Fatal("conflict accepted")
	}
	must(t, providerDisconnect(c, "codex"))
	if exists(filepath.Join(link, "first")) || !exists(filepath.Join(link, "external", "SKILL.md")) ||
		!exists(filepath.Join(link, "second", "SKILL.md")) {
		t.Fatal("incorrect ownership cleanup")
	}
}

func TestProviderConflictDoesNotApprove(t *testing.T) {
	c := fixtureConfig(t)
	t.Setenv("HOME", temp(t))
	live := filepath.Join(c.runtime, "generation-test")
	must(t, os.MkdirAll(filepath.Join(live, "first"), 0700))
	must(t, os.Symlink(live, filepath.Join(c.runtime, "skills")))
	link, _ := providerLink(c, "codex")
	put(t, filepath.Join(link, "first", "SKILL.md"), "external")
	if connect(c, []string{"codex"}) == nil {
		t.Fatal("conflict accepted")
	}
	if exists(providerMarker(c, "codex")) {
		t.Fatal("approval persisted despite conflict")
	}
}

func TestProviderPriorStateRequiresExplicitMigration(t *testing.T) {
	c := fixtureConfig(t)
	home := temp(t)
	t.Setenv("HOME", home)
	live := filepath.Join(c.runtime, "generation-test")
	must(t, os.MkdirAll(filepath.Join(live, "first"), 0700))
	must(t, os.Symlink(live, filepath.Join(c.runtime, "skills")))

	link, err := providerLink(c, "codex")
	must(t, err)
	put(t, filepath.Join(link, "external", "SKILL.md"), "keep")
	prior := filepath.Join(filepath.Dir(c.state), "0123456789abcdef", "runtime", "skills", "first")
	must(t, os.Symlink(prior, filepath.Join(link, "first")))

	state, err := providerState(c, "codex")
	must(t, err)
	if state != "MIGRATION_REQUIRED" {
		t.Fatalf("got %s want MIGRATION_REQUIRED", state)
	}
	if exists(providerMarker(c, "codex")) {
		t.Fatal("status implicitly approved provider migration")
	}

	must(t, connect(c, []string{"codex"}))
	target, err := os.Readlink(filepath.Join(link, "first"))
	must(t, err)
	if target != filepath.Join(c.runtime, "skills", "first") {
		t.Fatalf("prior state link not migrated: %s", target)
	}
	if !exists(filepath.Join(link, "external", "SKILL.md")) {
		t.Fatal("explicit migration removed unrelated provider entry")
	}
	state, err = providerState(c, "codex")
	must(t, err)
	if state != "CONNECTED" {
		t.Fatalf("got %s want CONNECTED", state)
	}
}

func TestProviderRejectsLookalikeManagedLink(t *testing.T) {
	c := fixtureConfig(t)
	home := temp(t)
	t.Setenv("HOME", home)
	live := filepath.Join(c.runtime, "generation-test")
	must(t, os.MkdirAll(filepath.Join(live, "first"), 0700))
	must(t, os.Symlink(live, filepath.Join(c.runtime, "skills")))

	link, err := providerLink(c, "codex")
	must(t, err)
	must(t, os.MkdirAll(link, 0700))
	external := filepath.Join(home, "outside", "0123456789abcdef", "runtime", "skills", "first")
	must(t, os.Symlink(external, filepath.Join(link, "first")))

	if err = connect(c, []string{"codex"}); err == nil {
		t.Fatal("lookalike unmanaged link migrated")
	}
	if exists(providerMarker(c, "codex")) {
		t.Fatal("rejected link persisted provider approval")
	}
	target, readErr := os.Readlink(filepath.Join(link, "first"))
	must(t, readErr)
	if target != external {
		t.Fatal("rejected unmanaged link changed")
	}
}
