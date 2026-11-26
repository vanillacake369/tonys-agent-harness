package cli

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"tonys-agent-harness/core"

	"github.com/spf13/cobra"
)

func TestVersion(t *testing.T) {
	version, err := os.ReadFile("version.txt")
	if err != nil {
		t.Fatal(err)
	}
	if want := strings.TrimSpace(string(version)); buildVersion != want {
		t.Fatalf("got %q want %q", buildVersion, want)
	}
}

func TestCommandExitCodes(t *testing.T) {
	for _, tc := range []struct {
		args []string
		want int
	}{
		{[]string{"--help"}, 0}, {[]string{"missing"}, 2},
		{[]string{"fixture", "extra"}, 2}, {[]string{"fixture"}, 1},
	} {
		var cmd = &cobra.Command{Use: "fixture", Args: cobra.NoArgs,
			RunE: func(_ *cobra.Command, _ []string) error { return errors.New("fixture failure") }}
		code, _ := Run(core.NewApplication(), []*cobra.Command{cmd}, tc.args)
		if code != tc.want {
			t.Fatalf("args %v: got %d want %d", tc.args, code, tc.want)
		}
	}
}

func TestCompletionInstallsForShell(t *testing.T) {
	root := t.TempDir()
	t.Setenv("HOME", root)
	t.Setenv("XDG_CONFIG_HOME", filepath.Join(root, "config"))
	t.Setenv("ZDOTDIR", filepath.Join(root, "zsh"))
	for _, tc := range []struct {
		shell, script, startup string
	}{
		{"bash", "config/tonys-agent-harness/completion.bash", ".bashrc"},
		{"zsh", "config/tonys-agent-harness/completion.zsh", "zsh/.zshrc"},
		{"fish", "config/fish/completions/harness.fish", ""},
	} {
		t.Run(tc.shell, func(t *testing.T) {
			t.Setenv("SHELL", "/bin/"+tc.shell)
			for range 2 {
				if code, err := Run(core.NewApplication(), nil, []string{"completion"}); code != 0 || err != nil {
					t.Fatalf("completion failed: %d %v", code, err)
				}
			}
			script, err := os.ReadFile(filepath.Join(root, tc.script))
			if err != nil || !strings.Contains(string(script), "harness") {
				t.Fatalf("generated completion missing: %v", err)
			}
			if tc.startup != "" {
				startup, err := os.ReadFile(filepath.Join(root, tc.startup))
				if err != nil || strings.Count(string(startup), "# harness shell completion") != 1 {
					t.Fatalf("expected exactly one startup entry: %v", err)
				}
			}
		})
	}
}
