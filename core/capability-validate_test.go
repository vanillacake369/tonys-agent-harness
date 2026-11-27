package core

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestNodesReadRunsIndependentValidatorsConcurrently(t *testing.T) {
	// GIVEN four independent skills whose validators wait for another worker.
	c := fixtureConfig(t)
	root := c.workspace
	must(t, emptyTree(root))
	for _, id := range []string{"alpha", "beta", "gamma", "delta"} {
		put(t, filepath.Join(root, "skill", id, "SKILL.md"),
			"# Fixture\n\n```json composition\n{\"requires\":[],\"hints\":[]}\n```\n")
	}
	barrier := filepath.Join(c.state, "validator-barrier")
	must(t, os.Mkdir(barrier, 0700))
	t.Setenv("HARNESS_VALIDATOR_BARRIER", barrier)
	c.validatorDir = filepath.Join(c.repo, "core")
	put(t, filepath.Join(c.validatorDir, "skill-validate.sh"), `#!/bin/sh
set -eu
touch "$HARNESS_VALIDATOR_BARRIER/$(basename "$1")"
attempt=0
while [ "$attempt" -lt 100 ]; do
  count=$(find "$HARNESS_VALIDATOR_BARRIER" -type f | wc -l | tr -d ' ')
  [ "$count" -ge 2 ] && exit 0
  attempt=$((attempt + 1))
  sleep 0.01
done
exit 1
`)

	// WHEN the bundle is validated.
	nodes, err := nodesRead(c, root)

	// THEN all validators complete with their peers.
	must(t, err)
	if len(nodes) != 4 {
		t.Fatalf("got %d nodes want 4", len(nodes))
	}
}

func TestNodesReadReturnsFirstEnumeratedError(t *testing.T) {
	c := fixtureConfig(t)
	root := c.workspace
	must(t, emptyTree(root))
	must(t, os.Mkdir(filepath.Join(root, "skill", "alpha"), 0700))
	must(t, os.Mkdir(filepath.Join(root, "skill", "beta"), 0700))

	_, err := nodesRead(c, root)
	if err == nil || !strings.Contains(err.Error(), "alpha") {
		t.Fatalf("got %v want first enumerated alpha error", err)
	}
}

// 공개 검증기 실행은 Nix 환경에서만 가능할 수 있다.
func TestSkillValidatorIntegration(t *testing.T) {
	integrationOnly(t)
	for _, name := range []string{"bash", "jq", "python3"} {
		if _, err := exec.LookPath(name); err != nil {
			t.Skip("missing " + name)
		}
	}
	if exec.Command("python3", "-c", "import yaml").Run() != nil {
		t.Skip("missing PyYAML")
	}
	c := fixtureConfig(t)
	script, err := os.ReadFile("skill-validate.sh")
	must(t, err)
	put(t, filepath.Join(c.repo, "core/skill-validate.sh"), string(script))
	parser, err := os.ReadFile("metadata-validate.py")
	must(t, err)
	put(t, filepath.Join(c.repo, "core/metadata-validate.py"), string(parser))
	fixtureTree(t, c.workspace)
	path := filepath.Join(c.workspace, "skill/fixture/SKILL.md")
	put(t, path, "---\nname: fixture\ndescription: Fixture only.\n---\n\nBody\n\n"+
		"```json composition\n{\"requires\":[],\"hints\":[]}\n```\n")
	_, err = validate(c, c.workspace)
	must(t, err)
	put(t, path, "---\nname: wrong\ndescription: Fixture only.\n---\n\nBody\n")
	if _, err = validate(c, c.workspace); err == nil {
		t.Fatal("invalid skill accepted")
	}
}

func TestDAGProjectsStageCapabilitiesIntegration(t *testing.T) {
	integrationOnly(t)

	// GIVEN a review DAG and a locally declared evidence tool.
	c := fixtureConfig(t)
	root := c.workspace
	must(t, emptyTree(root))
	fixture := "../tests/fixtures/review/capability"
	dir := filepath.Join(root, "dag/dag-review")
	must(t, copyTree(filepath.Join(fixture, "dag/dag-review"), dir))
	must(t, copyTree(filepath.Join(fixture, "skill/skill-review-evidence"),
		filepath.Join(root, "skill/skill-review-evidence")))
	skill := filepath.Join(root, "skill/skill-review-evidence/SKILL.md")
	skillDoc, err := os.ReadFile(skill)
	must(t, err)
	put(t, skill, strings.ReplaceAll(string(skillDoc), "tool-git-evidence", "evidence"))
	put(t, filepath.Join(c.repo, "contract/local-access.json"),
		`{"schema_version":1,"tools":{"evidence":{"method":"cli","availability":"Requires Git."}}}`)
	put(t, filepath.Join(root, "tool/evidence/SKILL.md"),
		"---\nname: evidence\ndescription: Synthetic evidence tool.\n---\n\nEvidence.\n")
	must(t, os.Remove(filepath.Join(dir, "dag-contract.schema.json")))
	path := filepath.Join(dir, "DAG.yaml")
	body, err := os.ReadFile(path)
	must(t, err)
	for _, tc := range []struct {
		name, tool string
		wantError  bool
	}{
		{name: "declared tool", tool: "evidence"},
		{name: "missing tool", tool: "missing-tool", wantError: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			// GIVEN a DAG stage referencing the selected tool.
			doc := strings.Replace(string(body), "  - id: experiment\n",
				"  - id: experiment\n    capabilities: ["+tc.tool+"]\n", 1)
			put(t, path, doc)

			// WHEN the bundle is validated.
			nodes, err := validate(c, root)

			// THEN a missing reference is rejected and a declared tool appears in the graph.
			if tc.wantError {
				if err == nil || !strings.Contains(err.Error(), "invalid capability relation") {
					t.Fatalf("expected dangling stage Capability to be rejected: %v", err)
				}
				return
			}
			must(t, err)
			if strings.Join(nodes["dag-review"].Hints, ",") != "evidence" {
				t.Fatalf("missing stage-to-tool graph edge: %+v", nodes["dag-review"])
			}
			if nodes["evidence"].Execution == nil || nodes["evidence"].Execution.Method != "cli" {
				t.Fatal("tool execution method is missing from the graph")
			}
		})
	}
}
