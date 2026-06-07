package app

import "github.com/gin-gonic/gin"

func registerNotificationRoutes(r *gin.Engine) {
	api := r.Group("/api/v1")
	api.Use(authMiddleware())
	{
		api.GET("/me/notifications", GetMyNotifications)
		api.GET("/me/notifications/unread-count", UnreadNotificationCount)
		api.POST("/me/notifications/:id/read", MarkNotificationRead)
		api.POST("/me/notifications/read-all", MarkAllNotificationsRead)
	}
}
