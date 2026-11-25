package core

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

/*
명시적 대상은 파일 경계를 검증하고, 대화형 선택은 fzf에 위임한다.
fzf가 없으면 기존 편집기 디렉터리 탐색을 사용한다.
*/
func editorTarget(c config, target string) (string, error) {
	if target == "" {
		selected, err := editorSelect(c)
		if err != nil || selected == "" || selected == c.workspace {
			return selected, err
		}
		target = selected
	}
	if !targetValid(target) {
		return "", errors.New("invalid capability target")
	}
	kind, id, _ := strings.Cut(target, "/")
	path := filepath.Join(c.workspace, kind, id, "SKILL.md")
	if kind == "agent" {
		path = filepath.Join(c.workspace, kind, id+".md")
	}
	real, err := filepath.EvalSymlinks(path)
	if err != nil || real != path {
		return "", errors.New("unsafe or missing editor target")
	}
	if _, err := readRegular(path); err != nil {
		return "", err
	}
	return path, nil
}

func editorIDs(root string) ([]string, error) {
	var ids []string
	for _, kind := range []string{"agent", "dag", "skill", "tool"} {
		entries, err := os.ReadDir(filepath.Join(root, kind))
		if err != nil {
			return nil, err
		}
		for _, entry := range entries {
			id := strings.TrimSuffix(entry.Name(), ".md")
			ids = append(ids, kind+"/"+id)
		}
	}
	return ids, nil
}

func editorSelect(c config) (string, error) {
	if !terminalInput() {
		return "", errors.New("non-interactive edit requires kind/id")
	}
	fzf, err := exec.LookPath("fzf")
	if err != nil {
		return c.workspace, nil
	}
	ids, err := editorIDs(c.workspace)
	if err != nil {
		return "", err
	}
	if len(ids) == 0 {
		return c.workspace, nil
	}
	cmd := exec.Command(fzf, "--prompt=Capability> ", "--no-multi")
	cmd.Stdin = strings.NewReader(strings.Join(ids, "\n"))
	cmd.Stderr = os.Stderr
	out, err := cmd.Output()
	if err != nil {
		var exit *exec.ExitError
		if errors.As(err, &exit) && exit.ExitCode() == 130 {
			return "", nil
		}
		return "", errors.New("fzf selection failed; workspace retained")
	}
	return strings.TrimSpace(string(out)), nil
}

/*
편집기를 실행하는 동안 기존 작업 잠금을 유지한다.
자동 저장이나 배포 없이 평문 작업 공간을 보존한다.
*/
func Unlock(mode string) error {
	if mode != "" && mode != "--edit" && mode != "--path" {
		return errors.New("unknown workspace open option")
	}
	var editor string
	if mode == "--edit" {
		if !terminalInput() {
			return errors.New("workspace open --edit requires a terminal")
		}
		var err error
		editor, err = editorExecutable()
		if err != nil {
			return err
		}
	}
	return withInitializedState(func(c config) error { return unlockWorkspace(c, mode, editor) })
}

func editorExecutable() (string, error) {
	for _, name := range []string{os.Getenv("VISUAL"), os.Getenv("EDITOR"), "nvim", "vim", "vi"} {
		if name == "" {
			continue
		}
		path, err := exec.LookPath(name)
		if err == nil {
			return path, nil
		}
	}
	return "", errors.New("editor unavailable")
}

func unlockWorkspace(c config, mode, editor string) error {
	if err := reconcileWithOptions(c, "unlock", false, mode != "", false); err != nil {
		return err
	}
	if mode == "--path" {
		fmt.Println(c.workspace)
	}
	if mode == "--edit" {
		cmd := exec.Command(editor, c.workspace)
		cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stdout, os.Stderr
		if err := cmd.Run(); err != nil {
			return errors.New("editor failed; workspace retained")
		}
	}
	return nil
}
