package core

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestPlanDoesNotCommit(t *testing.T) {
	c := fixtureConfig(t)
	fixtureTree(t, c.workspace)
	must(t, recordWorkspaceBase(c))
	before, err := pack(c.workspace)
	must(t, err)
	must(t, reconcile(c, "plan"))
	if exists(c.archive) || exists(filepath.Join(c.runtime, "skills")) {
		t.Fatal("plan committed state")
	}
	after, err := pack(c.workspace)
	must(t, err)
	if !bytes.Equal(before, after) {
		t.Fatal("plan changed workspace")
	}
	if exists(c.runtime) {
		t.Fatal("plan created runtime directory")
	}
}

func TestReconcileRejectsArchiveChangedSinceWorkspaceOpened(t *testing.T) {
	c := fixtureConfig(t)
	fixtureTree(t, c.workspace)
	put(t, c.archive, "archive opened with")
	must(t, recordWorkspaceBase(c))
	put(t, c.archive, "archive pulled from another checkout")
	before, err := pack(c.workspace)
	must(t, err)

	err = reconcile(c, "sync")
	if err == nil || !strings.Contains(err.Error(), "vault changed since workspace opened") {
		t.Fatalf("sync error = %v, want stale workspace rejection", err)
	}
	got, err := pack(c.workspace)
	must(t, err)
	if !bytes.Equal(before, got) {
		t.Fatal("stale workspace was changed")
	}
	archive, err := os.ReadFile(c.archive)
	must(t, err)
	if string(archive) != "archive pulled from another checkout" {
		t.Fatal("pulled archive was overwritten")
	}
	if exists(c.runtime) {
		t.Fatal("stale workspace changed runtime")
	}
}

func TestWorkspaceWithoutBaselineCanAdoptMissingArchive(t *testing.T) {
	c := fixtureConfig(t)
	fixtureTree(t, c.workspace)
	if err := checkWorkspaceBase(c); err != nil {
		t.Fatalf("workspace with no archive could not establish its baseline: %v", err)
	}
	data, err := os.ReadFile(workspaceBasePath(c))
	must(t, err)
	if string(data) != "absent\n" {
		t.Fatalf("workspace baseline = %q, want absent", data)
	}
}

func TestEditWithoutApplyRetainsWorkspace(t *testing.T) {
	c := fixtureConfig(t)
	fixtureTree(t, c.workspace)
	must(t, recordWorkspaceBase(c))
	t.Setenv("VISUAL", "true")
	must(t, editTarget(c, "agent/reviewer", false))
	if !exists(c.workspace) || exists(c.archive) || exists(c.runtime) {
		t.Fatal("edit changed a deployment boundary")
	}
}

func TestSetupExplicitSource(t *testing.T) {
	c := fixtureConfig(t)
	source := filepath.Join(filepath.Dir(c.repo), "manual-source")
	fixtureTree(t, source)
	must(t, initialize(c, []string{"copy", source}))
	before, err := pack(source)
	must(t, err)
	after, err := pack(c.workspace)
	must(t, err)
	if !bytes.Equal(before, after) {
		t.Fatal("explicit initialization lost data")
	}
}

func TestSetupRejectsExistingStateInsteadOfApplying(t *testing.T) {
	c := fixtureConfig(t)
	fixtureTree(t, c.workspace)

	err := setup(c, []string{"empty"})
	if err == nil || !strings.Contains(err.Error(), "already initialized") {
		t.Fatalf("existing state did not require apply: %v", err)
	}
	if !exists(c.workspace) || exists(c.archive) || exists(filepath.Join(c.runtime, "skills")) {
		t.Fatal("rejected init changed managed state")
	}
}

func TestDeploymentReportNamesOutcome(t *testing.T) {
	for _, tc := range []struct {
		name  string
		d     deployment
		drift bool
		want  string
	}{
		{name: "up to date", want: "UP_TO_DATE "},
		{name: "applied", d: deployment{changed: true}, want: "APPLIED "},
		{name: "planned", d: deployment{plan: true}, drift: true, want: "PLANNED "},
	} {
		t.Run(tc.name, func(t *testing.T) {
			var output bytes.Buffer
			must(t, deploymentReportTo(tc.d, tc.drift, changeSet{}, &output))
			if !strings.HasPrefix(output.String(), tc.want) {
				t.Fatalf("got %q want prefix %q", output.String(), tc.want)
			}
		})
	}
}

func TestDeploymentCandidateRunsOneFullValidation(t *testing.T) {
	c := fixtureConfig(t)
	fixtureTree(t, c.workspace)
	put(t, filepath.Join(c.workspace, "skill/fixture/SKILL.md"),
		"# Fixture\n\n```json composition\n{\"requires\":[],\"hints\":[]}\n```\n")
	c.validatorDir = filepath.Join(c.repo, "core")
	put(t, filepath.Join(c.validatorDir, "skill-validate.sh"),
		"#!/bin/sh\nprintf x >> \"$HARNESS_VALIDATOR_LOG\"\n")
	log := filepath.Join(c.state, "validator.log")
	t.Setenv("HARNESS_VALIDATOR_LOG", log)

	must(t, validateStructure(c.workspace))
	_, err := deploymentNodes(c, c.workspace)
	must(t, err)
	data, err := os.ReadFile(log)
	must(t, err)
	if string(data) != "x" {
		t.Fatalf("full validator calls = %d, want 1", len(data))
	}
}

func TestValidateStructureRejectsUnsafeLocalInput(t *testing.T) {
	for _, name := range []string{".env.production", "unexpected.txt"} {
		t.Run(name, func(t *testing.T) {
			c := fixtureConfig(t)
			fixtureTree(t, c.workspace)
			put(t, filepath.Join(c.workspace, name), "fixture")
			if err := validateStructure(c.workspace); err == nil {
				t.Fatalf("unsafe local input %s accepted", name)
			}
		})
	}
}

// 실제 SOPS/age 설치 환경에서 초기화 완료 후 재초기화가 상태를 보존하는지 검증한다.
func TestSetupIntegration(t *testing.T) {
	integrationOnly(t)
	for _, name := range []string{"sops", "age-keygen"} {
		if _, err := exec.LookPath(name); err != nil {
			t.Skip("missing " + name)
		}
	}
	c := fixtureConfig(t)
	must(t, os.Remove(c.key))
	// 키 디렉터리는 사용자 전용이어야 한다.
	c.key = filepath.Join(c.state, "test-keys", "age.key")
	source := filepath.Join(filepath.Dir(c.repo), "main-v13", "capability")
	must(t, os.MkdirAll(filepath.Dir(source), 0700))
	fixtureTree(t, source)
	must(t, setup(c, []string{source}))
	if exists(c.workspace) || !exists(source) {
		t.Fatal("setup left workspace or removed original")
	}
	before, err := readRegular(c.archive)
	must(t, err)
	live, err := livePath(c)
	must(t, err)
	err = setup(c, []string{source})
	if err == nil || !strings.Contains(err.Error(), "already initialized") {
		t.Fatalf("repeated init was not rejected: %v", err)
	}
	after, err := readRegular(c.archive)
	must(t, err)
	again, err := livePath(c)
	must(t, err)
	if !bytes.Equal(before, after) || live != again {
		t.Fatal("repeated setup changed state")
	}
}

func TestSetupEmptyIntegration(t *testing.T) {
	integrationOnly(t)
	if _, err := exec.LookPath("age-keygen"); err != nil {
		t.Skip("missing age-keygen")
	}
	c := fixtureConfig(t)
	must(t, os.Remove(c.key))
	c.key = filepath.Join(c.state, "test-keys", "age.key")
	must(t, setup(c, []string{"empty"}))

	if !exists(c.workspace) {
		t.Fatal("empty setup did not prepare workspace")
	}
	if exists(c.archive) || exists(filepath.Join(c.runtime, "skills")) {
		t.Fatal("empty setup activated persistent state")
	}
}

func TestLockCommitRechecksWorkspaceBase(t *testing.T) {
	c := fixtureConfig(t)
	fixtureTree(t, c.workspace)
	must(t, recordWorkspaceBase(c))
	snapshot, err := pack(c.workspace)
	must(t, err)
	put(t, c.archive, "new archive")
	err = lockCommit(c, c.state, snapshot, snapshot)
	if err == nil || !strings.Contains(err.Error(), "vault changed since workspace opened") {
		t.Fatalf("unexpected commit result: %v", err)
	}
	if !exists(c.workspace) {
		t.Fatal("concurrent change lost the workspace")
	}
}

func TestTwoWorkspacesShareVaultLockIntegration(t *testing.T) {
	integrationOnly(t)
	for _, tool := range []string{"age-keygen", "sops"} {
		if _, err := exec.LookPath(tool); err != nil {
			t.Skip("missing " + tool)
		}
	}
	first, second := fixtureConfig(t), fixtureConfig(t)
	first.key = filepath.Join(filepath.Dir(first.key), "keys", "identity")
	must(t, keyGenerate(first))
	second.archive, second.key = first.archive, first.key
	fixtureTree(t, first.workspace)
	fixtureTree(t, second.workspace)
	must(t, recordWorkspaceBase(first))
	must(t, recordWorkspaceBase(second))
	snapshot, err := pack(second.workspace)
	must(t, err)

	lock, err := vaultOperationLock(first)
	must(t, err)
	err = lockCommit(second, second.state, snapshot, snapshot)
	must(t, lock.Close())
	if err == nil || !strings.Contains(err.Error(), "operation busy") {
		t.Fatalf("concurrent writer was not blocked: %v", err)
	}
	must(t, reconcile(first, "sync"))
	written, err := readRegular(first.archive)
	must(t, err)
	err = lockCommit(second, second.state, snapshot, snapshot)
	if err == nil || !strings.Contains(err.Error(), "vault changed") {
		t.Fatalf("stale second workspace was not rejected: %v", err)
	}
	workspace, err := pack(second.workspace)
	must(t, err)
	cipher, err := readRegular(first.archive)
	must(t, err)
	if !bytes.Equal(snapshot, workspace) || !bytes.Equal(written, cipher) {
		t.Fatal("rejected writer changed workspace or ciphertext")
	}
}
