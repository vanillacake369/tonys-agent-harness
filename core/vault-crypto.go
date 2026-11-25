package core

import (
	"archive/tar"
	"bytes"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
)

const maxArchive = 128 << 20

// 임시 평문 삭제 실패를 성공으로 숨기지 않는다.
// 경로를 출력하지 않고 기존 실패와 정리 실패를 함께 보존한다.
func cleanupPath(resultErr *error, path string) {
	if err := os.RemoveAll(path); err != nil {
		*resultErr = errors.Join(*resultErr, errors.New("temporary data cleanup failed; inspect local state"))
	}
}

// 링크와 특수 파일을 허용하지 않는다. 실행 비트만 보존한다.
func treeWalk(root string, visit func(string, fs.FileInfo) error) error {
	return filepath.Walk(root, func(path string, info fs.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if info.IsDir() {
			return visit(path, info)
		}
		if !info.Mode().IsRegular() || info.Sys().(*syscall.Stat_t).Nlink != 1 {
			return errors.New("unsafe tree entry")
		}
		return visit(path, info)
	})
}

// 메타데이터의 시간과 소유권을 제거해 동일 트리에서 동일한 digest를 얻는다.
func pack(root string) ([]byte, error) {
	var b bytes.Buffer
	w := tar.NewWriter(&b)
	err := treeWalk(root, func(path string, info fs.FileInfo) error {
		if path == root && !info.IsDir() {
			return errors.New("tree root not directory")
		}
		if path == root {
			return nil
		}
		rel, err := filepath.Rel(root, path)
		if err != nil {
			return err
		}
		h := &tar.Header{Name: filepath.ToSlash(rel), Mode: 0600, Typeflag: tar.TypeReg, Size: info.Size()}
		if info.IsDir() {
			h.Typeflag = tar.TypeDir
			h.Mode = 0700
			h.Size = 0
		}
		if info.Mode()&0100 != 0 {
			h.Mode = 0700
		}
		if h.Size > maxArchive || int64(b.Len())+h.Size > maxArchive {
			return errors.New("archive too large")
		}
		if err = w.WriteHeader(h); err != nil {
			return err
		}
		if info.IsDir() {
			return nil
		}
		f, err := os.Open(path)
		if err != nil {
			return err
		}
		defer f.Close()
		_, err = io.Copy(w, f)
		return err
	})
	if err != nil {
		return nil, err
	}
	if err = w.Close(); err != nil {
		return nil, err
	}
	if b.Len() > maxArchive {
		return nil, errors.New("archive too large")
	}
	return b.Bytes(), nil
}

func safeRelative(name string) bool {
	return name != "" && name != "." && !filepath.IsAbs(name) && filepath.Clean(name) == name &&
		!strings.HasPrefix(name, "../") && name != ".." && !strings.Contains(name, "\\")
}

// 새 디렉터리에만 추출하며 중복 및 경로 탈출을 거부한다.
func unpack(data []byte, root string) error {
	return unpackArchive(data, root, "")
}

func unpackGitArchive(data []byte, root, revision string) error {
	return unpackArchive(data, root, revision)
}

func unpackArchive(data []byte, root, revision string) error {
	if len(data) > maxArchive {
		return errors.New("archive too large")
	}
	r := tar.NewReader(bytes.NewReader(data))
	seen := map[string]bool{}
	globalSeen := false
	for {
		h, err := r.Next()
		if err == io.EOF {
			return nil
		}
		if err != nil {
			return err
		}
		isGlobal, metaErr := gitArchiveMetadata(h, revision, globalSeen || len(seen) != 0)
		if metaErr != nil {
			return metaErr
		}
		if isGlobal {
			globalSeen = true
			continue
		}
		name := strings.TrimSuffix(h.Name, "/")
		if !safeRelative(name) || seen[name] {
			return errors.New("unsafe archive path")
		}
		seen[name] = true
		if err = archiveEntry(r, h, filepath.Join(root, name)); err != nil {
			return err
		}
	}
}

func gitArchiveMetadata(h *tar.Header, revision string, seen bool) (bool, error) {
	if h.Typeflag != tar.TypeXGlobalHeader {
		return false, nil
	}
	if revision == "" || seen || len(h.PAXRecords) != 1 || h.PAXRecords["comment"] != revision {
		return false, errors.New("unsafe archive metadata")
	}
	return true, nil
}

// 허용된 일반 파일과 디렉터리만 사용자 전용 권한으로 생성한다.
// 링크 타입 및 이미 존재하는 파일은 생성하지 않는다.
func archiveEntry(r io.Reader, h *tar.Header, path string) error {
	if h.Typeflag == tar.TypeDir {
		return os.MkdirAll(path, 0700)
	}
	if h.Typeflag != tar.TypeReg && h.Typeflag != tar.TypeRegA {
		return errors.New("unsafe archive type")
	}
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		return err
	}
	mode := os.FileMode(0600)
	if h.Mode&0100 != 0 {
		mode = 0700
	}
	f, err := os.OpenFile(path, os.O_CREATE|os.O_EXCL|os.O_WRONLY, mode)
	if err != nil {
		return err
	}
	_, err = io.Copy(f, r)
	closeErr := f.Close()
	if err != nil {
		return err
	}
	return closeErr
}

func keyValidate(c config) error {
	info, err := os.Lstat(c.key)
	if err != nil {
		return errors.New("restore or generate age identity")
	}
	real, err := filepath.EvalSymlinks(c.key)
	if err != nil {
		return err
	}
	isOwned := info.Sys().(*syscall.Stat_t).Uid == uint32(os.Getuid())
	if !info.Mode().IsRegular() || info.Mode().Perm() != 0600 || real != c.key || !isOwned ||
		info.Sys().(*syscall.Stat_t).Nlink != 1 {
		return errors.New("unsafe age identity")
	}
	return nil
}

// 암호문이 승인된 단일 age recipient만 사용하도록 제한한다.
// 외부 KMS/PGP 키 서비스 요청이나 평문 필드를 허용하지 않는다.
func cipherValidate(data []byte, recipient string) error {
	var envelope struct {
		Data string                     `json:"data"`
		SOPS map[string]json.RawMessage `json:"sops"`
	}
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&envelope); err != nil {
		return errors.New("invalid ciphertext envelope")
	}
	if err := decoder.Decode(new(any)); err != io.EOF {
		return errors.New("invalid trailing ciphertext")
	}
	if !strings.HasPrefix(envelope.Data, "ENC[AES256_GCM,") {
		return errors.New("plaintext or invalid envelope")
	}
	for k, v := range envelope.SOPS {
		switch k {
		case "age", "lastmodified", "mac", "version", "unencrypted_suffix":
		case "kms", "gcp_kms", "azure_kv", "hc_vault", "pgp":
			if string(v) != "[]" && string(v) != "null" {
				return errors.New("non-age key service refused")
			}
		default:
			return errors.New("unsupported SOPS metadata")
		}
	}
	var keys []struct {
		Recipient string `json:"recipient"`
		Enc       string `json:"enc"`
	}
	if err := json.Unmarshal(envelope.SOPS["age"], &keys); err != nil {
		return errors.New("invalid recipient metadata")
	}
	if len(keys) != 1 || keys[0].Recipient != recipient || keys[0].Enc == "" {
		return errors.New("ciphertext recipient mismatch")
	}
	return nil
}

/*
공식 SOPS CLI를 고정 경계로 사용한다. 평문 tar는 디스크에 기록하지 않는다.
별도 임시 정책으로 외부 설정 파일의 암호화 규칙 상속을 차단한다.
*/
func sopsRun(c config, data []byte, encrypt bool) (_ []byte, resultErr error) {
	if err := keyValidate(c); err != nil {
		return nil, err
	}
	public, err := run("age-keygen", "-y", c.key)
	if err != nil {
		return nil, err
	}
	recipient := strings.TrimSpace(string(public))
	if !strings.HasPrefix(recipient, "age1") || strings.ContainsAny(recipient, " \r\n,\t") {
		return nil, errors.New("expected a single native age identity")
	}
	policy, err := os.CreateTemp(c.state, "sops-policy-*.yaml")
	if err != nil {
		return nil, err
	}
	defer cleanupPath(&resultErr, policy.Name())
	_, err = fmt.Fprintf(policy, "creation_rules:\n  - age: %s\n", recipient)
	closeErr := policy.Close()
	if err != nil {
		return nil, err
	}
	if closeErr != nil {
		return nil, closeErr
	}
	args := []string{"--config", policy.Name(), "decrypt", "--input-type", "json", "--output-type", "binary"}
	if encrypt {
		args = []string{
			"--config", policy.Name(), "encrypt", "--filename-override", "capability.enc",
			"--input-type", "binary", "--output-type", "json",
		}
	} else if err = cipherValidate(data, recipient); err != nil {
		return nil, err
	}
	cmd := exec.Command("sops", args...)
	cmd.Env = []string{"PATH=" + os.Getenv("PATH"), "SOPS_AGE_KEY_FILE=" + c.key, "HOME=" + c.state,
		"XDG_CONFIG_HOME=" + c.state}
	cmd.Dir = c.state
	cmd.Stdin = bytes.NewReader(data)
	out, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("sops operation failed: %w", err)
	}
	if encrypt {
		if err = cipherValidate(out, recipient); err != nil {
			return nil, err
		}
	}
	return out, nil
}

func readRegular(path string) ([]byte, error) {
	info, err := os.Lstat(path)
	if err != nil {
		return nil, err
	}
	if !info.Mode().IsRegular() || info.Sys().(*syscall.Stat_t).Nlink != 1 || info.Size() > maxArchive*2 {
		return nil, errors.New("unsafe input file")
	}
	return os.ReadFile(path)
}

func decrypt(c config, root string) error {
	cipher, err := readRegular(c.archive)
	if err != nil {
		return err
	}
	plain, err := sopsRun(c, cipher, false)
	if err != nil {
		return err
	}
	return unpack(plain, root)
}

// 같은 파일시스템에서 검증된 결과를 교체한다. 기존 링크는 덮어쓰지 않는다.
func atomicWrite(path string, data []byte) (resultErr error) {
	parent, err := filepath.EvalSymlinks(filepath.Dir(path))
	if err != nil {
		return err
	}
	if parent != filepath.Dir(path) {
		return errors.New("symlink output parent")
	}
	if exists(path) {
		if _, err := readRegular(path); err != nil {
			return err
		}
	}
	f, err := os.CreateTemp(filepath.Dir(path), ".sealed-")
	if err != nil {
		return err
	}
	defer cleanupPath(&resultErr, f.Name())
	_, err = f.Write(data)
	if err == nil {
		err = f.Sync()
	}
	closeErr := f.Close()
	if err != nil {
		return err
	}
	if closeErr != nil {
		return closeErr
	}
	if err = os.Rename(f.Name(), path); err != nil {
		return err
	}
	dir, err := os.Open(filepath.Dir(path))
	if err != nil {
		return err
	}
	defer dir.Close()
	return dir.Sync()
}

/*
후보 암호문을 실제 복호화하여 원본과 비교한다.
검증을 통과한 후보만 기존 암호문을 원자적으로 교체한다.
*/
func seal(c config, plain []byte) error {
	cipher, err := sopsRun(c, plain, true)
	if err != nil {
		return err
	}
	restored, err := sopsRun(c, cipher, false)
	if err != nil {
		return err
	}
	if !bytes.Equal(plain, restored) {
		return errors.New("round-trip mismatch")
	}
	return atomicWrite(c.archive, cipher)
}

func digest(root string) (string, error) {
	b, err := pack(root)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("%x", sha256.Sum256(b)), nil
}

func copyTree(from, to string) error {
	b, err := pack(from)
	if err != nil {
		return err
	}
	if err = os.Mkdir(to, 0700); err != nil {
		return err
	}
	return unpack(b, to)
}

// 기존 키를 덮어쓰지 않는다. 사용자가 직접 키의 백업을 관리한다.
func keyGenerate(c config) error {
	if exists(c.key) {
		return keyValidate(c)
	}
	if err := privateDir(filepath.Dir(c.key)); err != nil {
		return err
	}
	if _, err := run("age-keygen", "-o", c.key); err != nil {
		return err
	}
	return keyValidate(c)
}
