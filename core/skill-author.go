package core

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
)

var authoredSkillID = regexp.MustCompile(`^skl-(pre|mid|post)-[a-z0-9]+(-[a-z0-9]+)*-(ljh|vpplab)$`)

/*
초안은 사용자가 지정한 디렉터리에만 생성한다.
디렉터리 생성으로 ID를 예약해 기존 파일과 링크를 보호한다.
*/
func (Application) ScaffoldSkill(target, output string) (path string, resultErr error) {
	id, ok := strings.CutPrefix(target, "skill/")
	if !ok || !idValid(id) {
		return "", errors.New("expected skill/<id> with a valid capability ID")
	}
	if !authoredSkillID.MatchString(id) {
		return "", errors.New("new skill IDs must follow skl-{pre|mid|post}-<purpose>-{ljh|vpplab}")
	}
	if output == "" {
		return "", errors.New("an output directory is required")
	}
	root, err := filepath.EvalSymlinks(output)
	if err != nil {
		return "", err
	}
	path = filepath.Join(root, id)
	if err = os.Mkdir(path, 0700); err != nil {
		return "", err
	}
	created := path
	defer func() {
		if resultErr != nil {
			cleanupPath(&resultErr, created)
		}
	}()
	if err = writeSkillDraft(path, id); err != nil {
		return "", err
	}
	return path, nil
}

func writeSkillDraft(path, id string) error {
	words := strings.Split(id, "-")
	for i, word := range words {
		words[i] = strings.ToUpper(word[:1]) + word[1:]
	}
	display := "Skill / " + strings.Join(words, " ")
	doc := fmt.Sprintf("---\nname: %s\ndescription: Describe when this skill applies.\n"+
		"metadata:\n  kind: skill\n  behavior: not-verified\n---\n\n# %s\n\n"+
		"Describe the workflow and expected outcome.\n\n", id, display)
	doc += "```json composition\n{\"requires\": [], \"hints\": []}\n```\n"
	if err := os.WriteFile(filepath.Join(path, "SKILL.md"), []byte(doc), 0600); err != nil {
		return err
	}
	agents := filepath.Join(path, "agents")
	if err := os.Mkdir(agents, 0700); err != nil {
		return err
	}
	ui := fmt.Sprintf("interface:\n  display_name: %q\n  short_description: %q\n  default_prompt: %q\n",
		display, "Describe the skill's intended outcome", "Use $"+id+" to complete the intended workflow.")
	return os.WriteFile(filepath.Join(agents, "openai.yaml"), []byte(ui), 0600)
}

/*
단일 Skill 검증은 신뢰된 체크아웃의 검증기만 실행한다.
Vault나 Runtime을 열지 않고 후보 디렉터리만 읽는다.
*/
func (Application) ValidateSkill(path string) error {
	cwd, err := os.Getwd()
	if err != nil {
		return err
	}
	repo, err := repositoryRoot(cwd)
	if err != nil {
		return err
	}
	if !exists(filepath.Join(repo, "core/environment-public.txt")) {
		return errors.New("validator requires a Harness checkout; use --repo")
	}
	path, err = filepath.Abs(path)
	if err != nil {
		return err
	}
	for _, tool := range []string{"bash", "jq", "python3", "realpath"} {
		if _, err = exec.LookPath(tool); err != nil {
			return fmt.Errorf("skill validation requires %s on PATH", tool)
		}
	}
	if _, err = run("python3", "-c", "import yaml"); err != nil {
		return errors.New("skill validation requires Python 3 with PyYAML")
	}
	if _, err = run("bash", filepath.Join(repo, "core/skill-validate.sh"), path); err != nil {
		return errors.New("skill structure validation failed; check frontmatter, links, and files")
	}
	metadata := filepath.Join(repo, "core/metadata-validate.py")
	if _, err = run("python3", metadata, "skill", path); err != nil {
		return errors.New("v2.1 skill metadata validation failed; check kind, behavior, title and agents/openai.yaml")
	}
	doc, err := readRegular(filepath.Join(path, "SKILL.md"))
	if err != nil {
		return err
	}
	_, err = compositionRead(doc, 1)
	return err
}
