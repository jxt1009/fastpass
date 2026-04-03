package main

import (
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
)

// ---------------------------------------------------------------------------
// Metric definitions
// ---------------------------------------------------------------------------

var (
	// HTTP metrics
	httpRequestsTotal = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "http_requests_total",
		Help: "Total number of HTTP requests by method, route, and status code.",
	}, []string{"method", "route", "status"})

	httpRequestDuration = promauto.NewHistogramVec(prometheus.HistogramOpts{
		Name:    "http_request_duration_seconds",
		Help:    "HTTP request latency in seconds.",
		Buckets: []float64{0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2, 5},
	}, []string{"method", "route"})

	// Business metrics
	driveRecordingsTotal = promauto.NewCounter(prometheus.CounterOpts{
		Name: "drive_recordings_total",
		Help: "Total number of drives recorded since server start.",
	})

	userSignupsTotal = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "user_signups_total",
		Help: "Total number of user sign-ups by auth provider.",
	}, []string{"provider"})

	activeDrives = promauto.NewGauge(prometheus.GaugeOpts{
		Name: "active_drives",
		Help: "Number of drives currently in progress (created but not yet finalized).",
	})

	// Database metrics
	dbQueryErrorsTotal = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "db_query_errors_total",
		Help: "Total number of database query errors by operation.",
	}, []string{"operation"})
)

// ---------------------------------------------------------------------------
// Gin middleware
// ---------------------------------------------------------------------------

// metricsMiddleware records per-request HTTP metrics.
func metricsMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()

		c.Next()

		route := c.FullPath()
		if route == "" {
			route = "unknown"
		}

		status := strconv.Itoa(c.Writer.Status())
		duration := time.Since(start).Seconds()

		httpRequestsTotal.WithLabelValues(c.Request.Method, route, status).Inc()
		httpRequestDuration.WithLabelValues(c.Request.Method, route).Observe(duration)
	}
}
