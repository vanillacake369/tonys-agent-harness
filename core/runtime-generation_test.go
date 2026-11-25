package core

import (
	"os"
	"path/filepath"
	"testing"
)

func TestRuntimeActivation(t *testing.T) {
	c := fixtureConfig(t)
	must(t, privateDir(c.runtime))
	root := filepath.Join(c.state, "stage-1/capability")
	must(t, os.MkdirAll(filepath.Dir(root), 0700))
	fixtureTree(t, root)
	nodes, err := validate(c, root)
	must(t, err)
	first := filepath.Join(c.state, "stage-1/bundle")
	must(t, runtimeBuild(c, root, first, nodes))
	must(t, runtimeActivate(c, first))
	old, err := livePath(c)
	must(t, err)
	second := filepath.Join(c.state, "stage-1/second")
	must(t, runtimeBuild(c, root, second, nodes))
	changes, err := runtimeDiff(old, second)
	must(t, err)
	if changes.Added != 0 || changes.Removed != 0 || changes.Modified != 0 || len(changes.Details) != 0 {
		t.Fatal("unexpected drift")
	}
	must(t, runtimeActivate(c, second))
	live, err := livePath(c)
	must(t, err)
	if live == old || exists(old) {
		t.Fatal("stale generation retained")
	}
	must(t, purge(c))
	if exists(live) {
		t.Fatal("purge retained plaintext")
	}
}

func TestRuntimeBuildUsesCapabilityKind(t *testing.T) {
	c := fixtureConfig(t)
	root := filepath.Join(c.state, "stage/capability")
	must(t, os.MkdirAll(filepath.Dir(root), 0700))
	must(t, emptyTree(root))
	put(t, filepath.Join(root, "agent/reviewer.md"), "agent fixture")
	put(t, filepath.Join(root, "skill/review-agent/SKILL.md"), "skill fixture")

	target := filepath.Join(c.state, "stage/bundle")
	nodes := map[string]node{
		"review-agent": {Kind: "skill", Path: "capability/agent/review-agent/SKILL.md"},
		"reviewer":     {Kind: "agent", Path: "capability/agent/reviewer.md"},
	}
	must(t, runtimeBuild(c, root, target, nodes))

	if !exists(filepath.Join(target, "review-agent/SKILL.md")) {
		t.Fatal("skill was not projected from its capability kind")
	}
	if exists(filepath.Join(target, "reviewer.md")) {
		t.Fatal("agent document was projected into runtime")
	}
}

func TestPurgeDanglingGeneration(t *testing.T) {
	c := fixtureConfig(t)
	must(t, privateDir(c.runtime))
	link := filepath.Join(c.runtime, "skills")
	must(t, os.Symlink(filepath.Join(c.runtime, "generation-missing"), link))
	must(t, purge(c))
	if exists(link) {
		t.Fatal("purge retained dangling managed link")
	}
}

// 활성 링크 교체가 차단되면 기존 Runtime과 링크를 유지한다.
// 활성화에 실패한 후보 generation은 제거되어야 한다.
func TestActivationFailurePreservesLive(t *testing.T) {
	c := fixtureConfig(t)
	must(t, privateDir(c.runtime))
	old := filepath.Join(c.runtime, "generation-old")
	must(t, os.Mkdir(old, 0700))
	must(t, os.Symlink(old, filepath.Join(c.runtime, "skills")))
	put(t, filepath.Join(c.runtime, ".next"), "existing")
	candidate := filepath.Join(c.state, "candidate")
	must(t, os.Mkdir(candidate, 0700))
	if runtimeActivate(c, candidate) == nil {
		t.Fatal("stale activation was accepted")
	}
	live, err := livePath(c)
	must(t, err)
	if live != old {
		t.Fatal("active runtime changed")
	}
	generations, err := filepath.Glob(filepath.Join(c.runtime, "generation-*"))
	must(t, err)
	if len(generations) != 1 || generations[0] != old {
		t.Fatal("failed generation retained")
	}
}
