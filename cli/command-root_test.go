package cli

import (
	"errors"
	"testing"
	"tonys-agent-harness/core"

	"github.com/spf13/cobra"
)

func TestVersion(t *testing.T) {
	if buildVersion != "0.0.1" {
		t.Fatalf("got %q want %q", buildVersion, "0.0.1")
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
