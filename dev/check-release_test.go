package dev

import (
	"os"
	"strings"
	"testing"
)

func TestReleaseContract(t *testing.T) {
	version, err := os.ReadFile("../cli/version.txt")
	must(t, err)
	if string(version) != "0.0.1\n" {
		t.Fatalf("unexpected release version %q", version)
	}

	flake, err := os.ReadFile("../flake.nix")
	must(t, err)
	var sharedVersion = `nixpkgs.lib.removeSuffix "\n" (builtins.readFile ./cli/version.txt)`
	if !strings.Contains(string(flake), sharedVersion) {
		t.Fatal("flake must read the shared release version")
	}
	if !strings.Contains(string(flake), "application = self.packages.${system}.default;") {
		t.Fatal("flake check must use the application facade name")
	}

	workflow, err := os.ReadFile("../.github/workflows/release.yml")
	must(t, err)
	for _, contract := range []string{"tags:", "v*", "just", "gh release create"} {
		if !strings.Contains(string(workflow), contract) {
			t.Errorf("release workflow missing %q", contract)
		}
	}
	for _, contract := range []string{
		"permissions:\n  contents: read", "publish:\n    needs: build", "permissions:\n      contents: write",
	} {
		if !strings.Contains(string(workflow), contract) {
			t.Errorf("release workflow does not isolate publish permission: missing %q", contract)
		}
	}

	script, err := os.ReadFile("build-release.sh")
	must(t, err)
	var portableChecksums = `(cd dist && sha256sum *.tar.gz >checksums.txt)`
	if !strings.Contains(string(script), portableChecksums) {
		t.Fatal("release checksums must use asset basenames")
	}
}
