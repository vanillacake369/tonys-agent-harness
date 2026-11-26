package cli

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/spf13/cobra"
)

func commandCompletion() *cobra.Command {
	return &cobra.Command{
		Use:       "completion [bash|zsh|fish]",
		Short:     "Install shell completion for harness",
		Args:      cobra.MaximumNArgs(1),
		ValidArgs: []string{"bash", "zsh", "fish"},
		RunE: func(cmd *cobra.Command, args []string) error {
			shell := filepath.Base(os.Getenv("SHELL"))
			if len(args) == 1 {
				shell = args[0]
			}
			return installCompletion(cmd, shell)
		},
	}
}

func installCompletion(cmd *cobra.Command, shell string) error {
	root := cmd.Root()
	var generate func(io.Writer) error
	switch shell {
	case "bash":
		generate = func(w io.Writer) error { return root.GenBashCompletionV2(w, true) }
	case "zsh":
		generate = root.GenZshCompletion
	case "fish":
		generate = func(w io.Writer) error { return root.GenFishCompletion(w, true) }
	default:
		return fmt.Errorf("unsupported shell %q; specify bash, zsh, or fish", shell)
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return err
	}
	// macOS에서도 셸의 XDG 경로 규칙에 맞춰 설치한다.
	configDir := os.Getenv("XDG_CONFIG_HOME")
	if !filepath.IsAbs(configDir) {
		configDir = filepath.Join(home, ".config")
	}
	path := filepath.Join(configDir, "tonys-agent-harness", "completion."+shell)
	if shell == "fish" {
		path = filepath.Join(configDir, "fish", "completions", "harness.fish")
	}
	if err := writeCompletion(path, generate); err != nil {
		return err
	}
	if err := registerCompletion(shell, home, path); err != nil {
		return err
	}
	cmd.Printf("Installed %s completion at %s. Start a new shell to use it.\n", shell, path)
	return nil
}

/*
완성된 스크립트만 공개한다. 생성에 실패하면 이전 자동완성 파일을 보존한다.
*/
func writeCompletion(path string, generate func(io.Writer) error) error {
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0700); err != nil {
		return err
	}
	file, err := os.CreateTemp(dir, ".completion-*")
	if err != nil {
		return err
	}
	defer os.Remove(file.Name())
	genErr := generate(file)
	closeErr := file.Close()
	if genErr != nil {
		return genErr
	}
	if closeErr != nil {
		return closeErr
	}
	return os.Rename(file.Name(), path)
}

func registerCompletion(shell, home, path string) error {
	quoted := "'" + strings.ReplaceAll(path, "'", "'\\''") + "'"
	load := "if [ -r " + quoted + " ]; then\n  . " + quoted + "\nfi"
	switch shell {
	case "zsh":
		dir := os.Getenv("ZDOTDIR")
		if dir == "" {
			dir = home
		}
		load = "if [ -r " + quoted + " ]; then\n" +
			"  if ! (( $+functions[compdef] )); then autoload -Uz compinit && compinit; fi\n" +
			"  . " + quoted + "\nfi"
		return appendCompletion(filepath.Join(dir, ".zshrc"), load)
	case "bash":
		if err := appendCompletion(filepath.Join(home, ".bashrc"), load); err != nil {
			return err
		}
		login, err := bashLoginProfile(home)
		if err != nil {
			return err
		}
		load = "if [ -n \"${BASH_VERSION:-}\" ] && [ -r " + quoted + " ]; then\n  . " + quoted + "\nfi"
		return appendCompletion(login, load)
	}
	return nil
}

func bashLoginProfile(home string) (string, error) {
	for _, name := range []string{".bash_profile", ".bash_login", ".profile"} {
		path := filepath.Join(home, name)
		_, err := os.Stat(path)
		if err == nil {
			return path, nil
		}
		if !os.IsNotExist(err) {
			return "", err
		}
	}
	return filepath.Join(home, ".bash_profile"), nil
}

func appendCompletion(path, load string) error {
	const marker = "# harness shell completion"
	content, err := os.ReadFile(path)
	if err != nil && !os.IsNotExist(err) {
		return err
	}
	if strings.Contains("\n"+string(content), "\n"+marker+"\n") {
		return nil
	}
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		return err
	}
	file, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_APPEND, 0600)
	if err != nil {
		return err
	}
	_, writeErr := io.WriteString(file, "\n"+marker+"\n"+load+"\n")
	closeErr := file.Close()
	if writeErr != nil {
		return writeErr
	}
	return closeErr
}
