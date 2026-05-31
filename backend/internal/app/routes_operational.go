package app

import (
	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

func newRouter() *gin.Engine {
	r := gin.New()
	r.Use(gin.Recovery())
	r.Use(requestIDMiddleware())
	r.Use(requestLoggerMiddleware())
	r.Use(metricsMiddleware())
	// Limit request bodies to 12 MB (avatar upload is the largest expected payload)
	r.MaxMultipartMemory = 12 << 20
	return r
}

func registerOperationalRoutes(r *gin.Engine) {
	// Prometheus metrics scrape endpoint (internal only — not exposed via Ingress)
	r.GET("/metrics", gin.WrapH(promhttp.Handler()))

	// Health check
	r.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{"status": "ok"})
	})
}
