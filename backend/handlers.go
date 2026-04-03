package main

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
	
	if err := db.Create(&drive).Error; err != nil {
		dbQueryErrorsTotal.WithLabelValues("create_drive").Inc()
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create drive"})
		return
	}

	driveRecordingsTotal.Inc()
	logWithRequestID(c).Info("drive recorded", "user_id", userID, "drive_id", drive.ID, "distance_m", drive.Distance)

	c.JSON(http.StatusCreated, drive)
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
	if err := db.Save(&drive).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update drive"})
		return
	}
	
	c.JSON(http.StatusOK, drive)
}
