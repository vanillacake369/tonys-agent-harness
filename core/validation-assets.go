package core

import (
	"embed"
	"io"
	"os"
	"os/exec"
	"path/filepath"
)

//go:embed skill-validate.sh dag-validate.sh dag-contract.schema.json tool-contract-validate.sh metadata-validate.py
var validatorAssets embed.FS

// 배포 작업의 전용 임시 디렉터리에 빌드에 포함된 검증기를 푼다.
func prepareValidators(c *config, stage string) error {
	if c.validatorDir != "" {
		return nil
	}
	path := filepath.Join(stage, "validators")
	if err := os.Mkdir(path, 0700); err != nil {
		return err
	}
	entries, err := validatorAssets.ReadDir(".")
	if err != nil {
		return err
	}
	for _, entry := range entries {
		data, err := validatorAssets.ReadFile(entry.Name())
		if err != nil {
			return err
		}
		if err = os.WriteFile(filepath.Join(path, entry.Name()), data, 0600); err != nil {
			return err
		}
	}
	c.validatorDir = path
	return nil
}

func validatorRun(c config, interpreter, name string, args ...string) error {
	return validatorStart(c, interpreter, name, nil, args...)
}

func validatorStart(c config, interpreter, name string, output io.Writer, args ...string) (resultErr error) {
	if c.validatorDir == "" {
		stage, err := os.MkdirTemp(c.state, "stage-validator-")
		if err != nil {
			return err
		}
		defer cleanupPath(&resultErr, stage)
		if err = prepareValidators(&c, stage); err != nil {
			return err
		}
	}
	cmd := exec.Command(interpreter, append([]string{filepath.Join(c.validatorDir, name)}, args...)...)
	cmd.Dir = c.validatorDir
	cmd.Stdout = output
	cmd.Env = append(os.Environ(), "TMPDIR="+c.validatorDir, "BASH_ENV=/dev/null")
	return cmd.Run()
}
