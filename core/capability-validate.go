package core

import (
	"encoding/json"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"strings"
	"sync"
)

type node struct {
	Kind       string      `json:"kind"`
	Origin     string      `json:"origin"`
	Provenance *provenance `json:"provenance,omitempty"`
	Path       string      `json:"path"`
	Requires   []string    `json:"requires"`
	Hints      []string    `json:"hints"`
	Content    string      `json:"content_sha256"`
}

type nodeJob struct {
	kind, name, path string
}

type nodeResult struct {
	index int
	name  string
	node  node
	err   error
}

type nodeWorkerRequest struct {
	c      config
	root   string
	jobs   []nodeJob
	input  <-chan nodeResult
	output chan<- nodeResult
}

var idPattern = regexp.MustCompile(`^[a-z0-9]+(-[a-z0-9]+)*$`)
var compositionPattern = regexp.MustCompile("(?ms)^```json composition\\n(.*?)\\n```$")

func idValid(s string) bool { return len(s) <= 64 && idPattern.MatchString(s) }

// 기존 엄격한 YAML/Tool 검증기를 임시 호환 계층으로 유지한다.
// 검증 중 Skill 스크립트나 외부 네트워크는 실행하지 않는다.
func contractCheck(c config, script string, args ...string) (resultErr error) {
	cmd := exec.Command("bash", append([]string{filepath.Join(c.repo, "core", script)}, args...)...)
	tmp, err := os.MkdirTemp(c.state, "stage-validator-")
	if err != nil {
		return err
	}
	defer cleanupPath(&resultErr, tmp)
	cmd.Env = append(os.Environ(), "TMPDIR="+tmp)
	if err := cmd.Run(); err != nil {
		return errors.New(script + " failed (private details suppressed)")
	}
	return nil
}

func nodeRead(c config, root, kind, name, path string) (node, error) {
	n := node{
		Kind: kind, Path: "capability/" + strings.TrimPrefix(path, root+"/"), Origin: "private",
		Requires: []string{}, Hints: []string{},
	}
	data, err := readRegular(path)
	if err != nil {
		return n, err
	}
	if kind != "agent" {
		if err = contractCheck(c, "skill-validate.sh", filepath.Dir(path), root); err != nil {
			return n, err
		}
	}
	blocks := compositionPattern.FindAllSubmatch(data, -1)
	external := false
	if kind == "skill" {
		p, e := provenanceRead(filepath.Dir(path))
		external = e == nil && p.Content != ""
		if e == nil {
			n.Provenance = &p
		}
	}
	if external {
		n.Origin = "external"
	}
	expected := 1
	if kind == "tool" || external {
		expected = 0
	}
	if len(blocks) != expected {
		return n, errors.New("invalid composition block count")
	}
	if expected == 1 {
		var refs map[string][]string
		if err = json.Unmarshal(blocks[0][1], &refs); err != nil {
			return n, err
		}
		if len(refs) != 2 || refs["requires"] == nil || refs["hints"] == nil {
			return n, errors.New("invalid composition fields")
		}
		n.Requires = refs["requires"]
		n.Hints = refs["hints"]
	}
	var hasDAG = kind == "dag" && exists(filepath.Join(filepath.Dir(path), "DAG.yaml"))
	if hasDAG {
		dir := filepath.Dir(path)
		if err = contractCheck(
			c, "dag-validate.sh", filepath.Join(dir, "DAG.yaml"),
			filepath.Join(dir, "dag-contract.schema.json"), filepath.Dir(root),
		); err != nil {
			return n, err
		}
	}
	if kind == "tool" && name == "tool-git-evidence" {
		if err = contractCheck(
			c, "tool-contract-validate.sh", filepath.Join(c.repo, "contract/git-evidence.json"),
			filepath.Join(filepath.Dir(path), "TOOL.md"), path,
			filepath.Join(c.repo, "contract/git-evidence.schema.json"), filepath.Dir(root),
		); err != nil {
			return n, err
		}
	}
	if kind != "agent" {
		n.Content, err = digest(filepath.Dir(path))
	} else {
		n.Content = hashBytes(data)
	}
	return n, err
}

// 종류별 선언을 동일한 ID 공간에 등록한다.
// 중복과 잘못된 파일 구조를 Graph 계산보다 먼저 거부한다.
func nodesRead(c config, root string) (map[string]node, error) {
	jobs, err := nodeJobs(root)
	if err != nil {
		return nil, err
	}
	results := nodeResults(c, root, jobs)
	nodes := make(map[string]node, len(results))
	for _, result := range results {
		if result.err != nil {
			return nil, result.err
		}
		nodes[result.name] = result.node
	}
	if len(nodes) == 0 {
		return nil, errors.New("empty capability tree")
	}
	return nodes, relationsValidate(nodes)
}

func nodeJobs(root string) ([]nodeJob, error) {
	seen := map[string]bool{}
	var jobs []nodeJob
	for _, kind := range []string{"agent", "dag", "skill", "tool"} {
		entries, err := kindJobs(root, kind, seen)
		if err != nil {
			return nil, err
		}
		jobs = append(jobs, entries...)
	}
	return jobs, nil
}

func kindJobs(root, kind string, seen map[string]bool) ([]nodeJob, error) {
	entries, err := os.ReadDir(filepath.Join(root, kind))
	if err != nil {
		return nil, err
	}
	jobs := make([]nodeJob, 0, len(entries))
	for _, entry := range entries {
		name, path, err := entryPath(root, kind, entry)
		if err != nil {
			return nil, err
		}
		if seen[name] {
			return nil, errors.New("duplicate capability ID")
		}
		seen[name] = true
		jobs = append(jobs, nodeJob{kind: kind, name: name, path: path})
	}
	return jobs, nil
}

func nodeResults(c config, root string, jobs []nodeJob) []nodeResult {
	input := make(chan nodeResult, len(jobs))
	output := make(chan nodeResult, len(jobs))
	for index := range jobs {
		input <- nodeResult{index: index}
	}
	close(input)

	var workers sync.WaitGroup
	workerCount := validationWorkerCount(len(jobs))
	workers.Add(workerCount)
	request := nodeWorkerRequest{c: c, root: root, jobs: jobs, input: input, output: output}
	for range workerCount {
		go nodeWorker(request, &workers)
	}
	workers.Wait()
	close(output)

	results := make([]nodeResult, len(jobs))
	for result := range output {
		results[result.index] = result
	}
	return results
}

func nodeWorker(request nodeWorkerRequest, workers *sync.WaitGroup) {
	defer workers.Done()
	for result := range request.input {
		job := request.jobs[result.index]
		result.name = job.name
		result.node, result.err = nodeRead(request.c, request.root, job.kind, job.name, job.path)
		request.output <- result
	}
}

func validationWorkerCount(total int) int {
	if total == 0 {
		return 0
	}
	workers := runtime.GOMAXPROCS(0)
	if workers < 2 && total > 1 {
		workers = 2
	}
	if workers > 4 {
		workers = 4
	}
	if workers > total {
		workers = total
	}
	return workers
}

func entryPath(root, kind string, entry os.DirEntry) (string, string, error) {
	name := entry.Name()
	path := filepath.Join(root, kind, name)
	if kind == "agent" {
		if entry.IsDir() || !strings.HasSuffix(name, ".md") {
			return "", "", errors.New("invalid agent entry")
		}
		name = strings.TrimSuffix(name, ".md")
	} else {
		if !entry.IsDir() {
			return "", "", errors.New("invalid capability entry")
		}
		path = filepath.Join(path, "SKILL.md")
	}
	if !idValid(name) {
		return "", "", errors.New("invalid capability ID")
	}
	return name, path, nil
}

func relationTypesValidate(n node, nodes map[string]node) error {
	seen := map[string]bool{}
	for _, ref := range append(append([]string{}, n.Requires...), n.Hints...) {
		target, ok := nodes[ref]
		isAllowed := ok && relationAllowed(n.Kind, target.Kind)
		if !isAllowed || seen[ref] {
			return errors.New("invalid capability relation")
		}
		seen[ref] = true
	}
	return nil
}

func relationAllowed(from, to string) bool {
	switch from {
	case "tool":
		return false
	case "skill":
		return to == "tool"
	case "dag":
		return to == "skill"
	case "agent":
		return to == "tool" || to == "skill" || to == "dag" || to == "agent"
	default:
		return false
	}
}

// 참조의 종류, 존재 여부 및 순환 관계를 검증한다.
// 이 Graph를 실행 순서나 권한으로 해석하지 않는다.
func relationsValidate(nodes map[string]node) error {
	for _, n := range nodes {
		if err := relationTypesValidate(n, nodes); err != nil {
			return err
		}
	}
	marks := map[string]int{}
	var visit func(string) error
	visit = func(id string) error {
		if marks[id] == 1 {
			return errors.New("composition cycle")
		}
		if marks[id] == 2 {
			return nil
		}
		marks[id] = 1
		n := nodes[id]
		for _, ref := range append(append([]string{}, n.Requires...), n.Hints...) {
			if err := visit(ref); err != nil {
				return err
			}
		}
		marks[id] = 2
		return nil
	}
	for id := range nodes {
		if err := visit(id); err != nil {
			return err
		}
	}
	return nil
}

func validate(c config, root string) (map[string]node, error) {
	if err := validateStructure(root); err != nil {
		return nil, err
	}
	return nodesRead(c, root)
}

// Source 투영 전에는 경로와 루트 구조만 확인한다.
// 비용이 큰 개별 계약 검증은 최종 Runtime 후보에서 한 번 수행한다.
func validateStructure(root string) error {
	if err := treeWalk(root, func(path string, info os.FileInfo) error {
		name := info.Name()
		var isSecret = strings.HasPrefix(name, ".env") ||
			strings.HasSuffix(name, ".key") || strings.HasSuffix(name, ".pem")
		if name == ".git" || isSecret || name == "auth.json" || strings.HasPrefix(name, "credentials") {
			return errors.New("sensitive filename")
		}
		return nil
	}); err != nil {
		return err
	}
	entries, err := os.ReadDir(root)
	if err != nil {
		return err
	}
	for _, entry := range entries {
		var name = entry.Name()
		switch name {
		case "agent", "dag", "skill", "tool", "scripts":
			if !entry.IsDir() {
				return errors.New("invalid capability directory")
			}
		case "POLICY.md", "STANDARD.md", "README.md", "CHANGELOG.md", "catalog.json":
			if entry.IsDir() {
				return errors.New("invalid metadata file")
			}
		default:
			return errors.New("unexpected capability root entry")
		}
	}
	return nil
}

/*
Catalog은 로컬 원본의 생성물이며 사용자 제공 스크립트를 실행하지 않는다.
외부 Source 투영 전에 공개 검증기에서 metadata 일치 여부를 검사한다.
*/
func catalogValidate(c config, root string) error {
	if !exists(filepath.Join(root, "catalog.json")) {
		return nil
	}
	var cmd = exec.Command("python3", filepath.Join(c.repo, "core/metadata-validate.py"), "catalog", root)
	if err := cmd.Run(); err != nil {
		return errors.New("catalog validation failed; regenerate catalog and retry")
	}
	return nil
}
