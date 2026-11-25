package core

import (
	"errors"
	"path/filepath"
)

/*
모든 변경 작업은 동일한 OS 잠금과 Vault 바인딩을 사용한다.
초기화 진입점도 구버전 평문을 자동 이동하지 않는다.
*/
func withState(allowLegacy bool, fn func(config) error) (resultErr error) {
	c, err := loadConfig()
	if err != nil {
		return err
	}
	var hasLegacy = exists(filepath.Join(c.repo, "capability")) || exists(filepath.Join(c.repo, ".runtime"))
	if hasLegacy && !allowLegacy {
		return errors.New("legacy plaintext; move outside checkout manually")
	}
	lock, err := operationLock(c)
	if err != nil {
		return err
	}
	defer func() { resultErr = errors.Join(resultErr, lock.Close()) }()
	if err = bindState(c); err != nil {
		return err
	}
	return fn(c)
}
