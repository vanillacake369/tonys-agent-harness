package core

import (
	"os"
	"testing"
)

func TestStateBindingAndLock(t *testing.T) {
	c := fixtureConfig(t)
	must(t, bindState(c))
	must(t, bindState(c))
	other := c
	other.archive += ".other"
	if bindState(other) == nil {
		t.Fatal("state reused across vaults")
	}
	first, err := operationLock(c)
	must(t, err)
	defer first.Close()
	second, err := operationLock(c)
	if err == nil {
		second.Close()
		t.Fatal("concurrent lock accepted")
	}
}

// 상태 조회가 최초 설치 전에도 파일을 생성하지 않는지 확인한다.
func TestStatusReadOnly(t *testing.T) {
	c := fixtureConfig(t)
	must(t, os.RemoveAll(c.state))
	must(t, status(c))
	if exists(c.state) {
		t.Fatal("status created state")
	}
}

func TestV18StatusReportReadOnly(t *testing.T) {
	c := fixtureConfig(t)
	must(t, os.RemoveAll(c.state))
	t.Setenv("HOME", temp(t))
	r, err := readStatus(c)
	must(t, err)
	if r.ArchiveExists || r.WorkspaceExists || r.RuntimeExists || exists(c.state) {
		t.Fatal("status created or misreported state")
	}
	if r.SchemaVersion != 1 || len(r.Providers) != 3 {
		t.Fatal("unexpected status contract")
	}
}

func TestRepositoryDiscovery(t *testing.T) {
	c := fixtureConfig(t)
	t.Setenv("HARNESS_REPO", "")
	root, err := repositoryRoot(c.repo + "/source")
	must(t, err)
	if root != c.repo {
		t.Fatal(root)
	}
	t.Setenv("HARNESS_REPO", c.repo)
	root, err = repositoryRoot(temp(t))
	must(t, err)
	if root != c.repo {
		t.Fatal(root)
	}
}

func BenchmarkReadStatus(b *testing.B) {
	c := fixtureConfig(b)
	b.Setenv("HOME", temp(b))
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		if _, err := readStatus(c); err != nil {
			b.Fatal(err)
		}
	}
}
