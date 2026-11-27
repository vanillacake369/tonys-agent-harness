package dev

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestWorktreeCreate(t *testing.T) {
	// GIVEN a primary checkout with a local main branch.
	root, err := filepath.EvalSymlinks(t.TempDir())
	must(t, err)
	parent := filepath.Join(root, "project")
	main := filepath.Join(parent, "main")
	must(t, os.MkdirAll(main, 0700))
	git := func(t *testing.T, dir string, args ...string) string {
		t.Helper()
		flags := []string{"-C", dir, "-c", "core.hooksPath=/dev/null", "-c", "commit.gpgsign=false"}
		cmd := exec.Command("git", append(flags, args...)...)
		out, err := cmd.CombinedOutput()
		if err != nil {
			t.Fatalf("git %v: %v\n%s", args, err, out)
		}
		return strings.TrimSpace(string(out))
	}
	git(t, main, "init", "-b", "main")
	must(t, os.Mkdir(filepath.Join(main, "dev"), 0700))
	script := filepath.Join(main, "dev", "worktree-create.sh")
	code, err := os.ReadFile("worktree-create.sh")
	must(t, err)
	must(t, os.WriteFile(script, code, 0600))
	file := filepath.Join(main, "tracked")
	must(t, os.WriteFile(file, []byte("main\n"), 0600))
	git(t, main, "add", ".")
	git(t, main, "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-m", "main")
	base := git(t, main, "rev-parse", "main")
	create := func(script, name string) (string, error) {
		out, err := exec.Command("sh", script, name).Output()
		return strings.TrimSpace(string(out)), err
	}

	t.Run("from a primary checkout", func(t *testing.T) {
		// GIVEN a tracked file has an uncommitted edit in the primary checkout.
		must(t, os.WriteFile(file, []byte("working edit\n"), 0600))
		want := filepath.Join(parent, "first")

		// WHEN a sibling worktree is created.
		got, err := create(script, "first")

		// THEN the new branch starts at main and the primary edit is preserved.
		must(t, err)
		if got != want {
			t.Fatalf("returned %q, want %q", got, want)
		}
		if git(t, got, "branch", "--show-current") != "codex/first" || git(t, got, "rev-parse", "HEAD") != base {
			t.Fatal("worktree has the wrong branch or base")
		}
		data, err := os.ReadFile(file)
		must(t, err)
		if string(data) != "working edit\n" {
			t.Fatal("main worktree edit was changed")
		}
	})

	t.Run("from a linked worktree", func(t *testing.T) {
		// GIVEN an existing linked worktree.
		linked := filepath.Join(parent, "origin")
		git(t, main, "worktree", "add", "-b", "codex/origin", linked, "main")
		want := filepath.Join(parent, "second")

		// WHEN the tool runs from the linked worktree.
		got, err := create(filepath.Join(linked, "dev", "worktree-create.sh"), "second")

		// THEN it places the new worktree beside the primary checkout.
		must(t, err)
		if got != want {
			t.Fatalf("returned %q, want %q", got, want)
		}
	})

	for _, tc := range []struct {
		caseName, name string
		prepare        func(*testing.T, string)
		wantExists     bool
	}{
		{
			caseName: "existing worktree", name: "registered", wantExists: true,
			prepare: func(t *testing.T, path string) {
				git(t, main, "worktree", "add", "-b", "codex/registered", path, "main")
			},
		},
		{caseName: "path outside sibling directory", name: "../escape"},
		{
			caseName: "occupied directory", name: "occupied", wantExists: true,
			prepare: func(t *testing.T, path string) { must(t, os.Mkdir(path, 0700)) },
		},
		{
			caseName: "symbolic link", name: "linked", wantExists: true,
			prepare: func(t *testing.T, path string) {
				must(t, os.Symlink(filepath.Join(parent, "missing"), path))
			},
		},
		{
			caseName: "existing branch", name: "taken",
			prepare: func(t *testing.T, _ string) { git(t, main, "branch", "codex/taken", "main") },
		},
	} {
		t.Run(tc.caseName, func(t *testing.T) {
			// GIVEN this case's path or branch condition.
			target := filepath.Join(parent, tc.name)
			if tc.prepare != nil {
				tc.prepare(t, target)
			}

			// WHEN worktree creation is attempted.
			_, err := create(script, tc.name)

			// THEN creation fails and the destination's existence is preserved.
			if err == nil {
				t.Fatalf("worktree %q unexpectedly created", tc.name)
			}
			_, statErr := os.Lstat(target)
			if tc.wantExists && statErr != nil || !tc.wantExists && !os.IsNotExist(statErr) {
				t.Fatalf("rejected creation changed the destination: %v", statErr)
			}
		})
	}
}
