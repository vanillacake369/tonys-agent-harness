package core

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"path/filepath"
	"sort"
	"strings"
)

type graphOptions struct {
	target, format, relation string
	reverse                  bool
	depth                    int
}
type graphNode struct {
	ID   string `json:"id"`
	Kind string `json:"kind"`
}
type graphEdge struct {
	From string `json:"from"`
	To   string `json:"to"`
	Type string `json:"type"`
}
type graphView struct {
	Version int         `json:"schema_version"`
	Scope   string      `json:"scope"`
	Nodes   []graphNode `json:"nodes"`
	Edges   []graphEdge `json:"edges"`
}

type GraphRequest struct {
	Target, Format, Relation string
	Reverse                  bool
	Depth                    int // -1 means unlimited
}

func graphRequest(req GraphRequest) (graphOptions, error) {
	if req.Format == "" {
		req.Format = "tree"
	}
	o := graphOptions{
		target: req.Target, format: req.Format, relation: req.Relation,
		reverse: req.Reverse, depth: req.Depth,
	}
	if req.Format != "tree" && req.Format != "json" && req.Format != "dot" {
		return o, errors.New("unknown graph format")
	}
	if req.Relation != "" && req.Relation != "requires" && req.Relation != "hints" {
		return o, errors.New("unknown graph relation")
	}
	if req.Target != "" && !targetValid(req.Target) {
		return o, errors.New("invalid graph target")
	}
	if req.Depth < -1 || (req.Depth >= 0 && req.Target == "") {
		return o, errors.New("depth requires a target")
	}
	return o, nil
}

func Graph(req GraphRequest, w io.Writer) error {
	opts, err := graphRequest(req)
	if err != nil {
		return err
	}
	return withInitializedState(func(c config) error { return graphRead(c, opts, w) })
}

/*
작업 공간 또는 암호문을 임시 복사해 현재 선언 그래프를 조회한다.
외부 소스 갱신이나 runtime 활성화 없이 정리 오류까지 반환한다.
*/
func graphRead(c config, o graphOptions, w io.Writer) (resultErr error) {
	if err := keyValidate(c); err != nil {
		return err
	}
	stage, err := stageCreate(c)
	if err != nil {
		return err
	}
	defer cleanupPath(&resultErr, stage)
	root := filepath.Join(stage, "capability")
	if _, err = materialize(c, root); err != nil {
		return err
	}
	nodes, err := validate(c, root)
	if err != nil {
		return err
	}
	if err = catalogValidate(c, root); err != nil {
		return err
	}
	view, err := graphBuild(nodes, o)
	if err != nil {
		return err
	}
	return graphRender(w, view, o)
}

/*
requires와 hints를 구분하고 원래 edge 방향을 보존한다.
역방향 탐색은 도달 범위만 바꾸며 실행 순서를 의미하지 않는다.
*/
func graphBuild(nodes map[string]node, o graphOptions) (graphView, error) {
	v := graphView{Version: 1, Scope: "local_desired", Nodes: []graphNode{}, Edges: []graphEdge{}}
	ids := make([]string, 0, len(nodes))
	for id := range nodes {
		ids = append(ids, id)
	}
	sort.Strings(ids)
	for _, id := range ids {
		n := nodes[id]
		from := n.Kind + "/" + id
		v.Nodes = append(v.Nodes, graphNode{from, n.Kind})
		v.Edges = append(v.Edges, graphEdges(nodes, from, n.Requires, "requires")...)
		v.Edges = append(v.Edges, graphEdges(nodes, from, n.Hints, "hints")...)
	}
	v.Edges = graphRelation(v.Edges, o.relation)
	if o.target == "" {
		if o.depth >= 0 {
			return v, errors.New("--depth requires a target")
		}
		return v, nil
	}
	kind, id, _ := strings.Cut(o.target, "/")
	n, ok := nodes[id]
	if !ok || n.Kind != kind {
		return v, errors.New("unknown graph target; run harness config graph to list available IDs")
	}
	return graphFilter(v, o), nil
}
func graphEdges(nodes map[string]node, from string, refs []string, kind string) []graphEdge {
	result := make([]graphEdge, 0, len(refs))
	refs = append([]string(nil), refs...)
	sort.Strings(refs)
	for _, ref := range refs {
		result = append(result, graphEdge{from, nodes[ref].Kind + "/" + ref, kind})
	}
	return result
}
func graphFilter(v graphView, o graphOptions) graphView {
	seen := map[string]bool{o.target: true}
	queue := []string{o.target}
	depth := 0
	for len(queue) > 0 && (o.depth < 0 || depth < o.depth) {
		queue = graphNext(v.Edges, queue, seen, o.reverse)
		depth++
	}
	result := graphView{Version: v.Version, Scope: v.Scope, Nodes: []graphNode{}, Edges: []graphEdge{}}
	for _, n := range v.Nodes {
		if seen[n.ID] {
			result.Nodes = append(result.Nodes, n)
		}
	}
	for _, e := range v.Edges {
		if seen[e.From] && seen[e.To] {
			result.Edges = append(result.Edges, e)
		}
	}
	return result
}
func graphNext(edges []graphEdge, queue []string, seen map[string]bool, reverse bool) []string {
	active := map[string]bool{}
	for _, id := range queue {
		active[id] = true
	}
	var next []string
	for _, e := range edges {
		from, to := e.From, e.To
		if reverse {
			from, to = to, from
		}
		if active[from] && !seen[to] {
			seen[to] = true
			next = append(next, to)
		}
	}
	return next
}
func graphRender(w io.Writer, v graphView, o graphOptions) error {
	switch o.format {
	case "json":
		enc := json.NewEncoder(w)
		enc.SetIndent("", "  ")
		return enc.Encode(v)
	case "dot":
		return graphDOT(w, v)
	default:
		return graphTree(w, v, o)
	}
}
func graphDOT(w io.Writer, v graphView) error {
	var b strings.Builder
	b.WriteString("digraph Capability {\n  rankdir=TB;\n")
	for _, n := range v.Nodes {
		fmt.Fprintf(&b, "  %q;\n", n.ID)
	}
	for _, e := range v.Edges {
		fmt.Fprintf(&b, "  %q -> %q [label=%q];\n", e.From, e.To, e.Type)
	}
	b.WriteString("}\n")
	_, err := io.WriteString(w, b.String())
	return err
}
func graphTree(w io.Writer, v graphView, o graphOptions) error {
	var b strings.Builder
	fmt.Fprintln(&b, "Graph: local desired (before source reconciliation)")
	adj := map[string][]graphEdge{}
	incoming := map[string]bool{}
	for _, e := range v.Edges {
		if o.reverse {
			e.From, e.To = e.To, e.From
		}
		adj[e.From] = append(adj[e.From], e)
		incoming[e.To] = true
	}
	seen := map[string]bool{}
	for _, n := range v.Nodes {
		if !incoming[n.ID] {
			graphBranch(&b, adj, seen, graphLine{id: n.ID})
		}
	}
	for _, n := range v.Nodes {
		if !seen[n.ID] {
			graphBranch(&b, adj, seen, graphLine{id: n.ID})
		}
	}
	_, err := io.WriteString(w, b.String())
	return err
}

type graphLine struct{ id, indent, branch, relation string }

func graphBranch(b *strings.Builder, adj map[string][]graphEdge, seen map[string]bool, line graphLine) {
	fmt.Fprint(b, line.indent, line.branch, line.id)
	if line.relation != "" {
		fmt.Fprintf(b, " [%s]", line.relation)
	}
	if seen[line.id] {
		fmt.Fprintln(b, " [shared]")
		return
	}
	fmt.Fprintln(b)
	seen[line.id] = true
	indent := line.indent
	if line.branch == "├── " {
		indent += "│   "
	} else if line.branch != "" {
		indent += "    "
	}
	for i, e := range adj[line.id] {
		branch := "├── "
		if i == len(adj[line.id])-1 {
			branch = "└── "
		}
		graphBranch(b, adj, seen, graphLine{e.To, indent, branch, e.Type})
	}
}

func graphRelation(edges []graphEdge, relation string) []graphEdge {
	if relation == "" {
		return edges
	}
	result := make([]graphEdge, 0, len(edges))
	for _, e := range edges {
		if e.Type == relation {
			result = append(result, e)
		}
	}
	return result
}
