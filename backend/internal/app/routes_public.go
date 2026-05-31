package app

import "github.com/gin-gonic/gin"

func registerPublicRoutes(r *gin.Engine) {
	registerPublicPageRoutes(r)

	// Serve uploaded avatars and web static files
	r.Static("/uploads", "./uploads")
	r.Static("/static", "./static")

	// Public web page routes (no auth required)
	r.GET("/leaderboard", renderLeaderboard)
	r.GET("/u/:username", renderProfile)
}
