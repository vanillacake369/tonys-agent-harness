package core

import (
	"crypto/sha256"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

func hashBytes(b []byte) string { return fmt.Sprintf("%x", sha256.Sum256(b)) }

// Runtime 후보는 외부 Nix Store가 아닌 사용자 전용 디렉터리에서 구성한다.
func runtimeBuild(c config, root, target string, nodes map[string]node) error {
	if err := os.Mkdir(target, 0700); err != nil {
		return err
	}
	if err := copyTree(root, filepath.Join(target, ".capability")); err != nil {
		return err
	}
	var descriptions, err = runtimeAgentDescriptions(root)
	if err != nil {
		return err
	}
	for id, n := range nodes {
		if err := runtimeNode(c, root, filepath.Join(target, id), n, descriptions[id]); err != nil {
			return err
		}
	}
	graph := map[string]any{"schema_version": 3, "scope": "bundle", "capabilities": nodes}
	b, err := json.MarshalIndent(graph, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(target, ".capability-graph.json"), b, 0600)
}

func runtimeNode(c config, root, target string, n node, description string) error {
	var id = filepath.Base(target)
	if n.Kind == "agent" {
		return runtimeAgentProfile(c, filepath.Dir(target), id, description)
	}
	if err := copyTree(filepath.Join(root, n.Kind, id), target); err != nil {
		return err
	}
	if err := runtimePolicyLink(c, filepath.Dir(target), id); err != nil {
		return err
	}
	if id == "tool-git-evidence" {
		return toolProject(c, target)
	}
	return nil
}

// 평탄화된 provider discovery에서도 공통 정책 경로가 유지되도록 한다.
func runtimePolicyLink(c config, target, id string) error {
	var path = filepath.Join(target, id, "SKILL.md")
	var b, err = readRegular(path)
	if err != nil {
		return err
	}
	var policy = filepath.Join(c.runtime, "skills", ".capability", "POLICY.md")
	var text = strings.ReplaceAll(string(b), "(../../POLICY.md)", "(<"+policy+">)")
	if text == string(b) {
		return nil
	}
	return os.WriteFile(path, []byte(text), 0600)
}

// Native subagent 실행을 가정하지 않는 portable role discovery를 제공한다.
func runtimeAgentDescriptions(root string) (map[string]string, error) {
	var result = map[string]string{}
	var path = filepath.Join(root, "catalog.json")
	if !exists(path) {
		return result, nil
	}
	var data, err = readRegular(path)
	if err != nil {
		return nil, err
	}
	var catalog struct {
		Capabilities map[string]struct{ Kind, Description string } `json:"capabilities"`
	}
	if err = json.Unmarshal(data, &catalog); err != nil {
		return nil, err
	}
	for id, entry := range catalog.Capabilities {
		if entry.Kind == "agent" {
			result[id] = entry.Description
		}
	}
	return result, nil
}

func runtimeAgentProfile(c config, target, id, description string) error {
	if description == "" {
		return nil
	} // Legacy profiles remain in the original snapshot.
	var dir = filepath.Join(target, id)
	if err := os.Mkdir(dir, 0700); err != nil {
		return err
	}
	var encoded, err = json.Marshal(description)
	if err != nil {
		return err
	}
	var profile = filepath.Join(c.runtime, "skills", ".capability", "agent", id+".md")
	var policy = filepath.Join(c.runtime, "skills", ".capability", "POLICY.md")
	var body = fmt.Sprintf("---\nname: %s\ndescription: %s\n---\n\n# Portable agent role\n\n", id, encoded)
	body += fmt.Sprintf("Read the [role profile](<%s>) and [policy](<%s>).\n", profile, policy)
	body += "This is a role skill, not a native subagent. " +
		"Delegate only when the provider supports it and authority permits.\n"
	body += "Otherwise use sequential role passes and disclose that limitation.\n"
	return os.WriteFile(filepath.Join(dir, "SKILL.md"), []byte(body), 0600)
}

func toolProject(c config, target string) error {
	files := map[string]string{
		"git-evidence.json":        "tool.json",
		"git-evidence.schema.json": "tool-contract.schema.json",
	}
	for from, to := range files {
		b, err := readRegular(filepath.Join(c.repo, "contract", from))
		if err != nil {
			return err
		}
		if err = os.WriteFile(filepath.Join(target, to), b, 0600); err != nil {
			return err
		}
	}
	return nil
}

func managedRuntimeLink(c config) (string, error) {
	live := filepath.Join(c.runtime, "skills")
	if !exists(live) {
		return "", nil
	}
	path, err := os.Readlink(live)
	if err != nil {
		return "", errors.New("unmanaged runtime link")
	}
	if filepath.Dir(path) != c.runtime || !strings.HasPrefix(filepath.Base(path), "generation-") {
		return "", errors.New("unsafe runtime link")
	}
	return path, nil
}

func livePath(c config) (string, error) {
	path, err := managedRuntimeLink(c)
	if err != nil || path == "" {
		return path, err
	}
	if !exists(path) {
		return "", errors.New("dangling runtime generation; run harness config runtime reset then harness apply")
	}
	if err = privateDir(path); err != nil {
		return "", err
	}
	return path, nil
}

/*
후보 generation을 먼저 생성한 뒤 활성 링크를 원자적으로 교체한다.
링크 교체 실패 시 기존 활성 세대를 보존하고 후보 평문을 정리한다.
*/
func runtimeActivate(c config, target string) (resultErr error) {
	if _, err := livePath(c); err != nil {
		return err
	}
	generation, err := os.MkdirTemp(c.runtime, "generation-")
	if err != nil {
		return err
	}
	if err = os.Remove(generation); err != nil {
		return err
	}
	if err = os.Rename(target, generation); err != nil {
		return err
	}
	link := filepath.Join(c.runtime, ".next")
	var activated bool
	defer func() {
		if !activated {
			cleanupPath(&resultErr, generation)
		}
	}()
	if exists(link) {
		return errors.New("stale activation link; run harness config runtime reset after stopping agents")
	}
	if err = os.Symlink(generation, link); err != nil {
		return err
	}
	if err = os.Rename(link, filepath.Join(c.runtime, "skills")); err != nil {
		cleanupPath(&err, link)
		return err
	}
	activated = true
	return runtimeCleanup(c, generation)
}
func runtimeCleanup(c config, keep string) error {
	entries, err := os.ReadDir(c.runtime)
	if err != nil {
		return err
	}
	for _, e := range entries {
		p := filepath.Join(c.runtime, e.Name())
		if p == keep || !strings.HasPrefix(e.Name(), "generation-") {
			continue
		}
		if err = os.RemoveAll(p); err != nil {
			return err
		}
	}
	return nil
}

/*
관리되는 임시 후보와 Runtime만 삭제한다.
암호문, 편집본, 키 및 이관 백업은 삭제하지 않는다.
*/
func purge(c config) error {
	if err := stageCleanup(c); err != nil {
		return err
	}
	if !exists(c.runtime) {
		return nil
	}
	if err := privateDir(c.runtime); err != nil {
		return err
	}
	if _, err := managedRuntimeLink(c); err != nil {
		return err
	}
	for _, name := range []string{"skills", ".next"} {
		if err := os.Remove(filepath.Join(c.runtime, name)); err != nil && !os.IsNotExist(err) {
			return err
		}
	}
	return runtimeCleanup(c, "")
}

// 상태 조회는 키 생성, 상태 바인딩, 디렉터리 생성 없이 실행한다.
func status(c config) error {
	if err := existingPrivateDir(c.state); err != nil {
		return err
	}
	if err := existingPrivateDir(c.runtime); err != nil {
		return err
	}
	live, err := livePath(c)
	if err != nil {
		return err
	}
	fmt.Printf("archive=%t workspace=%t runtime=%t key=%t\n",
		exists(c.archive), exists(c.workspace), live != "", exists(c.key))
	fmt.Println("Vault:", c.archive)
	fmt.Println("Workspace:", c.workspace)
	fmt.Println("Runtime:", filepath.Join(c.runtime, "skills"))
	if exists(filepath.Join(c.state, "legacy-backup")) {
		fmt.Println("Legacy backup (plaintext):", filepath.Join(c.state, "legacy-backup"))
	}
	if exists(filepath.Join(c.repo, "capability")) || exists(filepath.Join(c.repo, ".runtime")) {
		fmt.Println("ACTION: move legacy plaintext outside checkout manually")
	}
	sources, err := sourcesRead(c)
	if err != nil {
		return err
	}
	names := make([]string, 0, len(sources))
	for name := range sources {
		names = append(names, name)
	}
	sort.Strings(names)
	for _, name := range names {
		fmt.Printf("source=%s pinned=%t\n", name, sources[name].valid())
	}
	return nil
}

// 설치 파일과 그래프를 직접 비교한다. 기본 출력은 민감한 ID를 숨기고 건수만 제공한다.
type changeDetail struct {
	ID     string `json:"id"`
	Action string `json:"action"`
}
type changeSet struct {
	Added, Removed, Modified int
	Details                  []changeDetail
}

func inventory(path string) (map[string]string, error) {
	result := map[string]string{}
	if path == "" {
		return result, nil
	}
	entries, err := os.ReadDir(path)
	if err != nil {
		return nil, err
	}
	b, err := readRegular(filepath.Join(path, ".capability-graph.json"))
	if err != nil {
		return nil, err
	}
	var graph struct {
		Capabilities map[string]node `json:"capabilities"`
	}
	if err = json.Unmarshal(b, &graph); err != nil {
		return nil, err
	}
	for id, n := range graph.Capabilities {
		data, err := json.Marshal(n)
		if err != nil {
			return nil, err
		}
		result[id] = hashBytes(data)
	}
	for _, entry := range entries {
		if entry.Name() == ".capability-graph.json" || entry.Name() == ".capability" {
			continue
		}
		if !entry.IsDir() {
			return nil, errors.New("unexpected runtime entry")
		}
		h, err := digest(filepath.Join(path, entry.Name()))
		if err != nil {
			return nil, err
		}
		result[entry.Name()] = result[entry.Name()] + h
	}
	return result, nil
}

func runtimeDiff(actual, desired string) (changeSet, error) {
	var changes changeSet
	a, err := inventory(actual)
	if err != nil {
		return changes, err
	}
	d, err := inventory(desired)
	if err != nil {
		return changes, err
	}
	for id, v := range d {
		old, ok := a[id]
		if !ok {
			changes.Added++
			changes.Details = append(changes.Details, changeDetail{id, "added"})
			continue
		}
		if v != old {
			changes.Modified++
			changes.Details = append(changes.Details, changeDetail{id, "modified"})
		}
	}
	for id := range a {
		if _, ok := d[id]; !ok {
			changes.Removed++
			changes.Details = append(changes.Details, changeDetail{id, "removed"})
		}
	}
	sort.Slice(changes.Details, func(i, j int) bool { return changes.Details[i].ID < changes.Details[j].ID })
	return changes, nil
}
