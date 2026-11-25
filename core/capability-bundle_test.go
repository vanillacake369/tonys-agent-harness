package core

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// 실제 개인 Bundle은 외부 경로에서만 읽는다. 공개 fixture나 Nix에 복제하지 않는다.
func TestCapabilityBundleV21(t *testing.T) {
	var input = os.Getenv("HARNESS_TEST_BUNDLE")
	if input == "" {
		t.Skip("set HARNESS_TEST_BUNDLE to an external v2.1 directory")
	}
	c := fixtureConfig(t)
	for _, name := range []string{"skill-validate.sh", "dag-validate.sh", "tool-contract-validate.sh",
		"metadata-validate.py"} {
		data, err := os.ReadFile(name)
		must(t, err)
		put(t, filepath.Join(c.repo, "core", name), string(data))
	}
	for _, name := range []string{"git-evidence.json", "git-evidence.schema.json"} {
		data, err := os.ReadFile(filepath.Join("../contract", name))
		must(t, err)
		put(t, filepath.Join(c.repo, "contract", name), string(data))
	}
	var stage = filepath.Join(c.state, "stage-bundle")
	must(t, os.Mkdir(stage, 0700))
	var root = filepath.Join(stage, "capability")
	must(t, copyTree(input, root))
	nodes, err := validate(c, root)
	must(t, err)
	must(t, catalogValidate(c, root))
	if len(nodes) != 48 {
		t.Fatalf("expected 48 nodes, got %d", len(nodes))
	}
	var target = filepath.Join(stage, "bundle")
	must(t, runtimeBuild(c, root, target, nodes))
	ids, err := providerIDs(target)
	must(t, err)
	if len(ids) != 48 {
		t.Fatalf("expected 48 discovery entries, got %d", len(ids))
	}
	profile, err := readRegular(filepath.Join(target, "agent-supervisor/SKILL.md"))
	must(t, err)
	if !strings.Contains(string(profile), "not a native subagent") {
		t.Fatal("role projection incorrectly classified")
	}
	if !exists(filepath.Join(target, ".capability/POLICY.md")) {
		t.Fatal("policy not projected")
	}
}
