package config

import (
	"encoding/json"
	"errors"
	"github.com/spf13/cobra"
	"os"
	"slices"
	"tonys-agent-harness/cli"
	"tonys-agent-harness/core"
)

/*
Config 명령은 Capability와 Vault의 수명주기를 관리한다.
파싱은 Cobra, 실행은 Core에서 처리한다.
*/
func Command(application core.Application) *cobra.Command {
	var cmd = &cobra.Command{Use: "config", Short: "Manage capabilities and runtime", Args: cobra.NoArgs}
	var status = commandStatus(application)
	cmd.RunE = status.RunE
	cmd.AddCommand(
		status, commandInit(application), commandEdit(application), commandApply(application, "apply", false),
	)
	cmd.AddCommand(commandGraph(application), commandWorkspace(application), commandRuntime(application))
	cmd.AddCommand(commandApply(application, "sync", true), commandOpen(application, "unlock", true))
	cmd.AddCommand(commandClose(application, "lock", true), commandReset(application, "purge", true))
	return cmd
}

func commandStatus(application core.Application) *cobra.Command {
	var format string
	var cmd = &cobra.Command{Use: "status", Short: "Inspect state without decryption", Args: cobra.NoArgs}
	cmd.PreRunE = func(_ *cobra.Command, _ []string) error { return formatValidate(format, "text", "json") }
	cmd.RunE = func(_ *cobra.Command, _ []string) error { return statusWrite(application, format) }
	cmd.Flags().StringVar(&format, "format", "text", "Output: text or json")
	return cmd
}

func statusWrite(application core.Application, format string) error {
	if format != "json" {
		return cli.RenderStatus(application)
	}
	var r, err = application.ReadStatus()
	if err != nil {
		return err
	}
	return json.NewEncoder(os.Stdout).Encode(r)
}

func formatValidate(value string, allowed ...string) error {
	if !slices.Contains(allowed, value) {
		return errors.New("invalid output format")
	}
	return nil
}

func commandInit(application core.Application) *cobra.Command {
	return &cobra.Command{Use: "init SOURCE|empty", Short: "Initialize explicitly", Args: cobra.ExactArgs(1),
		RunE: func(_ *cobra.Command, args []string) error { return application.Init(argFirst(args)) }}
}

func commandEdit(application core.Application) *cobra.Command {
	return &cobra.Command{Use: "edit [kind/id]", Short: "Edit, apply, and close workspace", Args: cobra.MaximumNArgs(1),
		RunE: func(_ *cobra.Command, args []string) error { return application.Edit(argFirst(args)) }}
}

func argFirst(args []string) string {
	if len(args) == 0 {
		return ""
	}
	return args[0]
}

func commandApply(application core.Application, use string, hidden bool) *cobra.Command {
	var req core.ReconcileRequest
	var format string
	var cmd = &cobra.Command{Use: use, Short: "Validate, save, and deploy", Args: cobra.NoArgs, Hidden: hidden}
	cmd.PreRunE = func(_ *cobra.Command, _ []string) error { return formatValidate(format, "text", "json") }
	cmd.RunE = func(_ *cobra.Command, _ []string) error {
		req.JSON = format == "json"
		return application.Reconcile(req)
	}
	cmd.Flags().BoolVar(&req.Plan, "dry-run", false, "Preview without deployment")
	cmd.Flags().BoolVar(&req.Verbose, "verbose", false, "Include capability IDs")
	cmd.Flags().StringVar(&format, "format", "text", "Output: text or json")
	return cmd
}

func commandWorkspace(application core.Application) *cobra.Command {
	var cmd = &cobra.Command{Use: "workspace", Short: "Manage the private editing workspace", Args: cobra.NoArgs}
	cmd.AddCommand(commandOpen(application, "open", false), commandClose(application, "close", false))
	return cmd
}

func commandRuntime(application core.Application) *cobra.Command {
	var cmd = &cobra.Command{Use: "runtime", Short: "Manage the activated runtime", Args: cobra.NoArgs}
	cmd.AddCommand(commandReset(application, "reset", false))
	return cmd
}

func commandClose(application core.Application, use string, hidden bool) *cobra.Command {
	return &cobra.Command{Use: use, Short: "Save and close the workspace", Args: cobra.NoArgs, Hidden: hidden,
		RunE: func(_ *cobra.Command, _ []string) error { return application.Lock() }}
}

func commandReset(application core.Application, use string, hidden bool) *cobra.Command {
	return &cobra.Command{Use: use, Short: "Remove the managed runtime", Args: cobra.NoArgs, Hidden: hidden,
		RunE: func(_ *cobra.Command, _ []string) error { return application.Purge() }}
}

func commandGraph(application core.Application) *cobra.Command {
	var req core.GraphRequest
	var cmd = &cobra.Command{Use: "graph [kind/id]", Short: "Explore composition", Args: cobra.MaximumNArgs(1)}
	cmd.PreRunE = func(_ *cobra.Command, _ []string) error {
		if err := formatValidate(req.Format, "tree", "dot", "json"); err != nil {
			return err
		}
		if req.Depth < -1 {
			return errors.New("invalid depth")
		}
		return formatValidate(req.Relation, "", "requires", "hints")
	}
	cmd.RunE = func(c *cobra.Command, args []string) error {
		req.Target = argFirst(args)
		return application.Graph(req, c.OutOrStdout())
	}
	cmd.Flags().StringVar(&req.Format, "format", "tree", "Output: tree, dot or json")
	cmd.Flags().StringVar(&req.Relation, "relation", "", "Filter: requires or hints")
	cmd.Flags().BoolVar(&req.Reverse, "reverse", false, "Explore consumers")
	cmd.Flags().IntVar(&req.Depth, "depth", -1, "Traversal depth; -1 means unlimited")
	return cmd
}

func commandOpen(application core.Application, use string, hidden bool) *cobra.Command {
	var edit, path bool
	var cmd = &cobra.Command{Use: use, Short: "Open the private workspace", Args: cobra.NoArgs, Hidden: hidden}
	cmd.RunE = func(_ *cobra.Command, _ []string) error {
		if edit {
			return application.Unlock("--edit")
		}
		if path {
			return application.Unlock("--path")
		}
		return application.Unlock("")
	}
	cmd.Flags().BoolVar(&edit, "edit", false, "Open editor without apply")
	cmd.Flags().BoolVar(&path, "path", false, "Print workspace path")
	cmd.MarkFlagsMutuallyExclusive("edit", "path")
	return cmd
}
