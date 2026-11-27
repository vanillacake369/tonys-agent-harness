package core

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
)

/*
최초 설치만 명시적인 원본으로 수행한다.
기존 원본과 키는 덮어쓰지 않으며 이미 초기화된 상태를 apply로 암묵 변환하지 않는다.
*/
func setup(c config, args []string) error {
	if len(args) != 1 {
		return errors.New("usage: harness config init SOURCE|empty")
	}
	var alreadyInitialized = exists(c.archive) || exists(c.workspace)
	if alreadyInitialized {
		return errors.New("already initialized; run harness apply")
	}
	parent, err := filepath.EvalSymlinks(filepath.Dir(c.archive))
	if err != nil || parent != filepath.Dir(c.archive) {
		return errors.New("vault parent missing or unsafe; choose an existing approved HARNESS_VAULT directory")
	}
	if exists(filepath.Join(c.repo, "capability")) || exists(filepath.Join(c.repo, ".runtime")) {
		return errors.New("legacy plaintext; move outside checkout manually")
	}
	var isEmptySetup = len(args) == 1 && args[0] == "empty"
	if exists(c.runtime) {
		return errors.New("vault missing from initialized state; restore ciphertext instead of reinitializing")
	}
	if err = setupInitialize(c, args); err != nil {
		return err
	}
	if isEmptySetup {
		fmt.Println("EDIT:", c.workspace)
		fmt.Println("PENDING: add a valid capability, then run harness apply")
		return nil
	}
	if err = reconcile(c, "sync"); err != nil {
		return err
	}
	fmt.Println("READY: harness edit; harness apply")
	return status(c)
}

// 최초 설정은 명시적인 디렉터리 또는 empty만 받는다.
func setupInitialize(c config, args []string) error {
	if len(args) != 1 {
		return errors.New("run harness config init PATH or harness config init empty")
	}
	var input = []string{"init"}
	if args[0] != "empty" {
		var from, err = filepath.Abs(args[0])
		if err != nil {
			return err
		}
		input = []string{"copy", from}
	}
	if err := keyGenerate(c); err != nil {
		return err
	}
	return initialize(c, input)
}

// 초기화는 명시적으로 요청해야 한다. 기존 암호문 누락을 초기화로 해석하지 않는다.
func initialize(c config, args []string) (resultErr error) {
	if exists(c.archive) || exists(c.workspace) {
		return errors.New("existing source; refusing initialization")
	}
	if err := keyValidate(c); err != nil {
		return err
	}
	stage, err := stageCreate(c)
	if err != nil {
		return err
	}
	defer cleanupPath(&resultErr, stage)
	root := filepath.Join(stage, "capability")
	if args[0] == "init" {
		if len(args) != 1 {
			return errors.New("unexpected args")
		}
		if err = emptyTree(root); err != nil {
			return err
		}
	} else if err = migrateTree(c, root, args); err != nil {
		return err
	}
	if err = os.Rename(root, c.workspace); err != nil {
		return err
	}
	return writeWorkspaceBase(c, "absent")
}

func emptyTree(root string) error {
	if err := os.Mkdir(root, 0700); err != nil {
		return err
	}
	for _, kind := range []string{"agent", "dag", "skill", "tool"} {
		if err := os.Mkdir(filepath.Join(root, kind), 0700); err != nil {
			return err
		}
	}
	return nil
}

// 최초 설치에서만 명시적 외부 디렉터리를 복사한다.
func migrateTree(c config, root string, args []string) error {
	if len(args) != 2 || args[0] != "copy" {
		return errors.New("explicit source directory required")
	}
	var from = args[1]
	if !filepath.IsAbs(from) || inside(c.repo, from) || inside(c.state, from) {
		return errors.New("unsafe source path")
	}
	var real, err = filepath.EvalSymlinks(from)
	if err != nil {
		return err
	}
	if real != from {
		return errors.New("symlink source")
	}
	return copyTree(from, root)
}

func stageCreate(c config) (string, error) {
	// 이전 비정상 종료의 평문 후보는 작업 잠금 안에서 제거한다.
	if err := stageCleanup(c); err != nil {
		return "", err
	}
	return os.MkdirTemp(c.state, "stage-")
}

func stageCleanup(c config) error {
	entries, err := filepath.Glob(filepath.Join(c.state, "stage-*"))
	if err != nil {
		return err
	}
	for _, p := range entries {
		if err = os.RemoveAll(p); err != nil {
			return err
		}
	}
	return nil
}

func materialize(c config, root string) ([]byte, error) {
	if exists(c.workspace) {
		if err := privateDir(c.workspace); err != nil {
			return nil, err
		}
		if err := copyTree(c.workspace, root); err != nil {
			return nil, err
		}
		return pack(root)
	}
	if err := os.Mkdir(root, 0700); err != nil {
		return nil, err
	}
	if err := decrypt(c, root); err != nil {
		return nil, err
	}
	return pack(root)
}

/*
lock과 sync는 동일한 검증 경로를 사용한다.
plan은 영속 원본을 변경하지 않으며 임시 평문 정리 실패도 보고한다.
*/
func reconcile(c config, cmd string) error {
	return reconcileFormat(c, cmd, false)
}

func reconcileFormat(c config, cmd string, jsonOutput bool) error {
	return reconcileWithOptions(c, cmd, jsonOutput, false, false)
}

func reconcileWithOptions(c config, cmd string, jsonOutput, quiet, verbose bool) (resultErr error) {
	if cmd != "plan" && cmd != "sync" && cmd != "lock" && cmd != "unlock" {
		return errors.New("unknown command")
	}
	if !exists(c.archive) && !exists(c.workspace) {
		return errors.New("no capability initialized; run harness config init or restore missing vault")
	}
	if err := keyValidate(c); err != nil {
		return err
	}
	if cmd == "unlock" && exists(c.workspace) {
		if _, err := checkWorkspaceBase(c); err != nil {
			return err
		}
		if !quiet {
			fmt.Println("EDIT:", c.workspace)
		}
		return nil
	}
	if cmd == "lock" && !exists(c.workspace) {
		if !exists(c.archive) {
			return errors.New("missing source")
		}
		return nil
	}
	var editing = exists(c.workspace)
	var archiveBase string
	if editing {
		if _, err := checkWorkspaceBase(c); err != nil {
			return err
		}
	} else {
		var err error
		archiveBase, err = currentArchiveFingerprint(c)
		if err != nil {
			return err
		}
	}
	stage, err := stageCreate(c)
	if err != nil {
		return err
	}
	defer cleanupPath(&resultErr, stage)
	if err = prepareValidators(&c, stage); err != nil {
		return err
	}
	root := filepath.Join(stage, "capability")
	before, err := materialize(c, root)
	if err != nil {
		return err
	}
	var validatesFullTree = cmd == "unlock" || cmd == "lock"
	if validatesFullTree {
		if _, err = validate(c, root); err != nil {
			return err
		}
	} else if err = validateStructure(root); err != nil {
		return err
	}
	if cmd != "unlock" {
		if err = catalogValidate(c, root); err != nil {
			return err
		}
	}
	if cmd == "unlock" {
		if err = verifyArchiveFingerprint(c, archiveBase); err != nil {
			return err
		}
		if err = os.Rename(root, c.workspace); err != nil {
			return err
		}
		if err = writeWorkspaceBase(c, archiveBase); err != nil {
			return err
		}
		if !quiet {
			fmt.Println("EDIT:", c.workspace)
		}
		return nil
	}
	after, err := pack(root)
	if err != nil {
		return err
	}
	if cmd == "lock" {
		return lockCommit(c, stage, before, after)
	}
	changed := !bytes.Equal(before, after)
	if editing {
		changed, err = archiveChanged(c, filepath.Join(stage, "compare"), after)
		if err != nil {
			return err
		}
	}
	nodes, err := deploymentNodes(c, root)
	if err != nil {
		return err
	}
	return deploy(c, deployment{
		stage: stage, root: root, nodes: nodes, plain: after, before: before,
		changed: changed, plan: cmd == "plan", editing: editing, jsonOutput: jsonOutput, verbose: verbose,
		archiveBase: archiveBase,
	})
}

// Source를 임시 후보에 투영한 뒤 최종 그래프와 모든 계약을 한 번 검증한다.
func deploymentNodes(c config, root string) (map[string]node, error) {
	c.imports = make(map[string]provenance)
	if err := sourcesProject(c, root); err != nil {
		return nil, err
	}
	return validate(c, root)
}

/*
편집본의 변경 여부를 확인하고 왕복 검증된 암호문을 먼저 저장한다.
저장 전후 편집본이 달라졌다면 원본을 삭제하지 않는다.
*/
func lockCommit(c config, stage string, before, after []byte) (resultErr error) {
	lock, err := vaultOperationLock(c)
	if err != nil {
		return err
	}
	defer func() { resultErr = errors.Join(resultErr, lock.Close()) }()
	baseline, err := checkWorkspaceBase(c)
	if err != nil {
		return err
	}
	current, err := pack(c.workspace)
	if err != nil {
		return err
	}
	if !bytes.Equal(before, current) {
		return errors.New("workspace changed; retry after closing editor")
	}
	changed, err := archiveChanged(c, filepath.Join(stage, "previous"), after)
	if err != nil {
		return err
	}
	if changed {
		err = seal(c, after, baseline)
	} else {
		err = verifyArchiveFingerprint(c, baseline)
	}
	if err != nil {
		return err
	}
	current, err = pack(c.workspace)
	if err != nil {
		return err
	}
	if !bytes.Equal(before, current) {
		return errors.New("workspace changed during commit; original retained")
	}
	if err = os.RemoveAll(c.workspace); err != nil {
		return err
	}
	return os.Remove(workspaceBasePath(c))
}

type deployment struct {
	stage, root, archiveBase                    string
	nodes                                       map[string]node
	plain, before                               []byte
	changed, plan, editing, jsonOutput, verbose bool
	providersChanged                            bool
}

func archiveChanged(c config, path string, after []byte) (bool, error) {
	if !exists(c.archive) {
		return true, nil
	}
	if err := os.Mkdir(path, 0700); err != nil {
		return false, err
	}
	if err := decrypt(c, path); err != nil {
		return false, err
	}
	before, err := pack(path)
	return !bytes.Equal(before, after), err
}

func deploy(c config, d deployment) error {
	if err := existingPrivateDir(c.runtime); err != nil {
		return err
	}
	live, err := livePath(c)
	if err != nil {
		return err
	}
	target := filepath.Join(d.stage, "bundle")
	if err = runtimeBuild(c, d.root, target, d.nodes); err != nil {
		return err
	}
	desired, err := digest(target)
	if err != nil {
		return err
	}
	actual := ""
	if live != "" {
		actual, err = digest(live)
		if err != nil {
			return err
		}
	}
	drift := desired != actual
	changes, err := runtimeDiff(live, target)
	if err != nil {
		return err
	}
	links, err := providerPreflight(c, target)
	if err != nil {
		return err
	}
	d.providersChanged, err = providerChanges(c, links, target)
	if err != nil {
		return err
	}
	if d.plan {
		return deploymentReport(d, drift, changes)
	}
	if err = privateDir(c.runtime); err != nil {
		return err
	}
	if err = commitDeployment(c, d); err != nil {
		return err
	}
	if drift {
		err = runtimeActivate(c, target)
	} else {
		err = runtimeCleanup(c, live)
	}
	if err != nil {
		return fmt.Errorf("vault commit completed; runtime activation or cleanup incomplete: %w", err)
	}
	if err = providerReconcile(c, links); err != nil {
		return fmt.Errorf("runtime committed; provider reconciliation incomplete: %w", err)
	}
	return deploymentReport(d, drift, changes)
}

// apply는 열린 편집본도 명시적으로 저장하고 배포한다.
// Runtime 후보 검증 후에만 암호문을 교체한다.
func commitDeployment(c config, d deployment) (resultErr error) {
	if d.editing {
		return lockCommit(c, d.stage, d.before, d.plain)
	}
	if !d.changed {
		return nil
	}
	lock, err := vaultOperationLock(c)
	if err != nil {
		return err
	}
	defer func() { resultErr = errors.Join(resultErr, lock.Close()) }()
	return seal(c, d.plain, d.archiveBase)
}

// 편집기를 정상 종료한 경우에만 저장과 배포를 진행한다.
// 편집기가 실패하면 복호화된 원본을 유지하여 사용자의 변경을 보호한다.
func edit(c config) error { return editTarget(c, "", true) }

func editTarget(c config, target string, apply bool) error {
	path, err := editorExecutable()
	if err != nil {
		return err
	}
	if err = reconcile(c, "unlock"); err != nil {
		return err
	}
	selected, err := editorTarget(c, target)
	if err != nil {
		return err
	}
	if selected == "" {
		return nil
	}
	cmd := exec.Command(path, selected)
	cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stdout, os.Stderr
	if err = cmd.Run(); err != nil {
		return errors.New("editor failed; workspace retained; run harness edit or harness apply")
	}
	if !apply {
		return nil
	}
	return reconcile(c, "sync")
}

func deploymentReport(d deployment, drift bool, changes changeSet) error {
	return deploymentReportTo(d, drift, changes, os.Stdout)
}

func deploymentReportTo(d deployment, drift bool, changes changeSet, output io.Writer) error {
	var outcome = "UP_TO_DATE"
	if d.plan {
		outcome = "PLANNED"
	} else if d.changed || drift || d.providersChanged {
		outcome = "APPLIED"
	}
	if !d.jsonOutput {
		fmt.Fprintf(output, "%s source_changed=%t runtime_changed=%t added=%d removed=%d modified=%d\n", outcome,
			d.changed, drift, changes.Added, changes.Removed, changes.Modified)
		fmt.Fprintf(output, "providers_changed=%t\n", d.providersChanged)
	}
	if d.verbose && !d.jsonOutput {
		for _, item := range changes.Details {
			fmt.Fprintf(output, "%s %s\n", item.Action, item.ID)
		}
	}

	if !d.jsonOutput {
		return nil
	}
	return json.NewEncoder(output).Encode(map[string]any{
		"schema_version": 1, "plan": d.plan, "source_changed": d.changed, "runtime_changed": drift,
		"added": changes.Added, "removed": changes.Removed, "modified": changes.Modified,
		"details": reportDetails(d, changes), "providers_changed": d.providersChanged, "outcome": outcome,
	})
}

func reportDetails(d deployment, changes changeSet) []changeDetail {
	if !d.verbose {
		return nil
	}
	return changes.Details
}

func targetValid(target string) bool {
	kind, id, ok := strings.Cut(target, "/")
	return ok && slices.Contains([]string{"agent", "dag", "skill", "tool"}, kind) && idValid(id)
}

func Init(source string) error {
	var args []string
	if source != "" {
		args = []string{source}
	}
	return withState(true, func(c config) error { return setup(c, args) })
}

func Edit(target string) error { return EditWorkspace(target, true) }

func EditWorkspace(target string, apply bool) error {
	if target != "" && !targetValid(target) {
		return errors.New("invalid capability target")
	}
	if target == "" && !terminalInput() {
		return errors.New("non-interactive edit requires kind/id")
	}
	return withInitializedState(func(c config) error { return editTarget(c, target, apply) })
}

type ReconcileRequest struct{ Plan, JSON, Verbose bool }

func Reconcile(req ReconcileRequest) error {
	cmd := "sync"
	if req.Plan {
		cmd = "plan"
	}
	return withInitializedState(func(c config) error {
		return reconcileWithOptions(c, cmd, req.JSON, false, req.Verbose)
	})
}

func Lock() error {
	return withInitializedState(func(c config) error { return reconcile(c, "lock") })
}

func Purge() error { return withState(false, purge) }

// 초기화되지 않은 Vault에는 편집·계획·동기화가 상태를 생성하지 않는다.
func withInitializedState(fn func(config) error) error {
	c, err := loadConfig()
	if err != nil {
		return err
	}
	if !exists(c.archive) && !exists(c.workspace) {
		return errors.New("no initialized capability; run harness config init")
	}
	return withState(false, fn)
}
