package app

import "github.com/gin-gonic/gin"

func registerDriveRoutes(r *gin.Engine) {
	// Drive routes (auth required)
	api := r.Group("/api/v1")
	api.Use(authMiddleware())
	{
		api.POST("/drives", createDrive)
		api.GET("/drives", listDrives)
		api.GET("/drives/:id", getDrive)
		api.PUT("/drives/:id", updateDrive)
		api.DELETE("/drives/:id", deleteDrive)
	}
}
