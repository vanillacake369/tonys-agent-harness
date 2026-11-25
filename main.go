package main

import (
	"fmt"
	"github.com/spf13/cobra"
	"os"
	"syscall"
	"tonys-agent-harness/cli"
	"tonys-agent-harness/config"
	"tonys-agent-harness/core"
	"tonys-agent-harness/provider"
	"tonys-agent-harness/source"
)

func main() {
	syscall.Umask(0077)
	application := core.NewApplication()
	commands := []*cobra.Command{
		config.Command(application), source.Command(application), provider.Command(application),
	}
	code, err := cli.Run(application, commands, os.Args[1:])
	if err != nil {
		fmt.Fprintln(os.Stderr, "BLOCKED:", core.PublicError(err))
	}
	os.Exit(code)
}
