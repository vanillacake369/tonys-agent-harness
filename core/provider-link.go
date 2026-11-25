package core

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

type providerStateValue string

const (
	providerBlocked           providerStateValue = "BLOCKED"
	providerConnected         providerStateValue = "CONNECTED"
	providerConflict          providerStateValue = "CONFLICT"
	providerDisabled          providerStateValue = "DISABLED"
	providerDrifted           providerStateValue = "DRIFTED"
	providerMigrationRequired providerStateValue = "MIGRATION_REQUIRED"
)

type providerOwnership uint8

const (
	providerUnmanaged providerOwnership = iota
	providerCurrent
	providerPrior
)

var providerStateIDPattern = regexp.MustCompile(`^[0-9a-f]{16}$`)

type providerDefinition struct {
	Name       string `json:"name"`
	SkillsPath string `json:"skills_path"`
	Default    bool   `json:"default,omitempty"`
}

type providerCatalog struct {
	Providers []providerDefinition `json:"providers"`
}

/*
Provider 이름과 사용자 경로는 공개 카탈로그 한 곳에서 읽는다.
중복, 경로 이탈, 기본 Provider 누락은 링크를 계산하기 전에 거부한다.
*/
func providerDefinitions(c config) ([]providerDefinition, error) {
	b, err := readRegular(filepath.Join(c.repo, "provider/provider-catalog.json"))
	if err != nil {
		return nil, err
	}
	var catalog providerCatalog
	if err = json.Unmarshal(b, &catalog); err != nil {
		return nil, errors.New("invalid provider catalog")
	}
	seen := map[string]bool{}
	defaults := 0
	for _, provider := range catalog.Providers {
		invalid := !idValid(provider.Name) || seen[provider.Name] || !providerPathValid(provider.SkillsPath)
		if invalid {
			return nil, errors.New("invalid provider catalog")
		}
		seen[provider.Name] = true
		if provider.Default {
			defaults++
		}
	}
	if len(catalog.Providers) == 0 || defaults != 1 {
		return nil, errors.New("invalid provider catalog")
	}
	return catalog.Providers, nil
}

func providerPathValid(path string) bool {
	return safeRelative(path) && strings.HasPrefix(path, ".") && strings.Contains(path, "/")
}

func providerNames(c config) ([]string, string, error) {
	providers, err := providerDefinitions(c)
	if err != nil {
		return nil, "", err
	}
	names := make([]string, 0, len(providers))
	var defaultName string
	for _, provider := range providers {
		names = append(names, provider.Name)
		if provider.Default {
			defaultName = provider.Name
		}
	}
	return names, defaultName, nil
}

func providerDefinitionRead(c config, name string) (providerDefinition, error) {
	providers, err := providerDefinitions(c)
	if err != nil {
		return providerDefinition{}, err
	}
	for _, provider := range providers {
		if provider.Name == name {
			return provider, nil
		}
	}
	return providerDefinition{}, errors.New("unknown provider")
}

func providerLink(c config, name string) (string, error) {
	provider, err := providerDefinitionRead(c, name)
	if err != nil {
		return "", err
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(home, provider.SkillsPath), nil
}
func providerMarker(c config, name string) string { return filepath.Join(c.state, "provider-"+name) }
func providerApproved(c config, name string) (bool, error) {
	path := providerMarker(c, name)
	if !exists(path) {
		return false, nil
	}
	b, err := readRegular(path)
	if err != nil {
		return false, err
	}
	if string(b) != "approved\n" {
		return false, errors.New("invalid provider approval")
	}
	return true, nil
}
func providerSafeDir(path string) error {
	real, err := filepath.EvalSymlinks(path)
	if err != nil {
		return err
	}
	info, err := os.Lstat(path)
	if err != nil {
		return err
	}
	if real != path || !info.IsDir() {
		return errors.New("unsafe provider directory")
	}
	return nil
}
func providerIDs(root string) ([]string, error) {
	if root == "" {
		return nil, errors.New("runtime missing")
	}
	entries, err := os.ReadDir(root)
	if err != nil {
		return nil, err
	}
	var ids []string
	for _, e := range entries {
		if e.IsDir() && !strings.HasPrefix(e.Name(), ".") {
			ids = append(ids, e.Name())
		}
	}
	return ids, nil
}
func providerOwned(c config, path string) bool {
	return providerOwnershipRead(c, path) == providerCurrent
}
func providerOwnershipRead(c config, path string) providerOwnership {
	target, err := os.Readlink(path)
	if err != nil {
		return providerUnmanaged
	}
	current := filepath.Join(c.runtime, "skills", filepath.Base(path))
	if target == current {
		return providerCurrent
	}
	if providerPriorTarget(c, path, target) {
		return providerPrior
	}
	return providerUnmanaged
}
func providerPriorTarget(c config, path, target string) bool {
	if !filepath.IsAbs(target) || filepath.Clean(target) != target {
		return false
	}
	relative, err := filepath.Rel(filepath.Dir(c.state), target)
	if err != nil {
		return false
	}
	parts := strings.Split(filepath.ToSlash(relative), "/")
	return len(parts) == 4 && providerStateIDPattern.MatchString(parts[0]) &&
		parts[1] == "runtime" && parts[2] == "skills" && parts[3] == filepath.Base(path) &&
		parts[0] != filepath.Base(c.state)
}
func providerLegacy(c config, link string) bool {
	legacy, _ := providerLegacyKind(c, link)
	return legacy
}
func providerLegacyKind(c config, link string) (bool, bool) {
	target, err := os.Readlink(link)
	legacy := err == nil && target == filepath.Join(c.runtime, "skills")
	return legacy, os.IsNotExist(err)
}
func providerState(c config, name string) (providerStateValue, error) {
	link, err := providerLink(c, name)
	if err != nil {
		return "", err
	}
	approved, err := providerApproved(c, name)
	if err != nil {
		return "", err
	}
	legacy, missing := providerLegacyKind(c, link)
	if !approved && !legacy {
		if missing {
			return providerDisabled, nil
		}
		migration, migrationErr := providerMigrationPending(c, link)
		if migrationErr != nil {
			return "", migrationErr
		}
		if !migration {
			return providerDisabled, nil
		}
		live, liveErr := livePath(c)
		if liveErr != nil || live == "" {
			return providerBlocked, nil
		}
		state, inspectErr := providerInspect(c, link, live)
		if inspectErr != nil || state == providerConflict {
			return state, inspectErr
		}
		return providerMigrationRequired, nil
	}
	live, err := livePath(c)
	if err != nil || live == "" {
		return providerBlocked, nil
	}
	if legacy {
		if providerSafeDir(filepath.Dir(link)) != nil {
			return providerConflict, nil
		}
		return providerConnected, nil
	}
	state, err := providerInspect(c, link, live)
	return state, err
}
func providerMigrationPending(c config, link string) (bool, error) {
	if !exists(link) {
		return false, nil
	}
	if err := providerSafeDir(link); err != nil {
		return false, nil
	}
	entries, err := os.ReadDir(link)
	if err != nil {
		return false, err
	}
	for _, entry := range entries {
		if providerOwnershipRead(c, filepath.Join(link, entry.Name())) == providerPrior {
			return true, nil
		}
	}
	return false, nil
}
func providerInspect(c config, link, root string) (providerStateValue, error) {
	if !exists(link) {
		return providerDrifted, nil
	}
	if providerSafeDir(link) != nil {
		return providerConflict, nil
	}
	ids, err := providerIDs(root)
	if err != nil {
		return "", err
	}
	state := providerConnected
	for _, id := range ids {
		path := filepath.Join(link, id)
		if !exists(path) {
			state = providerDrifted
			continue
		}
		switch providerOwnershipRead(c, path) {
		case providerCurrent:
		case providerPrior:
			state = providerDrifted
		default:
			return providerConflict, nil
		}
	}
	stale, err := providerStale(c, link, ids)
	if err != nil {
		return "", err
	}
	if len(stale) > 0 {
		state = providerDrifted
	}
	return state, nil
}
func providerStale(c config, link string, ids []string) ([]string, error) {
	wanted := map[string]bool{}
	for _, id := range ids {
		wanted[id] = true
	}
	entries, err := os.ReadDir(link)
	if err != nil {
		return nil, err
	}
	var stale []string
	for _, e := range entries {
		p := filepath.Join(link, e.Name())
		managed := providerOwnershipRead(c, p) != providerUnmanaged
		if !wanted[e.Name()] && managed {
			stale = append(stale, p)
		}
	}
	return stale, nil
}

/*
기존 Provider 디렉터리를 보존하고 현재 Runtime을 가리키는 링크만 관리한다.
동일 ID 충돌은 어떤 링크도 변경하기 전에 검사한다.
*/
func connect(c config, args []string) error {
	if len(args) != 1 {
		return errors.New("provider name required")
	}
	name := args[0]
	live, err := livePath(c)
	if err != nil || live == "" {
		return errors.New("run harness config apply first")
	}
	link, err := providerLink(c, name)
	if err != nil {
		return err
	}
	if err = providerPrepare(c, link, live); err != nil {
		return err
	}
	if err = atomicWrite(providerMarker(c, name), []byte("approved\n")); err != nil {
		return err
	}
	if err = providerReconcile(c, []string{link}); err != nil {
		return err
	}
	fmt.Println("CONNECTED:", name)
	return nil
}
func providerPrepare(c config, link, root string) error {
	parent := filepath.Dir(link)
	if exists(parent) {
		if err := providerSafeDir(parent); err != nil {
			return err
		}
	} else if err := providerSafeDir(filepath.Dir(parent)); err != nil {
		return err
	}
	if providerLegacy(c, link) {
		return providerSafeDir(filepath.Dir(link))
	}
	state, err := providerInspect(c, link, root)
	if err != nil {
		return err
	}
	if state == providerConflict {
		return fmt.Errorf("provider %s conflict; inspect existing skill links and resolve manually",
			filepath.Base(filepath.Dir(link)))
	}
	return nil
}
func providerApply(c config, link, root string) error {
	if err := providerPrepare(c, link, root); err != nil {
		return err
	}
	if providerLegacy(c, link) {
		return nil
	}
	if err := os.MkdirAll(filepath.Dir(link), 0700); err != nil {
		return err
	}
	if err := providerSafeDir(filepath.Dir(link)); err != nil {
		return err
	}
	if err := os.MkdirAll(link, 0700); err != nil {
		return err
	}
	if err := providerSafeDir(link); err != nil {
		return err
	}
	ids, err := providerIDs(root)
	if err != nil {
		return err
	}
	for _, id := range ids {
		if err = providerAdd(c, link, id); err != nil {
			return err
		}
	}
	stale, err := providerStale(c, link, ids)
	if err != nil {
		return err
	}
	for _, path := range stale {
		if err = providerRemove(c, path); err != nil {
			return err
		}
	}
	return nil
}
func providerAdd(c config, link, id string) error {
	path := filepath.Join(link, id)
	ownership := providerOwnershipRead(c, path)
	if ownership == providerCurrent {
		return nil
	}
	if ownership == providerPrior {
		return providerReplace(c, path, id)
	}
	return os.Symlink(filepath.Join(c.runtime, "skills", id), path)
}
func providerReplace(c config, path, id string) (resultErr error) {
	dir, err := os.MkdirTemp(filepath.Dir(path), ".harness-link-")
	if err != nil {
		return err
	}
	defer cleanupPath(&resultErr, dir)
	next := filepath.Join(dir, id)
	if err = os.Symlink(filepath.Join(c.runtime, "skills", id), next); err != nil {
		return err
	}
	if providerOwnershipRead(c, path) != providerPrior {
		return errors.New("provider ownership changed")
	}
	return os.Rename(next, path)
}
func providerRemove(c config, path string) error {
	if providerOwnershipRead(c, path) == providerUnmanaged {
		return errors.New("provider ownership changed")
	}
	return os.Remove(path)
}
func providerTargets(c config) ([]string, error) {
	providers, err := providerDefinitions(c)
	if err != nil {
		return nil, err
	}
	var links []string
	for _, provider := range providers {
		link, err := providerLink(c, provider.Name)
		if err != nil {
			return nil, err
		}
		approved, err := providerApproved(c, provider.Name)
		if err != nil {
			return nil, err
		}
		if approved || providerLegacy(c, link) {
			links = append(links, link)
		}
	}
	return links, nil
}
func providerPreflight(c config, root string) ([]string, error) {
	links, err := providerTargets(c)
	if err != nil {
		return nil, err
	}
	for _, link := range links {
		if err = providerPrepare(c, link, root); err != nil {
			return nil, err
		}
	}
	return links, nil
}
func providerReconcile(c config, links []string) error {
	if len(links) == 0 {
		return nil
	}
	live, err := livePath(c)
	if err != nil {
		return err
	}
	for _, link := range links {
		if err = providerApply(c, link, live); err != nil {
			return err
		}
		state, err := providerInspectAfter(c, link, live)
		if err != nil {
			return err
		}
		if state != providerConnected {
			return errors.New("provider reconciliation incomplete; retry harness config apply")
		}
	}
	return nil
}
func providerInspectAfter(c config, link, root string) (providerStateValue, error) {
	if providerLegacy(c, link) {
		return providerConnected, providerSafeDir(filepath.Dir(link))
	}
	return providerInspect(c, link, root)
}

/*
승인된 연결만 해제한다. 외부 파일과 디렉터리는 제거하지 않는다.
*/
func providerDisconnect(c config, name string) error {
	link, err := providerLink(c, name)
	if err != nil {
		return err
	}
	approved, err := providerApproved(c, name)
	if err != nil {
		return err
	}
	if err = providerDetach(c, link, approved); err != nil {
		return err
	}
	err = os.Remove(providerMarker(c, name))
	if os.IsNotExist(err) {
		return nil
	}
	return err
}
func providerDetach(c config, link string, approved bool) error {
	if providerLegacy(c, link) {
		if err := providerSafeDir(filepath.Dir(link)); err != nil {
			return err
		}
		return os.Remove(link)
	}
	if !exists(link) {
		return nil
	}
	if !approved {
		return errors.New("unmanaged provider path")
	}
	if err := providerSafeDir(link); err != nil {
		return err
	}
	stale, err := providerStale(c, link, nil)
	if err != nil {
		return err
	}
	for _, path := range stale {
		if err = providerRemove(c, path); err != nil {
			return err
		}
	}
	return nil
}

func providerChanges(c config, links []string, root string) (bool, error) {
	for _, link := range links {
		state, err := providerInspectAfter(c, link, root)
		if err != nil {
			return false, err
		}
		if state != providerConnected {
			return true, nil
		}
	}
	return false, nil
}

func Connect(name string) error {
	return withState(false, func(c config) error {
		if _, err := providerDefinitionRead(c, name); err != nil {
			return err
		}
		return connect(c, []string{name})
	})
}

func Disconnect(name string) error {
	return withState(false, func(c config) error {
		if _, err := providerDefinitionRead(c, name); err != nil {
			return err
		}
		return providerDisconnect(c, name)
	})
}

func ReadProviders(name string) ([]ProviderStatus, error) {
	c, err := loadConfig()
	if err != nil {
		return nil, err
	}
	if name != "" {
		if _, err = providerDefinitionRead(c, name); err != nil {
			return nil, err
		}
	}
	return providerStatusRows(c, name)
}

func ProviderNames() ([]string, error) {
	c, err := loadConfig()
	if err != nil {
		return nil, err
	}
	names, _, err := providerNames(c)
	return names, err
}
