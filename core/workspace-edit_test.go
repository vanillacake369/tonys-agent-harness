package core

import (
	"path/filepath"
	"testing"
)

func TestV17EditorTarget(t *testing.T) {
	c := fixtureConfig(t)
	fixtureTree(t, c.workspace)
	path, err := editorTarget(c, "agent/reviewer")
	must(t, err)
	if path != filepath.Join(c.workspace, "agent/reviewer.md") {
		t.Fatal(path)
	}
	if _, err = editorTarget(c, "skill/../fixture"); err == nil {
		t.Fatal("unsafe target accepted")
	}
}

func TestEditorFallback(t *testing.T) {
	t.Setenv("VISUAL", "/nonexistent-editor")
	t.Setenv("EDITOR", "sh")
	path, err := editorExecutable()
	must(t, err)
	if path == "" {
		t.Fatal("no fallback")
	}
}
