#!/bin/bash

# Quick Start Script for FastTrack Development

echo "🚗 FastTrack Quick Start"
echo "======================="
echo ""

# Check prerequisites
echo "Checking prerequisites..."

if ! command -v go &> /dev/null; then
    echo "❌ Go is not installed"
    exit 1
fi
echo "✅ Go $(go version | awk '{print $3}')"

if ! command -v xcodebuild &> /dev/null; then
    echo "❌ Xcode is not installed"
    exit 1
fi
echo "✅ Xcode $(xcodebuild -version | head -1 | awk '{print $2}')"

if ! command -v kubectl &> /dev/null; then
    echo "⚠️  kubectl not found (needed for K8s deployment)"
else
    echo "✅ kubectl $(kubectl version --client --short 2>/dev/null || echo 'installed')"
fi

echo ""
echo "📦 Project Structure:"
echo "  ├── backend/     - Go API server (ready to deploy)"
echo "  └── ios/         - iOS SwiftUI app (needs Xcode setup)"
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Backend status
cd "$REPO_ROOT/backend"
if [ -f "triprank-api" ]; then
    echo "✅ Backend binary compiled"
else
    echo "⚙️  Compiling backend..."
    go build -o triprank-api
    if [ $? -eq 0 ]; then
        echo "✅ Backend compiled successfully"
    else
        echo "❌ Backend compilation failed"
        exit 1
    fi
fi
cd "$REPO_ROOT"

echo ""
echo "🎯 Next Steps:"
echo ""
echo "1. Backend Setup (Choose one):"
echo "   A) Deploy to Kubernetes:"
echo "      cat docs/DEPLOYMENT.md"
echo ""
echo "   B) Run locally (requires PostgreSQL):"
echo "      # Install and start PostgreSQL"
echo "      createdb fasttrack"
echo "      export DATABASE_URL='host=localhost user=postgres password=postgres dbname=fasttrack port=5432 sslmode=disable'"
echo "      cd backend && go run ./cmd/server"
echo ""
echo "2. iOS Setup:"
echo "   • Open existing project: ios/FastTrack/FastTrack.xcodeproj"
echo "   • Copy ios/FastTrack/FastTrack/Secrets.swift.template to Secrets.swift"
echo "   • Set your local secrets in ios/FastTrack/FastTrack/Secrets.swift"
echo "   • Build and run the FastTrack scheme in Xcode"
echo ""
echo "3. Configuration:"
echo "   • Update backend URL in ios/FastTrack/FastTrack/Services/APIService.swift"
echo "   • Update K8s ingress domain in backend/k8s/base/ingress.yaml"
echo ""
echo "📖 Documentation:"
echo "   • README.md - Repository overview and setup"
echo "   • docs/DEVELOPMENT.md - Local development workflow"
echo "   • docs/DEPLOYMENT.md - Kubernetes deployment"
echo ""
echo "Ready to build! 🚀"
