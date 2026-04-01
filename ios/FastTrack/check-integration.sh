#!/bin/bash

echo "🎯 FastTrack Integration Checklist"
echo "================================="
echo ""

cd "$(dirname "$0")/FastTrack"

echo "✅ Swift Files (should be 8):"
find . -name "*.swift" -type f | wc -l | xargs echo "   Found:"

echo ""
echo "📁 File Structure:"
echo "   FastTrackApp.swift"
ls -1 Models/*.swift 2>/dev/null | sed 's/^/   /'
ls -1 Services/*.swift 2>/dev/null | sed 's/^/   /'
ls -1 ViewModels/*.swift 2>/dev/null | sed 's/^/   /'
ls -1 Views/*.swift 2>/dev/null | sed 's/^/   /'

echo ""
echo "📋 Next Steps in Xcode:"
echo ""
echo "1. ⚠️  Add files to Xcode project:"
echo "   • Right-click 'FastTrack' group → Add Files"
echo "   • Select: Views, Models, Services, ViewModels folders"
echo "   • UNCHECK 'Copy items if needed'"
echo ""
echo "2. 🔐 Configure location permissions:"
echo "   • Project → Target → Info tab"
echo "   • Add location usage descriptions (see SETUP.md)"
echo ""
echo "3. 🎮 Enable Background Modes:"
echo "   • Signing & Capabilities → + Capability"
echo "   • Add 'Background Modes' → Check 'Location updates'"
echo ""
echo "4. 🌐 Update backend URL:"
echo "   • Open Services/APIService.swift"
echo "   • Change baseURL to your backend"
echo ""
echo "5. ▶️  Build and Run (Cmd+R)"
echo ""
echo "📖 See SETUP.md for detailed instructions"
echo ""
