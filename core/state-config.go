package core

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"syscall"
)

func workspaceBasePath(c config) string {
	return filepath.Join(c.state, "workspace.base")
}

func currentArchiveFingerprint(c config) (string, error) {
	if !exists(c.archive) {
		return "absent", nil
	}
	cipher, err := readRegular(c.archive)
	if err != nil {
		return "", err
	}
	sum := sha256.Sum256(cipher)
	return hex.EncodeToString(sum[:]), nil
}

func recordWorkspaceBase(c config) error {
	fingerprint, err := currentArchiveFingerprint(c)
	if err != nil {
		return err
	}
	return atomicWrite(workspaceBasePath(c), []byte(fingerprint+"\n"))
}

func checkWorkspaceBase(c config) error {
	path := workspaceBasePath(c)
	if !exists(path) {
		if exists(c.archive) {
			return errors.New("workspace baseline missing; preserve workspace and reconcile it before applying")
		}
		if err := recordWorkspaceBase(c); err != nil {
			return err
		}
	}
	data, err := readRegular(path)
	if err != nil {
		return err
	}
	current, err := currentArchiveFingerprint(c)
	if err != nil {
		return err
	}
	if strings.TrimSpace(string(data)) != current {
		return errors.New("vault changed since workspace opened; preserve workspace and reconcile before applying")
	}
	return nil
}

type config struct {
	repo, state, workspace, runtime, archive, key string
}

// 체크아웃과 평문 저장 경계를 분리하고 사용자 전용 디렉터리를 확보한다.
func privateDir(path string) error {
	if err := os.MkdirAll(path, 0700); err != nil {
		return err
	}
	return privateDirCheck(path)
}

func privateDirCheck(path string) error {
	info, err := os.Lstat(path)
	if err != nil {
		return err
	}
	var unsafe = errors.New("unsafe private directory; verify ownership, symlinks and permissions (must be 0700)")
	if !info.IsDir() || info.Mode().Perm() != 0700 || info.Sys().(*syscall.Stat_t).Uid != uint32(os.Getuid()) {
		return unsafe
	}
	real, err := filepath.EvalSymlinks(path)
	if err != nil {
		return err
	}
	if real != path {
		return unsafe
	}
	return nil
}

// 조회 명령은 없는 경로를 만들지 않는다.
func existingPrivateDir(path string) error {
	err := privateDirCheck(path)
	if os.IsNotExist(err) {
		return nil
	}
	return err
}

func exists(path string) bool { _, err := os.Lstat(path); return !os.IsNotExist(err) }
func inside(parent, child string) bool {
	rel, err := filepath.Rel(parent, child)
	return err == nil && rel != ".." && !strings.HasPrefix(rel, "../")
}

func loadConfig() (config, error) {
	var c config
	repo, err := os.Getwd()
	if err != nil {
		return c, err
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return c, err
	}
	repo, err = repositoryRoot(repo)
	if err != nil {
		return c, err
	}
	repo, err = filepath.EvalSymlinks(repo)
	if err != nil {
		return c, err
	}
	c.repo = repo

	c.key = filepath.Join(home, ".config/tonys-agent-harness/age.key")
	c.archive = filepath.Join(repo, "capability.enc")
	if v := os.Getenv("HARNESS_VAULT"); v != "" {
		c.archive = v
	}
	c.state = filepath.Join(home, ".local/share/tonys-agent-harness", hashBytes([]byte(repo + "\n" + c.archive))[:16])
	if v := os.Getenv("HARNESS_STATE"); v != "" {
		c.state = v
	}
	if v := os.Getenv("HARNESS_AGE_KEY"); v != "" {
		c.key = v
	}
	for _, p := range []string{c.state, c.key, c.archive} {
		if !filepath.IsAbs(p) || filepath.Clean(p) != p {
			return c, errors.New("absolute clean paths required")
		}
	}
	isInsideStore := inside("/nix/store", c.state) || inside("/nix/store", c.key) || inside("/nix/store", c.archive)
	var unsafeBoundary = inside(repo, c.state) || inside(repo, c.key) || isInsideStore ||
		inside(c.state, c.archive) || inside(c.state, c.key) || c.archive == c.key
	if unsafeBoundary {
		return c, errors.New("unsafe state/key/vault boundary")
	}
	c.workspace = filepath.Join(c.state, "capability")
	c.runtime = filepath.Join(c.state, "runtime")
	if !exists(filepath.Join(repo, "core/environment-public.txt")) {
		return c, errors.New("run from a v19 repository root")
	}
	return c, nil
}

// 프로세스 종료 시 커널이 잠금을 해제한다. 잠금 파일은 삭제하지 않는다.
func operationLock(c config) (*os.File, error) {
	if err := privateDir(c.state); err != nil {
		return nil, err
	}
	path := filepath.Join(c.state, "operation.lock")
	fd, err := syscall.Open(path, syscall.O_CREAT|syscall.O_RDWR|syscall.O_NOFOLLOW|syscall.O_CLOEXEC, 0600)
	if err != nil {
		return nil, err
	}
	f := os.NewFile(uintptr(fd), "operation.lock")
	info, err := f.Stat()
	if err != nil {
		f.Close()
		return nil, err
	}
	if !info.Mode().IsRegular() || info.Mode().Perm() != 0600 || info.Sys().(*syscall.Stat_t).Nlink != 1 {
		f.Close()
		return nil, errors.New("unsafe operation lock")
	}
	if err = syscall.Flock(fd, syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		f.Close()
		return nil, errors.New("operation busy")
	}
	return f, nil
}

// 외부 도구의 오류 출력에 평문이 포함될 수 있어 명령 이름만 보고한다.
func run(name string, args ...string) ([]byte, error) {
	cmd := exec.Command(name, args...)
	out, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("%s failed: %w", name, err)
	}
	return out, nil
}

// 파일 경로는 민감한 Skill ID를 포함할 수 있다.
// 결합된 오류의 정리 실패 정보는 유지하면서 경로만 숨긴다.
func PublicError(err error) string {
	if joined, ok := err.(interface{ Unwrap() []error }); ok {
		var messages []string
		for _, item := range joined.Unwrap() {
			messages = append(messages, PublicError(item))
		}
		return strings.Join(messages, "; ")
	}
	var pathErr *os.PathError
	if errors.As(err, &pathErr) {
		return fmt.Sprintf("filesystem %s: %s", pathErr.Op, pathErr.Err)
	}
	return err.Error()
}

// 서로 다른 체크아웃이나 Vault가 하나의 편집 공간을 공유하지 않도록 한다.
func bindState(c config) error {
	path := filepath.Join(c.state, "binding")
	expected := c.archive + "\n" + c.repo + "\n"
	if !exists(path) {
		if exists(c.workspace) || exists(c.runtime) {
			return errors.New("unbound existing state; use a fresh state directory")
		}
		return atomicWrite(path, []byte(expected))
	}
	data, err := readRegular(path)
	if err != nil {
		return err
	}
	if string(data) != expected {
		return errors.New("state bound to another repository or vault; set HARNESS_STATE")
	}
	return nil
}

func repositoryRoot(cwd string) (string, error) {
	if repo := os.Getenv("HARNESS_REPO"); repo != "" {
		return filepath.Abs(repo)
	}
	for path := cwd; ; path = filepath.Dir(path) {
		if exists(filepath.Join(path, "core/environment-public.txt")) {
			return path, nil
		}
		if filepath.Dir(path) == path {
			break
		}
	}
	path, err := defaultRepositoryPath()
	if err != nil {
		return "", err
	}
	data, err := readRegular(path)
	if os.IsNotExist(err) {
		return "", errors.New("repository not found; run harness setup --repo PATH")
	}
	if err != nil {
		return "", err
	}
	repo := string(data)
	if !filepath.IsAbs(repo) || filepath.Clean(repo) != repo {
		return "", errors.New("invalid default checkout; run harness setup --repo PATH")
	}
	return repo, nil
}

func defaultRepositoryPath() (string, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(home, ".config", "tonys-agent-harness", "default-checkout"), nil
}

/*
사용자가 선택한 체크아웃만 저장한다.
설정의 유효성을 확인한 후 원자적으로 교체하여 다른 호출이 중간 값을 읽지 않게 한다.
*/
func SetupRepository() error {
	c, err := loadConfig()
	if err != nil {
		return err
	}
	if _, err = readStatus(c); err != nil {
		return err
	}
	path, err := defaultRepositoryPath()
	if err != nil {
		return err
	}
	if err = privateDir(filepath.Dir(path)); err != nil {
		return err
	}
	return atomicWrite(path, []byte(c.repo))
}

type SourceStatus struct {
	Name     string `json:"name"`
	Pinned   bool   `json:"pinned"`
	Revision string `json:"revision"`
}

type ProviderStatus struct {
	Name  string `json:"name"`
	State string `json:"state"`
}

type StatusReport struct {
	SchemaVersion   int              `json:"schema_version"`
	ArchiveExists   bool             `json:"archive_exists"`
	WorkspaceExists bool             `json:"workspace_exists"`
	RuntimeExists   bool             `json:"runtime_exists"`
	KeyExists       bool             `json:"key_exists"`
	LegacyPlaintext bool             `json:"legacy_plaintext"`
	LegacyBackup    bool             `json:"legacy_backup"`
	Sources         []SourceStatus   `json:"sources"`
	Providers       []ProviderStatus `json:"providers"`
	Next            string           `json:"next_action"`
}

/*
상태 조회는 복호화하거나 새 상태를 만들지 않는다.
존재 여부를 무결성 또는 동기화 완료로 오인하지 않게 한다.
*/
func ReadStatus() (StatusReport, error) {
	c, err := loadConfig()
	if err != nil {
		return StatusReport{}, err
	}
	return readStatus(c)
}

func readStatus(c config) (StatusReport, error) {
	var r StatusReport
	if err := existingPrivateDir(c.state); err != nil {
		return r, err
	}
	if err := existingPrivateDir(c.runtime); err != nil {
		return r, err
	}
	live, err := livePath(c)
	if err != nil {
		return r, err
	}
	r = StatusReport{
		SchemaVersion: 1, ArchiveExists: exists(c.archive), WorkspaceExists: exists(c.workspace),
		RuntimeExists: live != "", KeyExists: exists(c.key),
		LegacyPlaintext: exists(filepath.Join(c.repo, "capability")) || exists(filepath.Join(c.repo, ".runtime")),
		LegacyBackup:    exists(filepath.Join(c.state, "legacy-backup")),
	}
	r.Sources, err = sourceStatusRows(c)
	if err != nil {
		return r, err
	}
	r.Providers, err = providerStatusRows(c, "")
	if err != nil {
		return r, err
	}
	_, defaultProvider, err := providerNames(c)
	if err != nil {
		return r, err
	}
	r.Next = statusNext(r, exists(c.runtime), defaultProvider)
	return r, nil
}

/*
복원과 편집 상태를 연결 안내보다 먼저 확인한다.
파일 존재 여부만 관찰하므로 동기화 완료를 선언하지 않는다.
*/
func statusNext(r StatusReport, runtimeDirectory bool, defaultProvider string) string {
	switch {
	case r.LegacyPlaintext:
		return "inspect legacy plaintext before migration"
	case !r.ArchiveExists && runtimeDirectory:
		return "restore the existing encrypted Vault"
	case r.ArchiveExists && !r.KeyExists:
		return "restore the age key for this Vault"
	case r.WorkspaceExists:
		return "harness apply --dry-run"
	case !r.ArchiveExists:
		return "harness config init PATH or empty"
	case !r.RuntimeExists:
		return "harness apply"
	default:
		return providerNext(r.Providers, defaultProvider)
	}
}

func sourceStatusRows(c config) ([]SourceStatus, error) {
	sources, err := sourcesRead(c)
	if err != nil {
		return nil, err
	}
	rows := make([]SourceStatus, 0, len(sources))
	for name, s := range sources {
		rows = append(rows, SourceStatus{Name: name, Pinned: s.valid(), Revision: s.Revision})
	}
	sort.Slice(rows, func(i, j int) bool { return rows[i].Name < rows[j].Name })
	return rows, nil
}

func providerStatusRows(c config, name string) ([]ProviderStatus, error) {
	names, _, err := providerNames(c)
	if err != nil {
		return nil, err
	}
	if name != "" {
		names = []string{name}
	}
	rows := make([]ProviderStatus, 0, len(names))
	for _, id := range names {
		state, err := providerState(c, id)
		if err != nil {
			return nil, err
		}
		rows = append(rows, ProviderStatus{Name: id, State: string(state)})
	}
	return rows, nil
}

func providerNext(rows []ProviderStatus, defaultProvider string) string {
	connected := false
	for _, row := range rows {
		switch row.State {
		case "CONFLICT":
			return "harness provider status " + row.Name
		case "MIGRATION_REQUIRED":
			return "harness provider connect " + row.Name
		case "DRIFTED", "BLOCKED":
			return "harness apply"
		case "CONNECTED":
			connected = true
		}
	}
	if !connected {
		return "harness provider connect " + defaultProvider
	}
	return ""
}
