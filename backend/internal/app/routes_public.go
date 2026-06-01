package app

import "github.com/gin-gonic/gin"

func registerPublicRoutes(r *gin.Engine) {
	registerPublicPageRoutes(r)

	// Serve uploaded avatars and web static files
	r.Static("/uploads", "./uploads")
	r.Static("/static", "./static")

	// SPA build assets (SvelteKit default _app/ path — must be before SPA routes)
	r.Static("/_app", "./static/spa/_app")

	// Public social SPA routes (client-side routing via SvelteKit SPA fallback)
	r.GET("/leaderboard", renderLeaderboard)
	r.GET("/u/:username", renderProfile)
	r.GET("/find", serveSPAIndex)
}
