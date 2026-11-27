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

	configure := func(t *testing.T) config {
		t.Helper()
		c := fixtureConfig(t)
		t.Setenv("HARNESS_REPO", c.repo)
		t.Setenv("HARNESS_STATE", c.state)
		t.Setenv("HARNESS_VAULT", c.archive)
		t.Setenv("HARNESS_AGE_KEY", c.key)
		return c
	}
	run := func(args ...string) ([]byte, error) {
		return exec.Command(binary, args...).CombinedOutput()
	}

	t.Run("local declarations", func(t *testing.T) {
		// GIVEN a bound workspace with a local declaration and no active runtime.
		c := configure(t)
		must(t, bindState(c))
		fixtureTree(t, c.workspace)

		// WHEN the local graph is requested.
		out, err := run("config", "graph", "--format", "json")

		// THEN only the local declaration is returned.
		if err != nil {
			t.Fatalf("local graph: %v\n%s", err, out)
		}
		var local graphView
		must(t, json.Unmarshal(out, &local))
		if local.Scope != "local_desired" || len(local.Nodes) != 1 || local.Nodes[0].ID != "agent/reviewer" {
			t.Fatalf("unexpected local graph: %s", out)
		}
	})

	t.Run("no active runtime", func(t *testing.T) {
		// GIVEN a fresh state directory without an active runtime.
		c := configure(t)

		// WHEN the active graph is requested.
		out, err := run("graph", "--format", "json")

		// THEN the command reports the missing runtime and leaves state untouched.
		if err == nil || !strings.Contains(string(out), "no active runtime") {
			t.Fatalf("expected no active runtime: %v\n%s", err, out)
		}
		if exists(c.runtime) || exists(filepath.Join(c.state, "operation.lock")) {
			t.Fatal("missing-runtime query wrote state")
		}
	})

	t.Run("reads without a key while another operation holds the lock", func(t *testing.T) {
		// GIVEN an active generation with an external skill and an in-progress operation.
		c := configure(t)
		must(t, privateDir(c.runtime))
		root := c.workspace
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
		t.Cleanup(func() { must(t, lock.Close()) })
		stage := filepath.Join(c.state, "stage-marker")
		put(t, stage, "in-progress fixture")

		// WHEN the runtime graph is queried for consumers of the external skill.
		out, err := run(
			"graph", "skill/imported", "--format", "json", "--reverse", "--relation", "hints", "--depth", "1",
		)

		// THEN the graph keeps the external origin and edge direction, and leaves state untouched.
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
	})

	for _, tc := range []struct{ name, manifest, want string }{
		{
			name: "unsupported schema",
			manifest: `{"schema_version":42,"scope":"bundle",` +
				`"capabilities":{"reviewer":{"kind":"agent"}}}`,
			want: "unsupported runtime graph",
		},
		{
			name: "missing relationship target",
			manifest: `{"schema_version":3,"scope":"bundle",` +
				`"capabilities":{"reviewer":{"kind":"agent","hints":["gone"]}}}`,
			want: "invalid runtime graph",
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			// GIVEN an active generation with an incompatible graph.
			c := configure(t)
			generation := filepath.Join(c.runtime, "generation-fixture")
			put(t, filepath.Join(generation, ".capability-graph.json"), tc.manifest)
			must(t, os.Symlink(generation, filepath.Join(c.runtime, "skills")))

			// WHEN the active graph is requested.
			out, err := run("graph", "--format", "json")

			// THEN the command rejects the graph with the expected diagnostic.
			if err == nil || !strings.Contains(string(out), tc.want) {
				t.Fatalf("expected %q: %v\n%s", tc.want, err, out)
			}
		})
	}
}
