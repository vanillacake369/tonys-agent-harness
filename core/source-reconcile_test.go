package core

import (
	"encoding/json"
	"os"
	"path/filepath"
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
	target := filepath.Join(c.workspace, "skill", s.ID, "SKILL.md")
	put(t, target, "local edit")
	if sourceProject(c, c.workspace, "fixture", s) == nil {
		t.Fatal("source collision accepted")
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
	s := source{URL: "https://github.com/example/fixture", ID: "fixture", Path: "skills",
		Collection: true, Revision: strings.Repeat("a", 40)}
	tree := filepath.Join(c.state, "collection")
	put(t, filepath.Join(tree, "README.md"), "index")
	put(t, filepath.Join(tree, "first", "SKILL.md"), "first")
	put(t, filepath.Join(tree, "second", "SKILL.md"), "second")
	must(t, sourceCacheSave(c, s, tree))
	root := filepath.Join(c.state, "candidate")
	must(t, os.MkdirAll(filepath.Join(root, "skill"), 0700))
	must(t, sourceProject(c, root, "fixture", s))
	for _, name := range []string{"first", "second"} {
		if !exists(filepath.Join(root, "skill", name, "SKILL.md")) {
			t.Fatal("missing skill", name)
		}
	}
	if sourceProject(c, root, "fixture", s) == nil {
		t.Fatal("collision accepted")
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
