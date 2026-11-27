package core

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/rogpeppe/go-internal/testscript"
)

func TestCoreCLIScenario(t *testing.T) {
	if testing.Short() {
		t.Skip("scenario test")
	}
	binary := coreScenarioBinary(t)
	testscript.Run(t, testscript.Params{
		Files:               []string{"scenario-status.txtar"},
		RequireExplicitExec: true,
		RequireUniqueNames:  true,
		Setup: func(env *testscript.Env) error {
			env.Setenv("HARNESS_BIN", binary)
			env.Setenv("HARNESS_REPO", filepath.Join(env.WorkDir, "repo"))
			env.Setenv("HARNESS_STATE", filepath.Join(env.WorkDir, "state"))
			env.Setenv("HARNESS_VAULT", filepath.Join(env.WorkDir, "vault", "capability.enc"))
			env.Setenv("HARNESS_AGE_KEY", filepath.Join(env.WorkDir, "config", "age.key"))
			env.Setenv("HOME", filepath.Join(env.WorkDir, "home"))
			return nil
		},
	})
}

func coreScenarioBinary(t *testing.T) string {
	t.Helper()
	if binary := os.Getenv("HARNESS_CORE_BIN"); binary != "" {
		path, err := filepath.Abs(binary)
		must(t, err)
		return path
	}
	binary := filepath.Join(t.TempDir(), "harness")
	cmd := exec.Command("go", "build", "-mod=readonly", "-o", binary, "..")
	cmd.Env = append(os.Environ(), "GOTOOLCHAIN=local")
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("build scenario binary: %v\n%s", err, out)
	}
	return binary
}

func TestRuntimeGraphCLI(t *testing.T) {
	integrationOnly(t)
	binary := coreScenarioBinary(t)
	c := fixtureConfig(t)
	t.Setenv("HARNESS_REPO", c.repo)
	t.Setenv("HARNESS_STATE", c.state)
	t.Setenv("HARNESS_VAULT", c.archive)
	t.Setenv("HARNESS_AGE_KEY", c.key)
	run := func(args ...string) ([]byte, error) {
		t.Helper()
		return exec.Command(binary, append([]string{"config", "graph"}, args...)...).CombinedOutput()
	}
	args := []string{"--scope", "runtime", "--format", "json"}
	assertError := func(want string) {
		t.Helper()
		out, err := run(args...)
		if err == nil || !strings.Contains(string(out), want) {
			t.Fatalf("expected %q: %v\n%s", want, err, out)
		}
	}
	assertError("no active runtime")
	if exists(c.runtime) || exists(filepath.Join(c.state, "operation.lock")) {
		t.Fatal("missing-runtime query wrote state")
	}
	must(t, privateDir(c.runtime))
	root := filepath.Join(c.state, "capability")
	fixtureTree(t, root)
	put(t, filepath.Join(root, "skill/imported/SKILL.md"), "external skill fixture")
	nodes := map[string]node{
		"reviewer": {Kind: "agent", Hints: []string{"imported"}},
		"imported": {Kind: "skill", Origin: "external"},
	}
	bundle := filepath.Join(c.state, "bundle")
	must(t, runtimeBuild(c, root, bundle, nodes))
	must(t, runtimeActivate(c, bundle))
	must(t, os.Remove(c.key))
	lock, err := operationLock(c)
	must(t, err)
	defer lock.Close()
	stage := filepath.Join(c.state, "stage-marker")
	put(t, stage, "in-progress fixture")
	out, err := run(append(args, "skill/imported", "--reverse", "--relation", "hints", "--depth", "1")...)
	if err != nil {
		t.Fatalf("runtime graph: %v\n%s", err, out)
	}
	var graph struct {
		Scope string
		Nodes []struct{ ID, Origin string }
		Edges []graphEdge
	}
	must(t, json.Unmarshal(out, &graph))
	if graph.Scope != "active_runtime" || len(graph.Nodes) != 2 || len(graph.Edges) != 1 {
		t.Fatalf("unexpected runtime graph: %s", out)
	}
	if graph.Nodes[0].ID != "skill/imported" || graph.Nodes[0].Origin != "external" {
		t.Fatalf("external node missing from runtime graph: %s", out)
	}
	if graph.Edges[0].From != "agent/reviewer" || graph.Edges[0].To != "skill/imported" {
		t.Fatalf("reverse query changed the edge direction: %s", out)
	}
	if !exists(stage) || exists(c.archive) || exists(filepath.Join(c.state, "binding")) {
		t.Fatal("runtime query changed local state")
	}

	live, err := livePath(c)
	must(t, err)
	manifest := filepath.Join(live, ".capability-graph.json")
	put(t, manifest, `{"schema_version":42,"scope":"bundle","capabilities":{"reviewer":{"kind":"agent"}}}`)
	assertError("unsupported runtime graph")
	put(t, manifest, `{"schema_version":3,"scope":"bundle",`+
		`"capabilities":{"reviewer":{"kind":"agent","hints":["gone"]}}}`)
	assertError("invalid runtime graph")
}
