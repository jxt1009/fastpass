package app

import (
	"path/filepath"

	"github.com/gin-gonic/gin"
)

func serveSPAIndex(c *gin.Context) {
	c.File(filepath.Join(".", "static", "spa", "index.html"))
}

func renderProfile(c *gin.Context) {
	c.File(filepath.Join(".", "static", "spa", "index.html"))
}

func renderLeaderboard(c *gin.Context) {
	c.File(filepath.Join(".", "static", "spa", "index.html"))
}
