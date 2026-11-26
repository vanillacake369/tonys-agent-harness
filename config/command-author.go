package config

import (
	"github.com/spf13/cobra"
	"tonys-agent-harness/core"
)

func SkillCommand(application core.Application) *cobra.Command {
	cmd := &cobra.Command{Use: "skill", Short: "Create and validate Skill drafts", Args: cobra.NoArgs}
	cmd.AddCommand(commandNewSkill(application), commandValidate(application))
	return cmd
}

func commandNewSkill(application core.Application) *cobra.Command {
	var output string
	cmd := &cobra.Command{
		Use:   "new ID",
		Short: "Create a v2.1 skill draft without deploying it",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			path, err := application.ScaffoldSkill("skill/"+args[0], output)
			if err == nil {
				cmd.Println(path)
			}
			return err
		},
	}
	cmd.Flags().StringVar(&output, "output", "", "Existing directory in which to create the skill")
	_ = cmd.MarkFlagRequired("output")
	return cmd
}

func commandValidate(application core.Application) *cobra.Command {
	return &cobra.Command{
		Use:   "validate SKILL_DIR",
		Short: "Validate one v2.1 skill without opening the Vault",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			if err := application.ValidateSkill(args[0]); err != nil {
				return err
			}
			cmd.Println("Skill validated")
			return nil
		},
	}
}
