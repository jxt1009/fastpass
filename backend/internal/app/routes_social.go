package app

import "github.com/gin-gonic/gin"

func registerSocialRoutes(r *gin.Engine) {
	// Social routes (optional auth — public data)
	social := r.Group("/api/v1")
	social.Use(optionalAuthMiddleware())
	{
		social.GET("/users/search", searchUsers)
		social.GET("/leaderboard", getLeaderboard)
		social.GET("/users/:username", getPublicProfile)
		social.GET("/users/:username/followers", getFollowers)
		social.GET("/users/:username/following", getFollowing)
		social.GET("/cars/models", getCarModels)
	}

	// Social routes (auth required — mutating follows)
	socialAuth := r.Group("/api/v1")
	socialAuth.Use(authMiddleware())
	{
		socialAuth.POST("/users/:username/follow", followUser)
		socialAuth.DELETE("/users/:username/follow", unfollowUser)
	}
}
