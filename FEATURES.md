# FastPass Features

## Live Map Tracking 🗺️

### Real-Time Route Visualization
- **Live Map Display**: When recording, see your route plotted in real-time on an interactive map
- **Animated Camera**: Map automatically follows your current position with smooth animations
- **Route Polyline**: Blue line shows your complete path from start to current position
- **Start Marker**: Green flag indicates where your drive began
- **Current Location**: Blue pulsing circle marks your current position
- **Map Controls**: User location button and compass for easy navigation

### Map Features
- **3D Terrain**: Realistic elevation view using MapKit's standard elevation style
- **Auto-Zoom**: Map automatically adjusts zoom level for optimal viewing
- **Placeholder View**: When not recording, shows a friendly placeholder prompting you to start

## Enhanced Drive Statistics 📊

### Live Stats During Recording
Track 6 key metrics in real-time with color-coded stat cards:

1. **Time Elapsed** (Blue) - Live timer showing hours:minutes:seconds
2. **Distance** (Green) - Total distance traveled in miles
3. **Max Speed** (Red) - Highest speed reached during the drive
4. **Min Speed** (Orange) - Lowest speed recorded (excluding stops)
5. **Avg Speed** (Purple) - Average speed across entire drive
6. **Data Points** (Cyan) - Number of GPS coordinates captured

### Smart Speed Display
- **Large Current Speed**: 80pt bold display showing real-time speed
- **Color Indicators**: 
  - 🟢 Green: < 25 mph (slow/safe)
  - 🟠 Orange: 25-65 mph (moderate)
  - 🔴 Red: > 65 mph (fast)

### Automatic Updates
- Stats refresh every second during recording
- No manual refresh needed - everything updates live
- Smooth animations and transitions

## Recording Features 🎥

### Drive Recording
- **Start/Stop**: Simple button to begin and end recording
- **Automatic Tracking**: GPS updates captured automatically
- **Route Storage**: Complete path stored as JSON coordinates
- **Background Support**: Continues tracking when app is backgrounded (requires capability)

### Data Capture
- All GPS coordinates saved for route replay
- Speed readings at each point
- Distance calculations between points
- Timestamps for complete drive timeline

## Backend Integration 🔄

### API Sync
- Drives automatically saved to backend when stopped
- JWT authentication for secure data transfer
- User-specific drive filtering
- Offline support (queued for later sync - coming soon)

### Database Schema
```sql
drives:
  - id
  - user_id
  - start_time, end_time
  - start_latitude, start_longitude
  - end_latitude, end_longitude
  - distance (meters)
  - duration (seconds)
  - max_speed (m/s)
  - min_speed (m/s) ← NEW!
  - avg_speed (m/s)
  - route_data (JSON array)
  - created_at, updated_at
```

## User Interface 🎨

### Modern Design
- Clean, minimalist interface
- Color-coded information hierarchy
- Icon-based navigation
- Responsive layouts for all screen sizes

### Views
1. **Main View**: Map + speed + stats + controls
2. **History View**: List of all recorded drives
3. **Detail View**: Individual drive analysis
4. **Sign In View**: Apple Sign In integration

## Technical Details ⚙️

### iOS Features
- **SwiftUI**: Modern declarative UI framework
- **MapKit**: Native Apple maps integration
- **Core Location**: High-accuracy GPS tracking
- **Combine**: Reactive data flow
- **AuthenticationServices**: Secure Apple Sign In

### Performance
- Efficient map rendering with hardware acceleration
- Optimized location updates (not every GPS ping)
- Smart stat calculations to minimize CPU usage
- Preview-safe code (no crashes in Xcode previews)

## Coming Soon 🚀

### Planned Features
- **Leaderboard**: Compare speeds with friends
- **Route Replay**: Watch your drive played back on map
- **Statistics Dashboard**: Charts and graphs of driving patterns
- **Offline Mode**: Full functionality without internet
- **Drive Sharing**: Share your best drives
- **Apple Watch**: Track drives from your wrist
- **Widgets**: See current speed on home screen

## Requirements 📱

- iOS 18.0 or later
- Location permissions (Always for background tracking)
- Internet connection for API sync
- Apple ID for authentication

## Getting Started

1. Sign in with Apple ID
2. Grant location permissions
3. Tap "Start Recording" to begin tracking
4. Drive around and watch the map fill in
5. Tap "Stop Recording" to save your drive
6. View in history to see complete details

---

**Version**: 1.0
**Last Updated**: April 1, 2026
