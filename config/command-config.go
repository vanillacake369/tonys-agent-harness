package config

import (
	"errors"
	"github.com/spf13/cobra"
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
	cmd.AddCommand(commandInit(application), commandGraph(application), commandRuntime(application))
	return cmd
}

func LifecycleCommands(application core.Application) []*cobra.Command {
	setup := &cobra.Command{
		Use: "setup", Short: "Register a checkout and show the next onboarding step", Args: cobra.NoArgs,
		RunE: func(_ *cobra.Command, _ []string) error {
			if err := application.SetupRepository(); err != nil {
				return err
			}
			return cli.RenderStatus(application)
		},
	}
	var path, apply bool
	edit := &cobra.Command{
		Use: "edit [kind/id]", Short: "Open the private workspace for editing", Args: cobra.MaximumNArgs(1),
		RunE: func(_ *cobra.Command, args []string) error {
			if path {
				if len(args) != 0 {
					return errors.New("--path does not accept a capability target")
				}
				return application.Unlock("--path")
			}
			return application.EditWorkspace(argFirst(args), apply)
		},
	}
	edit.Flags().BoolVar(&path, "path", false, "Print the workspace path for external editing")
	edit.Flags().BoolVar(&apply, "apply", false, "Save and deploy when the editor exits successfully")
	edit.MarkFlagsMutuallyExclusive("path", "apply")
	return []*cobra.Command{setup, edit, commandApply(application)}
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

func argFirst(args []string) string {
	if len(args) == 0 {
		return ""
	}
	return args[0]
}

func commandApply(application core.Application) *cobra.Command {
	var req core.ReconcileRequest
	var format string
	var cmd = &cobra.Command{Use: "apply", Short: "Validate, save, and deploy", Args: cobra.NoArgs}
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

func commandRuntime(application core.Application) *cobra.Command {
	var cmd = &cobra.Command{Use: "runtime", Short: "Manage the activated runtime", Args: cobra.NoArgs}
	cmd.AddCommand(commandReset(application))
	return cmd
}

func commandReset(application core.Application) *cobra.Command {
	return &cobra.Command{Use: "reset", Short: "Remove the managed runtime", Args: cobra.NoArgs,
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
