package cli

import (
	"encoding/json"
	"fmt"
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
	fmt.Println("Next:", r.Next)
	return nil
}
