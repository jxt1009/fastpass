package main

import "dev.toper/fasttrack/internal/app"

// Injected at build time via -ldflags
var (
	buildVersion = "dev"
	buildCommit  = "unknown"
)

func main() {
	app.Run(buildVersion, buildCommit)
}
