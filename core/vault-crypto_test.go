package core

import (
	"archive/tar"
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// 실제 사용자 자료 없이 파일 내용과 실행 권한의 왕복을 확인한다.
func TestArchiveRoundTrip(t *testing.T) {
	root := temp(t)
	a := filepath.Join(root, "a")
	must(t, os.Mkdir(a, 0700))
	put(t, filepath.Join(a, "skill/run.sh"), "#!/bin/sh\nexit 0\n")
	must(t, os.Chmod(filepath.Join(a, "skill/run.sh"), 0700))
	put(t, filepath.Join(a, "skill/SKILL.md"), "fixture")
	b, err := pack(a)
	must(t, err)
	restored := filepath.Join(root, "b")
	must(t, os.Mkdir(restored, 0700))
	must(t, unpack(b, restored))
	after, err := pack(restored)
	must(t, err)
	if !bytes.Equal(b, after) {
		t.Fatal("archive changed on round trip")
	}
	info, err := os.Stat(filepath.Join(restored, "skill/run.sh"))
	must(t, err)
	if info.Mode().Perm() != 0700 {
		t.Fatal("executable mode lost")
	}
}

func TestUnsafeArchives(t *testing.T) {
	cases := []struct {
		name      string
		kind      byte
		duplicate bool
	}{
		{"../escape", tar.TypeReg, false}, {"/absolute", tar.TypeReg, false}, {"a/../escape", tar.TypeReg, false},
		{"link", tar.TypeSymlink, false}, {"hard", tar.TypeLink, false}, {"pipe", tar.TypeFifo, false},
		{"duplicate", tar.TypeReg, true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			var b bytes.Buffer
			w := tar.NewWriter(&b)
			h := &tar.Header{Name: tc.name, Typeflag: tc.kind, Mode: 0600, Linkname: "target"}
			must(t, w.WriteHeader(h))
			if tc.duplicate {
				must(t, w.WriteHeader(h))
			}
			must(t, w.Close())
			if unpack(b.Bytes(), temp(t)) == nil {
				t.Fatal("unsafe archive accepted")
			}
		})
	}
}

func TestTreeRejectsLinks(t *testing.T) {
	root := temp(t)
	put(t, filepath.Join(root, "a"), "fixture")
	must(t, os.Symlink("a", filepath.Join(root, "b")))
	if _, err := pack(root); err == nil {
		t.Fatal("symlink accepted")
	}
	must(t, os.Remove(filepath.Join(root, "b")))
	must(t, os.Link(filepath.Join(root, "a"), filepath.Join(root, "b")))
	if _, err := pack(root); err == nil {
		t.Fatal("hardlink accepted")
	}
}

func TestCipherPolicy(t *testing.T) {
	good := `{"data":"ENC[AES256_GCM,test]","sops":{"age":[{"recipient":"age1fixture","enc":"test"}],"kms":[]}}`
	must(t, cipherValidate([]byte(good), "age1fixture"))
	bad := []string{
		strings.Replace(good, "age1fixture", "age1wrong", 1),
		strings.Replace(good, `"kms":[]`, `"kms":[{}]`, 1),
		strings.Replace(good, "ENC[AES256_GCM,test]", "plaintext", 1),
		strings.Replace(good, `"kms":[]`, `"key_groups":[{}]`, 1),
		good + ` {}`,
	}
	for _, data := range bad {
		if cipherValidate([]byte(data), "age1fixture") == nil {
			t.Fatal("invalid policy accepted")
		}
	}
}

// 실제 SOPS 및 age가 설치된 환경에서만 실행한다. 모의 암호화로 성공을 주장하지 않는다.
func TestSOPSIntegration(t *testing.T) {
	integrationOnly(t)
	for _, name := range []string{"sops", "age-keygen"} {
		if _, err := exec.LookPath(name); err != nil {
			t.Skip("missing " + name)
		}
	}
	c := fixtureConfig(t)
	must(t, os.Remove(c.key))
	_, err := run("age-keygen", "-o", c.key)
	must(t, err)
	must(t, os.Chmod(c.key, 0600))
	fixtureTree(t, c.workspace)
	must(t, reconcile(c, "lock"))
	before, err := readRegular(c.archive)
	must(t, err)
	if exists(c.workspace) {
		t.Fatal("workspace retained after lock")
	}
	must(t, reconcile(c, "unlock"))
	must(t, reconcile(c, "sync"))
	if exists(c.workspace) {
		t.Fatal("sync did not close workspace")
	}
	after, err := readRegular(c.archive)
	must(t, err)
	if !bytes.Equal(before, after) {
		t.Fatal("unchanged lock rewrote ciphertext")
	}
	must(t, reconcile(c, "plan"))
	must(t, reconcile(c, "sync"))
	live, err := livePath(c)
	must(t, err)
	must(t, reconcile(c, "sync"))
	again, err := livePath(c)
	must(t, err)
	if live != again {
		t.Fatal("unchanged sync redeployed")
	}
	wrong := c
	wrong.key = filepath.Join(filepath.Dir(c.key), "wrong-key")
	_, err = run("age-keygen", "-o", wrong.key)
	must(t, err)
	must(t, os.Chmod(wrong.key, 0600))
	if reconcile(wrong, "unlock") == nil {
		t.Fatal("wrong key accepted")
	}
	if exists(c.workspace) {
		t.Fatal("failed decrypt exposed workspace")
	}
	must(t, os.WriteFile(c.archive, []byte("tampered"), 0600))
	if reconcile(c, "sync") == nil {
		t.Fatal("tampered archive accepted")
	}
	current, err := livePath(c)
	must(t, err)
	if current != live {
		t.Fatal("failed sync changed live generation")
	}
}

func TestGitArchiveGlobalCommitHeader(t *testing.T) {
	var b bytes.Buffer
	w := tar.NewWriter(&b)
	sha := strings.Repeat("a", 40)
	must(t, w.WriteHeader(&tar.Header{Typeflag: tar.TypeXGlobalHeader, Name: "pax_global_header",
		PAXRecords: map[string]string{"comment": sha}}))
	must(t, w.WriteHeader(&tar.Header{Name: "skill/SKILL.md", Mode: 0600, Size: 1}))
	_, err := w.Write([]byte("x"))
	must(t, err)
	must(t, w.Close())
	if err := unpackGitArchive(b.Bytes(), temp(t), sha); err != nil {
		t.Fatal(err)
	}
	if err := unpack(b.Bytes(), temp(t)); err == nil {
		t.Fatal("vault accepted global header")
	}
	if err := unpackGitArchive(b.Bytes(), temp(t), strings.Repeat("b", 40)); err == nil {
		t.Fatal("wrong commit accepted")
	}
}
