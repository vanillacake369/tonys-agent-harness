package dev

import (
	"bufio"
	"bytes"
	"go/ast"
	"go/format"
	"go/parser"
	"go/token"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"unicode/utf8"
)

// 운영 Go 코드의 너비와 함수 인자 수를 검증한다.
// 표준 라이브러리만 사용해 별도 린터 설치가 필요하지 않게 한다.
func TestArchitecture(t *testing.T) {
	files := goFiles(t)
	for _, name := range files {
		t.Run(name, func(t *testing.T) {
			checkWidth(t, name)
			if strings.HasSuffix(name, "_test.go") {
				return
			}
			checkSyntax(t, name)
		})
	}
}

func TestArchitectureSourceWidth(t *testing.T) {
	for _, pattern := range sourceWidthPatterns() {
		files, err := filepath.Glob(pattern)
		must(t, err)
		for _, name := range files {
			checkSourceWidth(t, name)
		}
	}
}

func TestArchitectureSourceWidthIncludesRootNix(t *testing.T) {
	for _, pattern := range sourceWidthPatterns() {
		if pattern == "../*.nix" {
			return
		}
	}
	t.Fatal("root Nix files are not covered by the width check")
}

func goFiles(t *testing.T) []string {
	t.Helper()
	var result []string
	for _, pattern := range []string{"../*.go", "../core/*.go", "../cli/*.go", "../config/*.go",
		"../source/*.go", "../provider/*.go", "../dev/*.go"} {
		files, err := filepath.Glob(pattern)
		must(t, err)
		result = append(result, files...)
	}
	return result
}

func sourceWidthPatterns() []string {
	return []string{
		"../*.go", "../*.nix", "../justfile", "../core/*.go", "../core/*.sh",
		"../cli/*.go", "../config/*.go", "../source/*.go", "../source/*.nix",
		"../provider/*.go", "../provider/*.nix", "../dev/*.go", "../dev/*.sh", "../dev/*.justfile",
	}
}

func must(t *testing.T, err error) {
	t.Helper()
	if err != nil {
		t.Fatal(err)
	}
}

func checkWidth(t *testing.T, name string) {
	data, err := os.ReadFile(name)
	must(t, err)
	formatted, err := format.Source(data)
	must(t, err)
	if !bytes.Equal(data, formatted) {
		t.Errorf("%s is not gofmt formatted", name)
	}
	checkSourceWidth(t, name)
}

func checkSourceWidth(t *testing.T, name string) {
	data, err := os.ReadFile(name)
	must(t, err)
	scanner := bufio.NewScanner(strings.NewReader(string(data)))
	line := 0
	for scanner.Scan() {
		line++
		text := strings.ReplaceAll(scanner.Text(), "\t", "    ")
		if utf8.RuneCountInString(text) > 120 {
			t.Errorf("%s:%d exceeds 120 columns", name, line)
		}
	}
	must(t, scanner.Err())
}

func checkSyntax(t *testing.T, name string) {
	data, err := os.ReadFile(name)
	must(t, err)
	set := token.NewFileSet()
	file, err := parser.ParseFile(set, name, nil, parser.ParseComments)
	must(t, err)
	ast.Inspect(file, func(n ast.Node) bool {
		fn, ok := n.(*ast.FuncDecl)
		if !ok {
			return true
		}
		if parameterCount(fn.Type.Params) > 5 {
			t.Errorf("%s: %s has more than five parameters", set.Position(fn.Pos()), fn.Name.Name)
		}
		if coreFunction(fn.Name.Name) && !hasCoreBlockComment(data, set, fn) {
			t.Errorf("%s: %s needs a multiline C-style intent comment", set.Position(fn.Pos()), fn.Name.Name)
		}
		ast.Walk(controlDepth{t: t, set: set}, fn.Body)
		return false
	})
}

func hasCoreBlockComment(data []byte, set *token.FileSet, fn *ast.FuncDecl) bool {
	if fn.Doc == nil {
		return false
	}
	position := set.Position(fn.Doc.Pos())
	end := set.Position(fn.Doc.End())
	comment := string(data[position.Offset:end.Offset])
	return strings.HasPrefix(comment, "/*") && strings.Contains(comment, "\n")
}

func parameterCount(fields *ast.FieldList) int {
	if fields == nil {
		return 0
	}
	count := 0
	for _, field := range fields.List {
		count += max(1, len(field.Names))
	}
	return count
}

func coreFunction(name string) bool {
	switch name {
	case "setup", "reconcile", "lockCommit", "seal", "sopsRun",
		"runtimeActivate", "purge", "withState", "copyPublicFiles", "Unlock":
		return true
	default:
		return false
	}
}

// if/for/range의 실제 중첩만 센다. 함수 리터럴은 독립된 실행 범위로 본다.
// switch와 일반 블록은 사용자 규칙의 for/if 깊이에 포함하지 않는다.
type controlDepth struct {
	t     *testing.T
	set   *token.FileSet
	depth int
}

func (v controlDepth) Visit(n ast.Node) ast.Visitor {
	switch n.(type) {
	case nil:
		return nil
	case *ast.FuncLit:
		v.depth = 0
	case *ast.IfStmt, *ast.ForStmt, *ast.RangeStmt:
		v.depth++
	}
	if v.depth > 2 {
		v.t.Errorf("%s: control nesting exceeds two", v.set.Position(n.Pos()))
		return nil
	}
	return v
}

// 직접 관리하는 Go 코드만 평탄하게 유지한다. 공개 fixture의 패키지 구조는 예외다.
func TestArchitectureLayout(t *testing.T) {
	for _, name := range []string{"core", "cli", "config", "source", "provider", "dev"} {
		entries, err := os.ReadDir(filepath.Join("..", name))
		must(t, err)
		for _, entry := range entries {
			if entry.IsDir() && entry.Name() != "testdata" {
				t.Errorf("module %s must remain flat: %s", name, entry.Name())
			}
		}
	}
}

// 공개 Go 소스가 새로 추가되면 Nix build allowlist도 명시적으로 갱신해야 한다.
func TestPublicManifestCompleteness(t *testing.T) {
	data, err := os.ReadFile("../core/environment-public.txt")
	must(t, err)
	entries := map[string]bool{}
	for _, name := range strings.Fields(string(data)) {
		if entries[name] {
			t.Fatalf("duplicate public path: %s", name)
		}
		entries[name] = true
		info, err := os.Lstat(filepath.Join("..", name))
		must(t, err)
		if !info.Mode().IsRegular() {
			t.Fatalf("unsafe public file: %s", name)
		}
	}
	for _, name := range goFiles(t) {
		if !entries[strings.TrimPrefix(name, "../")] {
			t.Errorf("missing public Go file: %s", name)
		}
	}
}
