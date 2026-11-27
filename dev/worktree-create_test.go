package dev

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestWorktreeCreate(t *testing.T) {
	parent, err := filepath.EvalSymlinks(t.TempDir())
	must(t, err)
	main := filepath.Join(parent, "main")
	must(t, os.Mkdir(main, 0700))
	git := func(dir string, args ...string) string {
		t.Helper()
		cmd := exec.Command("git", append([]string{"-C", dir}, args...)...)
		out, err := cmd.CombinedOutput()
		if err != nil {
			t.Fatalf("git %v: %v\n%s", args, err, out)
		}
		return strings.TrimSpace(string(out))
	}
	git(main, "init", "-b", "main")
	must(t, os.Mkdir(filepath.Join(main, "dev"), 0700))
	script := filepath.Join(main, "dev", "worktree-create.sh")
	code, err := os.ReadFile("worktree-create.sh")
	must(t, err)
	must(t, os.WriteFile(script, code, 0600))
	file := filepath.Join(main, "tracked")
	must(t, os.WriteFile(file, []byte("main\n"), 0600))
	git(main, "add", ".")
	git(main, "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-m", "main")
	base := git(main, "rev-parse", "main")
	must(t, os.WriteFile(file, []byte("working edit\n"), 0600))

	create := func(script, name string, success bool) string {
		t.Helper()
		cmd := exec.Command("sh", script, name)
		var stderr bytes.Buffer
		cmd.Stderr = &stderr
		out, err := cmd.Output()
		if (err == nil) != success {
			t.Fatalf("worktree %q: %v\n%s%s", name, err, out, stderr.String())
		}
		return strings.TrimSpace(string(out))
	}
	first := filepath.Join(parent, "first")
	if got := create(script, "first", true); got != first {
		t.Fatalf("returned %q, want %q", got, first)
	}
	if git(first, "branch", "--show-current") != "codex/first" || git(first, "rev-parse", "HEAD") != base {
		t.Fatal("worktree has the wrong branch or base")
	}
	data, err := os.ReadFile(file)
	must(t, err)
	if string(data) != "working edit\n" {
		t.Fatal("main worktree edit was changed")
	}

	second := filepath.Join(parent, "second")
	if got := create(filepath.Join(first, "dev", "worktree-create.sh"), "second", true); got != second {
		t.Fatalf("linked worktree returned %q, want %q", got, second)
	}
	create(script, "first", false)
	create(script, "../escape", false)
	must(t, os.Mkdir(filepath.Join(parent, "occupied"), 0700))
	create(script, "occupied", false)
	must(t, os.Symlink(filepath.Join(parent, "missing"), filepath.Join(parent, "linked")))
	create(script, "linked", false)
	git(main, "branch", "codex/taken", "main")
	create(script, "taken", false)
	if _, err := os.Lstat(filepath.Join(parent, "taken")); !os.IsNotExist(err) {
		t.Fatalf("failed creation left a destination: %v", err)
	}
}
