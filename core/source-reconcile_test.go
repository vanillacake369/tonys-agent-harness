package core

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

func TestSourcePinAndCollision(t *testing.T) {
	c := fixtureConfig(t)
	fixtureTree(t, c.workspace)
	var s = source{URL: "https://github.com/example/fixture", ID: "fixture",
		Path: "skills/fixture", Revision: strings.Repeat("a", 40)}
	if !s.valid() {
		t.Fatal("valid pin rejected")
	}
	s.Phases = map[string]string{"fixture": "pre"}
	target := filepath.Join(c.workspace, "skill", "skl-pre-fixture-fixture", "SKILL.md")
	put(t, target, "local edit")
	if err := sourceProject(c, c.workspace, "fixture", s); err == nil || !strings.Contains(err.Error(), "collision") {
		t.Fatalf("expected source collision, got %v", err)
	}
	b, err := readRegular(target)
	must(t, err)
	if string(b) != "local edit" {
		t.Fatal("source changed local file")
	}
}

func TestSourceCacheOfflineAndTamper(t *testing.T) {
	c := fixtureConfig(t)
	var s = source{URL: "https://github.com/example/fixture", ID: "fixture", Path: "skills/fixture",
		Revision: strings.Repeat("a", 40)}
	var tree = filepath.Join(c.state, "fixture")
	put(t, filepath.Join(tree, "SKILL.md"), "fixture")
	must(t, sourceCacheSave(c, s, tree))
	var output = filepath.Join(c.state, "output")
	must(t, sourceResolve(c, s, output))
	got, err := readRegular(filepath.Join(output, "SKILL.md"))
	must(t, err)
	if string(got) != "fixture" {
		t.Fatal("cache did not resolve exact content")
	}
	put(t, filepath.Join(sourceCachePath(c, s), "skill/SKILL.md"), "modified")
	if sourceResolve(c, s, filepath.Join(c.state, "unsafe")) == nil {
		t.Fatal("cache tampering accepted")
	}
}

func TestSourceFetchReportsMissingSelectedPath(t *testing.T) {
	c := fixtureConfig(t)
	bin := t.TempDir()
	script := "#!/bin/sh\ncase \" $* \" in\n" +
		" *' rev-parse '*) printf '%s\\n' " + strings.Repeat("a", 40) + ";;\n" +
		" *' archive '*) exit 1;;\nesac\n"
	must(t, os.WriteFile(filepath.Join(bin, "git"), []byte(script), 0700))
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	s := source{URL: "https://github.com/example/fixture", ID: "fixture",
		Path: "skills/fixture", Revision: strings.Repeat("a", 40)}
	err := sourceFetch(c, s, filepath.Join(c.state, "target"))
	if err == nil || !strings.Contains(err.Error(), "selected source path") {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestSourceCollectionProjectsEachSkillAndRejectsCollision(t *testing.T) {
	c := fixtureConfig(t)
	if exec.Command("python3", "-c", "import yaml").Run() != nil {
		t.Skip("missing PyYAML")
	}
	parser, err := os.ReadFile("metadata-validate.py")
	must(t, err)
	put(t, filepath.Join(c.repo, "core/metadata-validate.py"), string(parser))
	s := source{URL: "https://github.com/example/fixture", ID: "fixture", Path: "skills",
		Collection: true, Phases: map[string]string{"first": "pre", "second": "post"},
		Revision: strings.Repeat("a", 40)}
	tree := filepath.Join(c.state, "collection")
	put(t, filepath.Join(tree, "README.md"), "index")
	put(t, filepath.Join(tree, "first", "SKILL.md"),
		"---\nname: 'first' # keep\ndescription: fixture\n---\nname: first\n")
	put(t, filepath.Join(tree, "second", "SKILL.md"), "---\nname: second\ndescription: fixture\n---\nbody\n")
	must(t, sourceCacheSave(c, s, tree))
	root := filepath.Join(c.state, "candidate")
	must(t, os.MkdirAll(filepath.Join(root, "skill"), 0700))
	must(t, sourceProject(c, root, "fixture", s))
	for _, id := range []string{"skl-pre-first-fixture", "skl-post-second-fixture"} {
		doc, err := readRegular(filepath.Join(root, "skill", id, "SKILL.md"))
		must(t, err)
		if !strings.Contains(string(doc), "name: "+id) {
			t.Fatalf("missing imported name %s in %q", id, doc)
		}
	}
	doc, err := readRegular(filepath.Join(root, "skill", "skl-pre-first-fixture", "SKILL.md"))
	must(t, err)
	if string(doc) != "---\nname: skl-pre-first-fixture # keep\ndescription: fixture\n---\nname: first\n" {
		t.Fatalf("unrelated skill content changed: %q", doc)
	}
	raw, err := readRegular(filepath.Join(sourceCachePath(c, s), "skill", "first", "SKILL.md"))
	must(t, err)
	if !strings.Contains(string(raw), "name: 'first' # keep") {
		t.Fatal("import mutated the source cache")
	}
	if sourceProject(c, root, "fixture", s) == nil {
		t.Fatal("collision accepted")
	}
	delete(s.Phases, "first")
	err = sourceProject(c, root, "fixture", s)
	if err == nil || !strings.Contains(err.Error(), "requires an import phase") {
		t.Fatalf("missing import phase accepted: %v", err)
	}
}

func TestSourceSelectedCollectionLimitsArchiveAndSeparatesCache(t *testing.T) {
	c := fixtureConfig(t)
	s := source{URL: "https://github.com/example/fixture", ID: "fixture", Path: "skills",
		Collection: true, SelectByPhase: true, Revision: strings.Repeat("a", 40),
		Phases: map[string]string{"zeta": "post", "alpha": "pre"}}
	if !s.validSelection() || !slices.Equal(s.archivePaths(), []string{"skills/alpha", "skills/zeta"}) {
		t.Fatal("archive must select only configured paths in stable order")
	}
	cache := sourceCachePath(c, s)
	s.Phases["alpha"] = "mid"
	if sourceCachePath(c, s) != cache {
		t.Fatal("phase change must reuse the selected upstream bytes")
	}
	delete(s.Phases, "alpha")
	if sourceCachePath(c, s) == cache {
		t.Fatal("different selected paths reused the same cache")
	}
	s.Phases["../other"] = "pre"
	if s.validSelection() {
		t.Fatal("unsafe selection accepted")
	}
}

func TestSourceCachePruneRetainsPinnedAndPlansBeforeDelete(t *testing.T) {
	c := fixtureConfig(t)
	current := source{URL: "https://github.com/example/current", ID: "current", Path: "skills/current",
		Revision: strings.Repeat("a", 40)}
	stale := source{URL: "https://github.com/example/stale", ID: "stale", Path: "skills/stale",
		Revision: strings.Repeat("b", 40)}
	registry, err := json.Marshal(map[string]source{"current": current})
	must(t, err)
	put(t, filepath.Join(c.repo, "source/registry-sources.json"), string(registry))
	for _, item := range []source{current, stale} {
		tree := filepath.Join(c.state, "fixture-"+item.ID)
		put(t, filepath.Join(tree, "SKILL.md"), item.ID)
		must(t, sourceCacheSave(c, item, tree))
	}

	plan, err := pruneSourceCache(c, true)
	must(t, err)
	if !plan.Plan || plan.Removed != 1 || plan.Bytes == 0 {
		t.Fatalf("unexpected prune plan: %+v", plan)
	}
	if !exists(sourceCachePath(c, current)) || !exists(sourceCachePath(c, stale)) {
		t.Fatal("dry-run changed source caches")
	}

	result, err := pruneSourceCache(c, false)
	must(t, err)
	if result.Plan || result.Removed != 1 || result.Bytes != plan.Bytes {
		t.Fatalf("unexpected prune result: %+v", result)
	}
	if !exists(sourceCachePath(c, current)) || exists(sourceCachePath(c, stale)) {
		t.Fatal("prune did not preserve exactly the pinned cache")
	}
}

func TestSourceCachePruneRejectsUnexpectedEntry(t *testing.T) {
	c := fixtureConfig(t)
	put(t, filepath.Join(c.state, "source-cache/unexpected"), "fixture")
	if _, err := pruneSourceCache(c, false); err == nil {
		t.Fatal("unsafe source cache entry accepted")
	}
	if !exists(filepath.Join(c.state, "source-cache/unexpected")) {
		t.Fatal("rejected cache entry was removed")
	}
}

func TestReviewedSourceDigestControlsOfflineResolution(t *testing.T) {
	// GIVEN a cached source tree and its reviewed digest.
	c := fixtureConfig(t)
	const entry = `{"url":"https://github.com/example/fixture","id":"fixture","path":"skills/fixture",` +
		`"rev":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}`
	var s source
	must(t, json.Unmarshal([]byte(entry), &s))
	tree := filepath.Join(c.state, "fixture")
	put(t, filepath.Join(tree, "SKILL.md"), "fixture")
	must(t, sourceCacheSave(c, s, tree))
	content, err := digest(tree)
	must(t, err)
	reviewed := func(t *testing.T, digest string) source {
		t.Helper()
		var pinned source
		doc := strings.TrimSuffix(entry, "}") + `,"reviewed_tree_sha256":"` + digest + `"}`
		must(t, json.Unmarshal([]byte(doc), &pinned))
		return pinned
	}
	t.Run("matching digest", func(t *testing.T) {
		// GIVEN the pin matches the cached content.
		pin := reviewed(t, content)
		target := filepath.Join(c.state, "offline")

		// WHEN the source is resolved offline.
		err := sourceResolve(c, pin, target)

		// THEN the exact cached skill is returned.
		must(t, err)
		skill, err := readRegular(filepath.Join(target, "SKILL.md"))
		must(t, err)
		if string(skill) != "fixture" {
			t.Fatalf("offline resolution returned %q", skill)
		}
	})

	t.Run("different digest", func(t *testing.T) {
		// GIVEN the reviewed pin describes different content.
		pin := reviewed(t, strings.Repeat("b", 64))
		target := filepath.Join(c.state, "unapproved")

		// WHEN the source is resolved from its cache.
		err := sourceResolve(c, pin, target)

		// THEN the mismatch is rejected before any skill is projected.
		if err == nil || !strings.Contains(err.Error(), "differs from the reviewed digest") || exists(target) {
			t.Fatalf("mismatched source was not rejected cleanly: %v", err)
		}
	})
}

func TestVaultSkillKeepsLocalOriginIntegration(t *testing.T) {
	integrationOnly(t)

	// GIVEN a vault skill has a standalone provenance file.
	c := fixtureConfig(t)
	fixtureTree(t, c.workspace)
	dir := filepath.Join(c.workspace, "skill/local")
	put(t, filepath.Join(dir, "SKILL.md"),
		"---\nname: local\ndescription: Local fixture.\n---\n\n"+
			"```json composition\n{\"requires\":[],\"hints\":[]}\n```\n")
	put(t, filepath.Join(dir, "source-provenance.json"),
		`{"source":"fixture","revision":"old","path":"skill/local","content_sha256":"fixture"}`)

	// WHEN the vault tree is validated.
	nodes, err := validate(c, c.workspace)

	// THEN source identity comes from the validated origin.
	must(t, err)
	if nodes["local"].Origin != "private" || nodes["local"].Provenance != nil {
		t.Fatal("a workspace file changed the validated source identity")
	}
}
