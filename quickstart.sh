#!/bin/bash

# Quick Start Script for TripRank Development

echo "🚗 TripRank Quick Start"
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

# Backend status
cd backend
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
cd ..

echo ""
echo "🎯 Next Steps:"
echo ""
echo "1. Backend Setup (Choose one):"
echo "   A) Deploy to Kubernetes:"
echo "      cd backend && cat DEPLOYMENT.md"
echo ""
echo "   B) Run locally (requires PostgreSQL):"
echo "      # Install and start PostgreSQL"
echo "      createdb triprank"
echo "      export DATABASE_URL='host=localhost user=postgres password=postgres dbname=triprank port=5432 sslmode=disable'"
echo "      cd backend && go run ."
echo ""
echo "2. iOS Setup:"
echo "   • Open Xcode"
echo "   • File → New → Project → iOS App"
echo "   • Name: TripRank, Interface: SwiftUI, Language: Swift"
echo "   • Save to: $(pwd)/ios"
echo "   • Add source files from ios/TripRank/"
echo "   • Copy Info.plist.template contents to your Info.plist"
echo "   • See ios/README.md for detailed instructions"
echo ""
echo "3. Configuration:"
echo "   • Update backend URL in ios/TripRank/Services/APIService.swift"
echo "   • Update K8s ingress domain in backend/k8s/ingress.yaml"
echo ""
echo "📖 Documentation:"
echo "   • GETTING_STARTED.md - Comprehensive setup guide"
echo "   • backend/DEPLOYMENT.md - Kubernetes deployment"
echo "   • ios/README.md - iOS app setup"
echo ""
echo "Ready to build! 🚀"
