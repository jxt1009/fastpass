package app

import (
	"gorm.io/gorm"
)

var db *gorm.DB

func Run(buildVersion, buildCommit string) {
	configureLogging()
	initJWTSecret()
	initDatabase()
	initWebTemplates()

	r := newRouter()
	registerOperationalRoutes(r)
	registerPublicRoutes(r)
	registerAuthRoutes(r)
	registerAccountRoutes(r)
	registerDriveRoutes(r)
	registerSocialRoutes(r)

	startServer(r, buildVersion, buildCommit)
}
