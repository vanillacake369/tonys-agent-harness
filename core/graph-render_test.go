package core

import (
	"bytes"
	"encoding/json"
	"strings"
	"testing"
)

func TestGraphRelations(t *testing.T) {
	nodes := map[string]node{
		"a": {Kind: "agent", Requires: []string{"s"}},
		"s": {Kind: "skill", Requires: []string{"t"}},
		"t": {Kind: "tool"},
	}
	must(t, relationsValidate(nodes))
	nodes["t"] = node{Kind: "tool", Requires: []string{"a"}}
	if relationsValidate(nodes) == nil {
		t.Fatal("wrong relation type accepted")
	}
	nodes = map[string]node{"a": {Kind: "agent", Requires: []string{"b"}}, "b": {Kind: "agent", Hints: []string{"a"}}}
	if relationsValidate(nodes) == nil {
		t.Fatal("cycle accepted")
	}
	nodes = map[string]node{"a": {Kind: "agent", Requires: []string{"missing"}}}
	if relationsValidate(nodes) == nil {
		t.Fatal("missing reference accepted")
	}
}

func TestRelationTypesRejectSyntheticKinds(t *testing.T) {
	nodes := map[string]node{
		"reviewer":   {Kind: "agent", Requires: []string{"unexpected"}},
		"unexpected": {Kind: "tool skill"},
	}
	if relationsValidate(nodes) == nil {
		t.Fatal("synthetic combined capability kind accepted")
	}
}

func TestV17GraphRender(t *testing.T) {
	nodes := map[string]node{
		"a": {Kind: "agent", Requires: []string{"b"}, Hints: []string{"c"}},
		"b": {Kind: "skill", Requires: []string{"c"}},
		"c": {Kind: "tool"},
	}
	must(t, relationsValidate(nodes))
	opts, err := graphRequest(GraphRequest{Target: "tool/c", Reverse: true, Depth: 1, Format: "json"})
	must(t, err)
	view, err := graphBuild(nodes, opts)
	must(t, err)
	if len(view.Nodes) != 3 || len(view.Edges) != 3 {
		t.Fatalf("unexpected graph: %+v", view)
	}
	var b bytes.Buffer
	must(t, graphRender(&b, view, opts))
	var parsed graphView
	must(t, json.Unmarshal(b.Bytes(), &parsed))
	if parsed.Version != 1 || parsed.Scope != "local_desired" {
		t.Fatal("unexpected graph schema")
	}
	b.Reset()
	opts.format = "dot"
	must(t, graphRender(&b, view, opts))
	if !strings.Contains(b.String(), `"agent/a" -> "tool/c" [label="hints"]`) {
		t.Fatal(b.String())
	}
	if _, err = graphRequest(GraphRequest{Format: "xml", Depth: -1}); err == nil {
		t.Fatal("invalid format accepted")
	}
	opts.target = "agent/a"
	opts.reverse = false
	opts.depth = 0
	view, err = graphBuild(nodes, opts)
	must(t, err)
	if len(view.Nodes) != 1 || len(view.Edges) != 0 {
		t.Fatal("depth zero ignored")
	}
}

func TestGraphRelationFilter(t *testing.T) {
	nodes := map[string]node{
		"a": {Kind: "agent", Requires: []string{"b"}, Hints: []string{"c"}},
		"b": {Kind: "skill", Requires: []string{"c"}}, "c": {Kind: "tool"},
	}
	opts, err := graphRequest(GraphRequest{Target: "agent/a", Relation: "hints", Depth: -1})
	must(t, err)
	view, err := graphBuild(nodes, opts)
	must(t, err)
	if len(view.Nodes) != 2 || len(view.Edges) != 1 || view.Edges[0].Type != "hints" {
		t.Fatal("wrong graph scope")
	}
}

func TestTreeIndentation(t *testing.T) {
	nodes := map[string]node{
		"a": {Kind: "agent", Hints: []string{"b"}},
		"b": {Kind: "skill", Hints: []string{"c"}},
		"c": {Kind: "tool"},
	}
	opts, err := graphRequest(GraphRequest{Target: "agent/a", Depth: -1})
	must(t, err)
	view, err := graphBuild(nodes, opts)
	must(t, err)
	var b bytes.Buffer
	must(t, graphRender(&b, view, opts))
	if !strings.Contains(b.String(), "└── skill/b [hints]\n    └── tool/c [hints]") {
		t.Fatal(b.String())
	}
}
