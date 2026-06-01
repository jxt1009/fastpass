package app

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
)

func createDrive(c *gin.Context) {
	userID, exists := getUserID(c)
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	var drive Drive
	if err := c.ShouldBindJSON(&drive); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Set the user ID from auth token
	drive.UserID = userID

	if drive.ZeroToSixtyAttempts == nil {
		drive.ZeroToSixtyAttempts = []ZeroToSixtyAttempt{}
	}

	if err := db.Create(&drive).Error; err != nil {
		dbQueryErrorsTotal.WithLabelValues("create_drive").Inc()
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create drive"})
		return
	}

	driveRecordingsTotal.Inc()
	logWithRequestID(c).Info("drive recorded", "user_id", userID, "drive_id", drive.ID, "distance_m", drive.Distance)

	// Evaluate achievements; embed the user's currently-unlocked set so the
	// client can celebrate and sync exactly without a follow-up fetch.
	unlocked, evalErr := evaluateForUser(userID)
	if evalErr != nil {
		// Don't fail the create — log and continue with an empty unlocked set.
		logWithRequestID(c).Warn("achievement evaluation failed", "user_id", userID, "error", evalErr.Error())
		unlocked = []UnlockedAchievement{}
	}
	c.JSON(http.StatusCreated, gin.H{
		"drive":                drive,
		"unlocked_achievements": unlocked,
	})
}

func listDrives(c *gin.Context) {
	userID, exists := getUserID(c)
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	var drives []Drive
	
	// Only return drives for the authenticated user
	if err := db.Where("user_id = ?", userID).Order("start_time DESC").Find(&drives).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch drives"})
		return
	}
	
	c.JSON(http.StatusOK, drives)
}

func getDrive(c *gin.Context) {
	userID, exists := getUserID(c)
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	id := c.Param("id")
	var drive Drive
	
	// Ensure user can only access their own drives
	if err := db.Where("id = ? AND user_id = ?", id, userID).First(&drive).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Drive not found"})
		return
	}
	
	c.JSON(http.StatusOK, drive)
}

func updateDrive(c *gin.Context) {
	userID, exists := getUserID(c)
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid ID"})
		return
	}

	var drive Drive
	// Ensure user can only update their own drives
	if err := db.Where("id = ? AND user_id = ?", id, userID).First(&drive).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Drive not found"})
		return
	}

	if err := c.ShouldBindJSON(&drive); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	drive.ID = uint(id)
	drive.UserID = userID // Ensure user_id doesn't change
	if drive.ZeroToSixtyAttempts == nil {
		drive.ZeroToSixtyAttempts = []ZeroToSixtyAttempt{}
	}
	if err := db.Save(&drive).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update drive"})
		return
	}

	// Re-evaluate achievements on update too (e.g. car reassignment can
	// affect which drive the user "set" a 0-60 PB on). Always return the
	// same envelope shape so clients have a single decode path; an empty
	// slice signals "nothing new unlocked".
	var unlocked []UnlockedAchievement
	if u, evalErr := evaluateForUser(userID); evalErr == nil {
		unlocked = u
	}
	c.JSON(http.StatusOK, gin.H{
		"drive":                 drive,
		"unlocked_achievements": unlocked,
	})
}
