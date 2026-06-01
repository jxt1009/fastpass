# SPA build stage
FROM node:22-alpine AS spa-builder

WORKDIR /spa

COPY website/spa/package.json website/spa/package-lock.json ./
RUN npm ci

COPY website/spa/ ./
RUN npm run build

# Go build stage
FROM golang:1.26-alpine AS builder

WORKDIR /app/backend

# Copy go mod files (paths relative to build context = repo root)
COPY backend/go.mod backend/go.sum ./
RUN go mod download

# Copy source code and web assets
COPY backend/cmd/ ./cmd/
COPY backend/internal/ ./internal/
COPY backend/static/ ./static/

# Copy SPA build output from the previous stage
# SPA config outputs to ../../backend/static/spa/ relative to WORKDIR /spa = /backend/static/spa/
COPY --from=spa-builder /backend/static/spa/ ./static/spa/

# Build with version info injected
ARG VERSION=dev
ARG COMMIT=unknown
RUN CGO_ENABLED=0 GOOS=linux go build \
    -ldflags="-s -w -X main.buildVersion=${VERSION} -X main.buildCommit=${COMMIT}" \
    -o /fasttrack ./cmd/server

# Runtime stage
FROM alpine:latest

RUN apk --no-cache add ca-certificates

WORKDIR /app

COPY --from=builder /fasttrack .
COPY --from=builder /app/backend/static/ ./static/

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://localhost:8080/health || exit 1

CMD ["./fasttrack"]
