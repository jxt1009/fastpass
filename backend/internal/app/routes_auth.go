package app

import "github.com/gin-gonic/gin"

func registerAuthRoutes(r *gin.Engine) {
	// Auth routes (no auth required)
	auth := r.Group("/api/v1/auth")
	{
		auth.POST("/apple", appleSignIn)
		auth.POST("/google", handleGoogleSignIn)
		auth.POST("/refresh", refreshToken)
	}
}
