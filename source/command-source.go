package source

import (
	"encoding/json"
	"errors"
	"fmt"
	"github.com/spf13/cobra"
	"os"
	"tonys-agent-harness/core"
)

func Command(application core.Application) *cobra.Command {
	var cmd = &cobra.Command{Use: "source", Short: "Inspect and pin Git sources", Args: cobra.NoArgs}
	var status = commandStatus(application)
	cmd.RunE = status.RunE
	cmd.AddCommand(status, commandCache(application), &cobra.Command{
		Use: "check NAME", Short: "Inspect the remote candidate without changing its pin", Args: cobra.ExactArgs(1),
		RunE: func(_ *cobra.Command, args []string) error { return application.UpdateSource(args[0], "") },
	}, &cobra.Command{
		Use: "pin NAME FULL_SHA", Short: "Pin an explicitly reviewed Git commit", Args: cobra.ExactArgs(2),
		RunE: func(cmd *cobra.Command, args []string) error {
			if args[1] == "" {
				return errors.New("full reviewed revision required")
			}
			if err := application.UpdateSource(args[0], args[1]); err != nil {
				return err
			}
			cmd.Println("Next: harness apply --dry-run")
			return nil
		},
	})
	return cmd
}

func commandCache(application core.Application) *cobra.Command {
	var cmd = &cobra.Command{Use: "cache", Short: "Manage immutable Source caches", Args: cobra.NoArgs}
	var plan bool
	var prune = &cobra.Command{Use: "prune", Short: "Remove unreferenced caches", Args: cobra.NoArgs}
	prune.RunE = func(_ *cobra.Command, _ []string) error {
		result, err := application.PruneSourceCache(plan)
		if err != nil {
			return err
		}
		outcome := "PRUNED"
		if plan {
			outcome = "PLANNED"
		}
		fmt.Printf("%s removed=%d bytes=%d\n", outcome, result.Removed, result.Bytes)
		return nil
	}
	prune.Flags().BoolVar(&plan, "dry-run", false, "Preview without deletion")
	cmd.AddCommand(prune)
	return cmd
}

func commandStatus(application core.Application) *cobra.Command {
	var format string
	var cmd = &cobra.Command{Use: "status [NAME]", Short: "Show current pins", Args: cobra.MaximumNArgs(1)}
	cmd.PreRunE = func(_ *cobra.Command, _ []string) error {
		if format != "text" && format != "json" {
			return errors.New("invalid output format")
		}
		return nil
	}
	cmd.RunE = func(_ *cobra.Command, args []string) error {
		var rows, err = application.ReadSources()
		if err != nil {
			return err
		}
		if len(args) > 0 {
			rows, err = sourceSelect(rows, args[0])
			if err != nil {
				return err
			}
		}
		if format == "json" {
			return json.NewEncoder(os.Stdout).Encode(map[string]any{"schema_version": 1, "sources": rows})
		}
		for _, s := range rows {
			fmt.Printf("%s pinned=%t revision=%s\n", s.Name, s.Pinned, s.Revision)
		}
		return nil
	}
	cmd.Flags().StringVar(&format, "format", "text", "Output: text or json")
	return cmd
}

func sourceSelect(rows []core.SourceStatus, name string) ([]core.SourceStatus, error) {
	for _, s := range rows {
		if s.Name == name {
			return []core.SourceStatus{s}, nil
		}
	}
	return nil, errors.New("unknown source")
}
