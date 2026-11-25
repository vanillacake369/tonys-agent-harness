package cli

import (
	_ "embed"
	"strings"
)

//go:embed version.txt
var versionFile string

var buildVersion = strings.TrimSpace(versionFile)
