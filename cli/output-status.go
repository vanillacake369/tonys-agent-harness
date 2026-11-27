package cli

import (
	"encoding/json"
	"errors"
	"fmt"
	"github.com/spf13/cobra"
	"os"
	"tonys-agent-harness/core"
)

func WriteJSON(value any) error { return json.NewEncoder(os.Stdout).Encode(value) }

func RenderStatus(application core.Application) error {
	r, err := application.ReadStatus()
	if err != nil {
		return err
	}
	fmt.Printf("Vault present: %t | Workspace open: %t | Runtime present: %t | Key present: %t\n",
		r.ArchiveExists, r.WorkspaceExists, r.RuntimeExists, r.KeyExists)
	for _, row := range r.Sources {
		fmt.Printf("source=%s pinned=%t\n", row.Name, row.Pinned)
	}
	for _, row := range r.Providers {
		fmt.Printf("provider=%s status=%s\n", row.Name, row.State)
	}
	if r.LegacyPlaintext || r.LegacyBackup {
		fmt.Println("WARNING: legacy plaintext exists; inspect before migration")
	}
	if r.Next != "" {
		fmt.Println("Next:", r.Next)
	}
	return nil
}

func CommandStatus(application core.Application) *cobra.Command {
	var format string
	var cmd = &cobra.Command{Use: "status", Short: "Inspect state without decryption", Args: cobra.NoArgs}
	cmd.PreRunE = func(_ *cobra.Command, _ []string) error {
		if format != "text" && format != "json" {
			return errors.New("invalid output format")
		}
		return nil
	}
	cmd.RunE = func(_ *cobra.Command, _ []string) error {
		if format == "text" {
			return RenderStatus(application)
		}
		r, err := application.ReadStatus()
		if err != nil {
			return err
		}
		return WriteJSON(r)
	}
	cmd.Flags().StringVar(&format, "format", "text", "Output: text or json")
	return cmd
}
