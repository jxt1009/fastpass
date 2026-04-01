package main

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

func authMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		authHeader := c.GetHeader("Authorization")
		
		tokenString, err := extractBearerToken(authHeader)
		if err != nil {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Missing or invalid authorization header"})
			c.Abort()
			return
		}

		claims, err := validateJWT(tokenString)
		if err != nil {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid or expired token"})
			c.Abort()
			return
		}

		// Store user info in context
		c.Set("user_id", claims.UserID)
		c.Set("apple_user_id", claims.AppleUserID)
		c.Set("email", claims.Email)

		c.Next()
	}
}

func optionalAuthMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		authHeader := c.GetHeader("Authorization")
		
		if authHeader == "" {
			c.Next()
			return
		}

		tokenString, err := extractBearerToken(authHeader)
		if err != nil {
			c.Next()
			return
		}

		claims, err := validateJWT(tokenString)
		if err != nil {
			c.Next()
			return
		}

		// Store user info in context if valid
		c.Set("user_id", claims.UserID)
		c.Set("apple_user_id", claims.AppleUserID)
		c.Set("email", claims.Email)

		c.Next()
	}
}

func getUserID(c *gin.Context) (uint, bool) {
	userID, exists := c.Get("user_id")
	if !exists {
		return 0, false
	}
	
	id, ok := userID.(uint)
	return id, ok
}

func getUserIDString(c *gin.Context) string {
	// For backward compatibility with old user_id query param
	userID := c.Query("user_id")
	if userID != "" {
		return userID
	}

	// Check if authenticated
	_, exists := getUserID(c)
	if exists {
		return c.GetString("apple_user_id")
	}

	return ""
}
