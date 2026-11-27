package core

import "testing"

func TestLifecycleGuidance(t *testing.T) {
	for _, tc := range []struct {
		name             string
		state            StatusReport
		runtimeDirectory bool
		want             string
	}{
		{"new", StatusReport{}, false, "harness config init PATH or empty"},
		{"lost vault", StatusReport{RuntimeExists: true}, true, "restore the existing encrypted Vault"},
		{"missing key", StatusReport{ArchiveExists: true}, false, "restore the age key for this Vault"},
		{"restore", StatusReport{ArchiveExists: true, KeyExists: true}, false, "harness apply"},
		{"editing", StatusReport{ArchiveExists: true, KeyExists: true, WorkspaceExists: true}, true,
			"harness apply --dry-run"},
		{"connected", StatusReport{ArchiveExists: true, KeyExists: true, RuntimeExists: true,
			Providers: []ProviderStatus{{Name: "codex", State: "CONNECTED"}}}, true, ""},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if got := statusNext(tc.state, tc.runtimeDirectory, "codex"); got != tc.want {
				t.Fatalf("guidance = %q, want %q", got, tc.want)
			}
		})
	}
}
