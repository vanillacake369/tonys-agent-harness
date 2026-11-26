package core

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"maps"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
	"time"
)

type source struct {
	URL           string            `json:"url"`
	Revision      string            `json:"rev"`
	Path          string            `json:"path"`
	ID            string            `json:"id"`
	Collection    bool              `json:"collection,omitempty"`
	Phases        map[string]string `json:"phases"`
	SelectByPhase bool              `json:"select_by_phase,omitempty"`
}

// 기존 Vault의 provenance는 읽기 호환성만 유지한다.
type provenance struct {
	Source   string `json:"source"`
	Revision string `json:"revision"`
	Path     string `json:"path"`
	Content  string `json:"content_sha256"`
	Hash     string `json:"hash,omitempty"`
}

var revisionPattern = regexp.MustCompile(`^[0-9a-f]{40}$`)
var githubURLPattern = regexp.MustCompile(`^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$`)
var sourceCacheNamePattern = regexp.MustCompile(`^[0-9a-f]{64}$`)

type SourceCachePruneResult struct {
	Plan    bool  `json:"plan"`
	Removed int   `json:"removed"`
	Bytes   int64 `json:"bytes"`
}

func sourcesRead(c config) (map[string]source, error) {
	var sources map[string]source
	var b, err = readRegular(filepath.Join(c.repo, "source/registry-sources.json"))
	if os.IsNotExist(err) {
		return map[string]source{}, nil
	}
	if err != nil {
		return nil, err
	}
	if err = json.Unmarshal(b, &sources); err != nil {
		return nil, err
	}
	for name, s := range sources {
		var invalid = !idValid(name) || !idValid(s.ID) || !safeRelative(s.Path) ||
			(!s.Collection && filepath.Base(s.Path) != s.ID) || !githubURLPattern.MatchString(s.URL) ||
			!s.validSelection()
		if invalid {
			return nil, errors.New("invalid source catalog")
		}
		if s.Revision != "" && !s.valid() {
			return nil, errors.New("invalid source revision")
		}
	}
	return sources, nil
}

func (s source) valid() bool {
	return revisionPattern.MatchString(s.Revision) && safeRelative(s.Path) && idValid(s.ID)
}

func (s source) validSelection() bool {
	if !s.SelectByPhase {
		return true
	}
	if !s.Collection || len(s.Phases) == 0 {
		return false
	}
	for id, phase := range s.Phases {
		if !idValid(id) || (phase != "pre" && phase != "mid" && phase != "post") {
			return false
		}
	}
	return true
}

// 검토 대상으로 지정한 디렉터리만 archive에 포함해 미선택 파일을 가져오지 않는다.
func (s source) archivePaths() []string {
	if !s.SelectByPhase {
		return []string{s.Path}
	}
	var paths []string
	for _, id := range slices.Sorted(maps.Keys(s.Phases)) {
		paths = append(paths, filepath.ToSlash(filepath.Join(s.Path, id)))
	}
	return paths
}

func provenanceRead(path string) (provenance, error) {
	var v provenance
	var b, err = readRegular(filepath.Join(path, "source-provenance.json"))
	if err != nil {
		return v, err
	}
	err = json.Unmarshal(b, &v)
	return v, err
}

/*
Git 인증은 사용자 credential helper에 위임한다. 대화형 인증이나
원격 오류 출력은 허용하지 않는다. 회사 인증은 gh auth setup-git으로 설정한다.
*/
func sourceGit(args ...string) ([]byte, error) {
	var options = []string{"-c", "protocol.file.allow=never", "-c", "protocol.ext.allow=never",
		"-c", "core.hooksPath=/dev/null", "-c", "credential.interactive=false"}
	var ctx, cancel = context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	var cmd = exec.CommandContext(ctx, "git", append(options, args...)...)
	cmd.Env = append(sourceGitEnv(), "GIT_TERMINAL_PROMPT=0", "GCM_INTERACTIVE=Never", "GIT_NO_REPLACE_OBJECTS=1")
	var pipe, err = cmd.StdoutPipe()
	if err != nil {
		return nil, err
	}
	if err = cmd.Start(); err != nil {
		return nil, errors.New("Git executable unavailable")
	}
	var out, readErr = io.ReadAll(io.LimitReader(pipe, maxArchive+1))
	if len(out) > maxArchive || readErr != nil {
		cancel()
		_ = cmd.Wait()
		return nil, errors.New("Git source output exceeded limit or could not be read")
	}
	err = cmd.Wait()
	if err != nil {
		return nil, errors.New("Git source access failed; check gh auth status / gh auth setup-git and SSO")
	}
	return out, nil
}

// 현재 checkout의 Git 환경이 별도 Source repository를 변경하지 않게 한다.
func sourceGitEnv() []string {
	var env []string
	for _, item := range os.Environ() {
		var key, _, _ = strings.Cut(item, "=")
		if strings.HasPrefix(key, "GIT_") {
			continue
		}
		env = append(env, item)
	}
	return env
}

/*
검토한 커밋의 선택 경로만 개인 임시 공간에 추출한다.
Git checkout/filter/hook 실행 없이 archive를 기존 안전한 unpack으로 처리한다.
*/
func sourceFetch(c config, s source, target string) (resultErr error) {
	if !s.valid() || !s.validSelection() {
		return errors.New("invalid source pin")
	}
	var tmp, err = os.MkdirTemp(c.state, "stage-source-")
	if err != nil {
		return err
	}
	defer cleanupPath(&resultErr, tmp)
	var gitDir = filepath.Join(tmp, "repo")
	if _, err = sourceGit("init", "--bare", gitDir); err != nil {
		return err
	}
	if _, err = sourceGit("-C", gitDir, "fetch", "--no-tags", "--depth=1", "--", s.URL, s.Revision); err != nil {
		return err
	}
	var out, verifyErr = sourceGit("-C", gitDir, "rev-parse", "FETCH_HEAD^{commit}")
	if verifyErr != nil || strings.TrimSpace(string(out)) != s.Revision {
		return errors.New("source revision mismatch")
	}
	var args = []string{"-C", gitDir, "archive", "--format=tar", s.Revision, "--"}
	var data, archiveErr = sourceGit(append(args, s.archivePaths()...)...)
	if archiveErr != nil {
		return errors.New("cannot archive selected source path at reviewed revision; check source path and revision")
	}
	var extracted = filepath.Join(tmp, "tree")
	if err = os.Mkdir(extracted, 0700); err != nil {
		return err
	}
	if err = unpackGitArchive(data, extracted, s.Revision); err != nil {
		return err
	}
	var selected = filepath.Join(extracted, s.Path)
	if err = sourceValidate(c, s, selected); err != nil {
		return err
	}
	return copyTree(selected, target)
}

// 컬렉션의 각 항목을 별도 Skill로 검증하며 임의 스크립트는 실행하지 않는다.
func sourceValidate(c config, s source, root string) error {
	if !s.Collection {
		return sourceValidateSkill(c, root)
	}
	entries, err := os.ReadDir(root)
	if err != nil {
		return err
	}
	if len(entries) == 0 {
		return errors.New("empty source collection")
	}
	count := 0
	for _, entry := range entries {
		if entry.Type().IsRegular() {
			continue
		}
		if !entry.IsDir() || !idValid(entry.Name()) {
			return errors.New("invalid source collection entry")
		}
		count++
		if err = sourceValidateSkill(c, filepath.Join(root, entry.Name())); err != nil {
			return err
		}
	}
	if count == 0 {
		return errors.New("empty source collection")
	}
	return nil
}

func sourceValidateSkill(c config, root string) error {
	if exists(filepath.Join(root, "source-provenance.json")) {
		return errors.New("reserved provenance file")
	}
	return contractCheck(c, "skill-validate.sh", root)
}

// Source는 사용자 원본과 분리된 검증 후보에만 투영한다.
func sourcesProject(c config, root string) error {
	var sources, err = sourcesRead(c)
	if err != nil {
		return err
	}
	for name, s := range sources {
		if s.Revision == "" {
			continue
		}
		if err = sourceProject(c, root, name, s); err != nil {
			return fmt.Errorf("source %s projection failed: %s", name, PublicError(err))
		}
	}
	return nil
}

func sourceProject(c config, root, name string, s source) (resultErr error) {
	if !s.Collection {
		target, err := s.importTarget(root, name, s.ID)
		if err != nil {
			return err
		}
		if err = sourceResolve(c, s, target); err != nil {
			return err
		}
		return s.finishImport(c, target, name, s.Path)
	}
	tmp, err := os.MkdirTemp(c.state, "stage-collection-")
	if err != nil {
		return err
	}
	defer cleanupPath(&resultErr, tmp)
	tree := filepath.Join(tmp, "collection")
	if err = sourceResolve(c, s, tree); err != nil {
		return err
	}
	entries, err := os.ReadDir(tree)
	if err != nil {
		return err
	}
	for _, entry := range entries {
		if entry.Type().IsRegular() {
			continue
		}
		if !entry.IsDir() || !idValid(entry.Name()) {
			return errors.New("invalid source collection entry")
		}
		target, err := s.importTarget(root, name, entry.Name())
		if err != nil {
			return err
		}
		if err = copyTree(filepath.Join(tree, entry.Name()), target); err != nil {
			return err
		}
		if err = s.finishImport(c, target, name, filepath.ToSlash(filepath.Join(s.Path, entry.Name()))); err != nil {
			return err
		}
	}
	return nil
}

func (s source) importTarget(root, sourceName, original string) (string, error) {
	phase := s.Phases[original]
	if phase != "pre" && phase != "mid" && phase != "post" {
		return "", fmt.Errorf("source %s skill %s requires an import phase (pre, mid, post)", sourceName, original)
	}
	id := "skl-" + phase + "-" + original + "-" + sourceName
	if !idValid(id) {
		return "", fmt.Errorf("invalid imported skill ID: %s", id)
	}
	target := filepath.Join(root, "skill", id)
	if exists(target) {
		return "", fmt.Errorf("source ID collision: %s", id)
	}
	return target, nil
}

/*
검토된 Git 원본과 캐시는 그대로 두고 후보의 호출 이름만 변경한다.
이름 변환에 실패하면 후보는 폐기되고 현재 Runtime은 유지된다.
*/
func (s source) finishImport(c config, target, name, path string) error {
	cmd := exec.Command("python3", filepath.Join(c.repo, "core", "metadata-validate.py"),
		"import-name", filepath.Join(target, "SKILL.md"), filepath.Base(path), filepath.Base(target))
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("could not set imported name for %s/%s", name, filepath.Base(path))
	}
	return sourceProvenance(target, name, s, path)
}

func sourceProvenance(target, name string, s source, path string) error {
	content, err := digest(target)
	if err != nil {
		return err
	}
	b, err := json.Marshal(provenance{Source: name, Revision: s.Revision, Path: path, Content: content})
	if err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(target, "source-provenance.json"), b, 0600)
}

func pinSource(c config, args []string) (resultErr error) {
	if len(args) != 2 || !revisionPattern.MatchString(args[1]) {
		return errors.New("full reviewed revision required")
	}
	var sources, err = sourcesRead(c)
	if err != nil {
		return err
	}
	var s, ok = sources[args[0]]
	if !ok {
		return errors.New("unknown source")
	}
	s.Revision = args[1]
	tmp, err := os.MkdirTemp(c.state, "stage-pin-")
	if err != nil {
		return err
	}
	defer cleanupPath(&resultErr, tmp)
	if err = sourceResolve(c, s, filepath.Join(tmp, "skill")); err != nil {
		return err
	}
	if err = sourceCacheSave(c, s, filepath.Join(tmp, "skill")); err != nil {
		return err
	}
	sources[args[0]] = s
	b, err := json.MarshalIndent(sources, "", "  ")
	if err != nil {
		return err
	}
	return atomicWrite(filepath.Join(c.repo, "source/registry-sources.json"), append(b, '\n'))
}

func UpdateSource(name, revision string) error {
	if revision == "" {
		c, err := loadConfig()
		if err != nil {
			return err
		}
		return sourceCandidates(c, name)
	}
	if !idValid(name) || !revisionPattern.MatchString(revision) {
		return errors.New("source name and full reviewed SHA required")
	}
	return withState(false, func(c config) error { return pinSource(c, []string{name, revision}) })
}

func ReadSources() ([]SourceStatus, error) {
	c, err := loadConfig()
	if err != nil {
		return nil, err
	}
	return sourceStatusRows(c)
}

/*
후보 조회는 원격 HEAD만 표시한다. 검토한 SHA의 명시적 입력 없이는 pin을 변경하지 않는다.
*/
func sourceCandidates(c config, name string) error {
	if name == "" {
		var rows, err = sourceStatusRows(c)
		if err != nil {
			return err
		}
		for _, row := range rows {
			fmt.Printf("%s pinned=%t revision=%s\n", row.Name, row.Pinned, row.Revision)
		}
		fmt.Println("Next: harness source check NAME")
		return nil
	}
	sources, err := sourcesRead(c)
	if err != nil {
		return err
	}
	s, ok := sources[name]
	if !ok {
		return errors.New("unknown source")
	}
	out, err := sourceGit("ls-remote", "--exit-code", s.URL, "HEAD")
	if err != nil {
		return fmt.Errorf("source %s remote check failed: %s; verify Git credentials and repository access",
			name, PublicError(err))
	}
	fields := strings.Fields(string(out))
	if len(fields) != 2 {
		return errors.New("invalid remote HEAD")
	}
	fmt.Printf("Candidate (unreviewed): %s\nReview before: harness source pin %s %s\n", fields[0], name, fields[0])
	return nil
}

// Cache는 원본이 아니며 검토한 동일 SHA와 digest가 모두 일치할 때만 사용한다.
func sourceCachePath(c config, s source) string {
	key := s.URL + "\n" + s.Revision + "\n" + s.Path + "\n" + s.ID
	if s.Collection {
		key += "\ncollection"
	}
	if s.SelectByPhase {
		key += "\nselected\n" + strings.Join(s.archivePaths(), "\n")
	}
	return filepath.Join(c.state, "source-cache", hashBytes([]byte(key)))
}

func sourceResolve(c config, s source, target string) error {
	var cache = sourceCachePath(c, s)
	if !exists(cache) {
		return sourceFetch(c, s, target)
	}
	if err := privateDir(cache); err != nil {
		return err
	}
	var expected, err = readRegular(filepath.Join(cache, "digest"))
	if err != nil {
		return err
	}
	var tree = filepath.Join(cache, "skill")
	actual, err := digest(tree)
	if err != nil {
		return err
	}
	if strings.TrimSpace(string(expected)) != actual {
		return errors.New("source cache integrity failure; remove cache manually")
	}
	return copyTree(tree, target)
}

func sourceCacheSave(c config, s source, tree string) (resultErr error) {
	var cache = sourceCachePath(c, s)
	if exists(cache) {
		return nil
	}
	var parent = filepath.Dir(cache)
	if err := privateDir(parent); err != nil {
		return err
	}
	var tmp, err = os.MkdirTemp(c.state, "stage-cache-")
	if err != nil {
		return err
	}
	defer cleanupPath(&resultErr, tmp)
	if err = copyTree(tree, filepath.Join(tmp, "skill")); err != nil {
		return err
	}
	content, err := digest(tree)
	if err != nil {
		return err
	}
	if err = os.WriteFile(filepath.Join(tmp, "digest"), []byte(content+"\n"), 0600); err != nil {
		return err
	}
	return os.Rename(tmp, cache)
}

// 현재 registry가 참조하지 않는 immutable cache만 정리한다.
// dry-run은 동일한 경계 검증과 용량 계산을 수행하되 파일을 변경하지 않는다.
func pruneSourceCache(c config, plan bool) (SourceCachePruneResult, error) {
	var result = SourceCachePruneResult{Plan: plan}
	sources, err := sourcesRead(c)
	if err != nil {
		return result, err
	}
	keep := map[string]bool{}
	for _, s := range sources {
		if s.valid() {
			keep[filepath.Base(sourceCachePath(c, s))] = true
		}
	}
	root := filepath.Join(c.state, "source-cache")
	if !exists(root) {
		return result, nil
	}
	if err = privateDir(root); err != nil {
		return result, err
	}
	entries, err := os.ReadDir(root)
	if err != nil {
		return result, err
	}
	for _, entry := range entries {
		if !entry.IsDir() || !sourceCacheNamePattern.MatchString(entry.Name()) {
			return result, errors.New("unsafe source cache entry")
		}
		path := filepath.Join(root, entry.Name())
		if err = privateDir(path); err != nil {
			return result, err
		}
		if keep[entry.Name()] {
			continue
		}
		var size int64
		err = treeWalk(path, func(_ string, info os.FileInfo) error {
			if info.Mode().IsRegular() {
				size += info.Size()
			}
			return nil
		})
		if err != nil {
			return result, err
		}
		result.Removed++
		result.Bytes += size
		if plan {
			continue
		}
		if err = os.RemoveAll(path); err != nil {
			return result, err
		}
	}
	return result, nil
}

func PruneSourceCache(plan bool) (SourceCachePruneResult, error) {
	var result SourceCachePruneResult
	err := withInitializedState(func(c config) error {
		var pruneErr error
		result, pruneErr = pruneSourceCache(c, plan)
		return pruneErr
	})
	return result, err
}
