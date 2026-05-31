package app

import "github.com/gin-gonic/gin"

func registerAccountRoutes(r *gin.Engine) {
	// API routes (auth required — personal data)
	api := r.Group("/api/v1")
	api.Use(authMiddleware())
	{
		api.GET("/me", getCurrentUser)
		api.DELETE("/me", deleteCurrentUser)
		api.PUT("/profile", updateProfile)
		api.PUT("/profile/avatar", uploadAvatar)
		api.GET("/stats", getCarStats)
		api.PUT("/stats", putCarStats)
		api.PUT("/display-settings", putDisplaySettings)
	}
}
