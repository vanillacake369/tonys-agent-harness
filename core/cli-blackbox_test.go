package core

import (
	"os"
	"os/exec"
	"path/filepath"
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
