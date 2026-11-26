package core

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestScaffoldSkillPreservesExistingTarget(t *testing.T) {
	app := NewApplication()
	root, err := filepath.EvalSymlinks(t.TempDir())
	must(t, err)
	path, err := app.ScaffoldSkill("skill/skl-mid-milestone-cycle-vpplab", root)
	must(t, err)
	if path != filepath.Join(root, "skl-mid-milestone-cycle-vpplab") {
		t.Fatalf("unexpected scaffold path: %s", path)
	}
	doc := filepath.Join(path, "SKILL.md")
	put(t, doc, "existing content")
	if _, err := app.ScaffoldSkill("skill/skl-mid-milestone-cycle-vpplab", root); !os.IsExist(err) {
		t.Fatalf("expected collision error, got %v", err)
	}
	actual, err := os.ReadFile(doc)
	must(t, err)
	if string(actual) != "existing content" {
		t.Fatal("scaffold overwrote the existing skill")
	}
	if _, err := app.ScaffoldSkill("skill/../escape", root); err == nil {
		t.Fatal("scaffold accepted traversal")
	}
}

func TestScaffoldSkillRejectsNonconformingIDs(t *testing.T) {
	app := NewApplication()
	root := t.TempDir()
	for _, id := range []string{"milestone-cycle", "skl-mid-vpplab", "skl-plan-cycle-vpplab", "skl-mid-cycle"} {
		if _, err := app.ScaffoldSkill("skill/"+id, root); err == nil {
			t.Errorf("scaffold accepted %q", id)
		}
		if exists(filepath.Join(root, id)) {
			t.Errorf("scaffold created a directory for %q", id)
		}
	}
}

func TestSkillAuthoringIntegration(t *testing.T) {
	integrationOnly(t)
	if exec.Command("python3", "-c", "import yaml").Run() != nil {
		t.Skip("missing Python with PyYAML")
	}
	for _, tool := range []string{"bash", "jq", "realpath"} {
		if _, err := exec.LookPath(tool); err != nil {
			t.Skip("missing " + tool)
		}
	}
	root := t.TempDir()
	t.Setenv("HARNESS_REPO", "..")
	t.Setenv("HARNESS_STATE", filepath.Join(root, "unused-state"))
	app := NewApplication()
	path, err := app.ScaffoldSkill("skill/skl-pre-example-ljh", root)
	must(t, err)
	must(t, app.ValidateSkill(path))

	docPath := filepath.Join(path, "SKILL.md")
	doc, err := os.ReadFile(docPath)
	must(t, err)
	put(t, docPath, strings.ReplaceAll(string(doc), "  behavior: not-verified\n", ""))
	if err := app.ValidateSkill(path); err == nil || !strings.Contains(err.Error(), "metadata validation") {
		t.Fatalf("expected missing behavior to fail metadata validation, got %v", err)
	}
	put(t, docPath, strings.ReplaceAll(string(doc), "\"hints\": []", "\"hints\": null"))
	if err := app.ValidateSkill(path); err == nil || !strings.Contains(err.Error(), "composition") {
		t.Fatalf("expected invalid composition to fail validation, got %v", err)
	}
	if exists(filepath.Join(root, "unused-state")) {
		t.Fatal("skill authoring initialized Harness state")
	}
}
