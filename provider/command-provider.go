package provider

import (
	"encoding/json"
	"errors"
	"fmt"
	"github.com/spf13/cobra"
	"os"
	"strings"
	"tonys-agent-harness/core"
)

func Command(application core.Application) *cobra.Command {
	var cmd = &cobra.Command{Use: "provider", Short: "Manage approved native provider links", Args: cobra.NoArgs}
	var status = commandStatus(application)
	cmd.RunE = status.RunE
	cmd.AddCommand(status, &cobra.Command{
		Use: "connect NAME", Short: "Approve provider access", Args: cobra.ExactArgs(1),
		ValidArgsFunction: providerCompletion(application),
		RunE:              func(_ *cobra.Command, args []string) error { return application.Connect(args[0]) },
	}, &cobra.Command{
		Use: "disconnect NAME", Short: "Remove managed link", Args: cobra.ExactArgs(1),
		ValidArgsFunction: providerCompletion(application),
		RunE:              func(_ *cobra.Command, args []string) error { return application.Disconnect(args[0]) },
	})
	return cmd
}

func commandStatus(application core.Application) *cobra.Command {
	var format string
	var cmd = &cobra.Command{Use: "status [NAME]", Short: "Inspect managed links", Args: cobra.MaximumNArgs(1),
		ValidArgsFunction: providerCompletion(application)}
	cmd.PreRunE = func(_ *cobra.Command, _ []string) error {
		if format != "text" && format != "json" {
			return errors.New("invalid output format")
		}
		return nil
	}
	cmd.RunE = func(_ *cobra.Command, args []string) error {
		var name string
		if len(args) > 0 {
			name = args[0]
		}
		var rows, err = application.ReadProviders(name)
		if err != nil {
			return err
		}
		if format == "json" {
			return json.NewEncoder(os.Stdout).Encode(map[string]any{"schema_version": 1, "providers": rows})
		}
		for _, s := range rows {
			fmt.Printf("provider=%s status=%s\n", s.Name, s.State)
		}
		return nil
	}
	cmd.Flags().StringVar(&format, "format", "text", "Output: text or json")
	return cmd
}

func providerCompletion(application core.Application) func(*cobra.Command, []string, string) ([]string,
	cobra.ShellCompDirective,
) {
	return func(_ *cobra.Command, _ []string, toComplete string) ([]string, cobra.ShellCompDirective) {
		names, err := application.ProviderNames()
		if err != nil {
			return nil, cobra.ShellCompDirectiveError
		}
		var matches []string
		for _, name := range names {
			if strings.HasPrefix(name, toComplete) {
				matches = append(matches, name)
			}
		}
		return matches, cobra.ShellCompDirectiveNoFileComp
	}
}
