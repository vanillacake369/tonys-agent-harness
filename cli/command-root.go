package cli

import (
	"github.com/spf13/cobra"
	"os"
	"tonys-agent-harness/core"
)

/*
Cobra에 파싱과 도움말을 위임한다. 실행 오류와 입력 오류는
서로 다른 종료 코드로 전달한다.
*/
func Run(application core.Application, commands []*cobra.Command, args []string) (int, error) {
	var repo string
	var code = 2
	var root = &cobra.Command{
		Use: "harness", Short: "Manage agent capabilities", Version: buildVersion,
		SilenceUsage: true, SilenceErrors: true, Args: cobra.NoArgs,
		RunE: func(_ *cobra.Command, _ []string) error { return RenderStatus(application) },
		PersistentPreRunE: func(_ *cobra.Command, _ []string) error {
			if repo != "" {
				if err := os.Setenv("HARNESS_REPO", repo); err != nil {
					return err
				}
			}
			return nil
		},
	}
	root.PersistentFlags().StringVar(&repo, "repo", "", "Configuration checkout directory")
	root.AddCommand(commands...)
	commandWrap(root, &code)
	root.SetArgs(args)
	if err := root.Execute(); err != nil {
		return code, err
	}
	return 0, nil
}

// 입력 검증을 먼저 실행하고 실제 작업에 진입하면 실행 실패 코드로 전환한다.
func commandWrap(cmd *cobra.Command, code *int) {
	if cmd.RunE != nil {
		var run = cmd.RunE
		cmd.RunE = func(c *cobra.Command, args []string) error { *code = 1; return run(c, args) }
	}
	for _, child := range cmd.Commands() {
		commandWrap(child, code)
	}
}
