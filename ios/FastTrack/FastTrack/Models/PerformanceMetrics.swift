import Foundation

// MARK: - Performance Metrics

struct PerformanceMetrics {
    // Basic metrics (existing)
    let maxSpeed: Double
    let avgSpeed: Double
    let minSpeed: Double
    let distance: Double
    let duration: Double
    
    // Advanced metrics (new)
    let accelerationMetrics: AccelerationMetrics
    let brakingMetrics: BrakingMetrics
    let corneringMetrics: CorneringMetrics
    let smoothnessMetrics: SmoothnessMetrics
    let weatherConditions: WeatherConditions?
}

// MARK: - Acceleration Analysis

struct AccelerationMetrics {
    let zeroToSixty: Double?        // 0-60 mph time in seconds
    let zeroToHundred: Double?      // 0-100 mph time in seconds
    let quarterMileTime: Double?    // 1/4 mile time in seconds
    let quarterMileTrapSpeed: Double? // Speed at end of 1/4 mile
    let maxAcceleration: Double     // m/s²
    let launchConsistency: Double   // 0-100 score, higher = smoother
    
    var zeroToSixtyCategory: String {
        guard let time = zeroToSixty else { return "Unknown" }
        switch time {
        case 0..<3.0: return "Hypercar" // Sub-3 second
        case 3.0..<4.0: return "Supercar" // 3-4 seconds
        case 4.0..<6.0: return "Sports Car" // 4-6 seconds
        case 6.0..<8.0: return "Quick" // 6-8 seconds
        case 8.0..<10.0: return "Moderate" // 8-10 seconds
        default: return "Leisurely" // 10+ seconds
        }
    }
}

// MARK: - Braking Analysis

struct BrakingMetrics {
    let sixtyToZero: Double?        // 60-0 mph braking distance in feet
    let hundredToZero: Double?      // 100-0 mph braking distance in feet
    let maxDeceleration: Double     // m/s²
    let brakingConsistency: Double  // 0-100 score
    let emergencyStops: Int         // Count of hard braking events
    
    var brakingGrade: String {
        guard let distance = sixtyToZero else { return "Unknown" }
        switch distance {
        case 0..<100: return "Excellent" // Race car territory
        case 100..<120: return "Very Good" // Performance cars
        case 120..<140: return "Good" // Average sports cars
        case 140..<160: return "Average" // Typical cars
        default: return "Poor" // Heavy vehicles/worn brakes
        }
    }
}

// MARK: - Cornering Analysis

struct CorneringMetrics {
    let avgCornerSpeed: Double      // Average speed through turns
    let maxLateralG: Double         // Peak lateral G-force
    let corneringConsistency: Double // How consistent through similar turns
    let apexAccuracy: Double        // 0-100 score for racing line
    let cornerCount: Int            // Number of turns detected
    
    var corneringGrade: String {
        switch maxLateralG {
        case 0.8...: return "Race Driver" // 0.8+ G
        case 0.6..<0.8: return "Enthusiast" // 0.6-0.8 G
        case 0.4..<0.6: return "Spirited" // 0.4-0.6 G
        case 0.2..<0.4: return "Cautious" // 0.2-0.4 G
        default: return "Gentle" // <0.2 G
        }
    }
}

// MARK: - Driving Smoothness

struct SmoothnessMetrics {
    let accelerationSmoothness: Double // 0-100, higher = smoother
    let brakingSmoothness: Double      // 0-100, higher = smoother
    let steeringSmoothness: Double     // 0-100, higher = smoother
    let overallSmoothness: Double      // Combined score
    let jerkiness: Double              // Sudden inputs per mile
    
    var drivingStyle: String {
        switch overallSmoothness {
        case 90...: return "Silk Smooth"
        case 80..<90: return "Very Smooth"
        case 70..<80: return "Smooth"
        case 60..<70: return "Moderate"
        case 50..<60: return "Sporty"
        case 40..<50: return "Aggressive"
        default: return "Very Aggressive"
        }
    }
}

// MARK: - Weather & Conditions

struct WeatherConditions: Codable {
    let temperature: Double?    // Celsius
    let humidity: Double?       // 0-100%
    let condition: String       // "Clear", "Rain", "Snow", etc.
    let windSpeed: Double?      // km/h
    let roadCondition: String   // "Dry", "Wet", "Snow", "Ice"
    
    var performanceImpact: String {
        switch condition.lowercased() {
        case "clear", "sunny": return "Optimal"
        case "cloudy", "overcast": return "Good"
        case "light rain", "drizzle": return "Reduced"
        case "rain", "heavy rain": return "Significantly Reduced"
        case "snow", "ice": return "Poor"
        default: return "Unknown"
        }
    }
}

// MARK: - Performance Analysis Extensions

extension Drive {
    func calculatePerformanceMetrics() -> PerformanceMetrics? {
        guard let routeData = routeData, !routeData.isEmpty else { return nil }
        
        let points = parseRoutePoints()
        guard points.count >= 10 else { return nil } // Need enough data points
        
        return PerformanceMetrics(
            maxSpeed: maxSpeed,
            avgSpeed: avgSpeed,
            minSpeed: minSpeed,
            distance: distance,
            duration: duration,
            accelerationMetrics: calculateAcceleration(from: points),
            brakingMetrics: calculateBraking(from: points),
            corneringMetrics: calculateCornering(from: points),
            smoothnessMetrics: calculateSmoothness(from: points),
            weatherConditions: nil // TODO: Integrate weather API
        )
    }
    
    private func parseRoutePoints() -> [GPSPoint] {
        guard let routeData = routeData,
              let data = routeData.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        
        return json.compactMap { point in
            guard let lat = point["lat"] as? Double,
                  let lng = point["lng"] as? Double,
                  let speed = point["speed"] as? Double,
                  let timestamp = point["timestamp"] as? Double else { return nil }
            
            return GPSPoint(
                latitude: lat,
                longitude: lng,
                speed: speed,
                timestamp: Date(timeIntervalSince1970: timestamp),
                altitude: point["altitude"] as? Double,
                heading: point["heading"] as? Double,
                accuracy: point["accuracy"] as? Double
            )
        }
    }
    
    private func calculateAcceleration(from points: [GPSPoint]) -> AccelerationMetrics {
        var zeroToSixty: Double?
        var zeroToHundred: Double?
        var quarterMileTime: Double?
        var quarterMileTrapSpeed: Double?
        var maxAcceleration: Double = 0
        var accelerations: [Double] = []
        
        // Find acceleration runs (sustained acceleration periods)
        for i in 1..<points.count {
            let prevSpeed = points[i-1].speed * 2.23694 // Convert m/s to mph
            let currentSpeed = points[i].speed * 2.23694
            let timeDiff = points[i].timestamp.timeIntervalSince(points[i-1].timestamp)
            
            if timeDiff > 0 {
                let acceleration = (currentSpeed - prevSpeed) / timeDiff
                accelerations.append(acceleration)
                maxAcceleration = max(maxAcceleration, acceleration)
                
                // Check for 0-60 mph time
                if zeroToSixty == nil && prevSpeed < 5 && currentSpeed >= 60 {
                    let startTime = findAccelerationStart(from: points, endIndex: i, targetSpeed: 5)
                    if let start = startTime {
                        zeroToSixty = points[i].timestamp.timeIntervalSince(start)
                    }
                }
                
                // Check for 0-100 mph time
                if zeroToHundred == nil && prevSpeed < 5 && currentSpeed >= 100 {
                    let startTime = findAccelerationStart(from: points, endIndex: i, targetSpeed: 5)
                    if let start = startTime {
                        zeroToHundred = points[i].timestamp.timeIntervalSince(start)
                    }
                }
            }
        }
        
        // Calculate launch consistency (lower variance = more consistent)
        let launchConsistency = calculateConsistency(from: accelerations)
        
        return AccelerationMetrics(
            zeroToSixty: zeroToSixty,
            zeroToHundred: zeroToHundred,
            quarterMileTime: quarterMileTime,
            quarterMileTrapSpeed: quarterMileTrapSpeed,
            maxAcceleration: maxAcceleration * 0.44704, // Convert mph/s to m/s²
            launchConsistency: launchConsistency
        )
    }
    
    private func calculateBraking(from points: [GPSPoint]) -> BrakingMetrics {
        var maxDeceleration: Double = 0
        var decelerations: [Double] = []
        var emergencyStops = 0
        
        for i in 1..<points.count {
            let prevSpeed = points[i-1].speed * 2.23694 // Convert to mph
            let currentSpeed = points[i].speed * 2.23694
            let timeDiff = points[i].timestamp.timeIntervalSince(points[i-1].timestamp)
            
            if timeDiff > 0 && currentSpeed < prevSpeed {
                let deceleration = abs(currentSpeed - prevSpeed) / timeDiff
                decelerations.append(deceleration)
                maxDeceleration = max(maxDeceleration, deceleration)
                
                // Detect emergency stops (deceleration > 20 mph/s ≈ 0.25G)
                if deceleration > 20 {
                    emergencyStops += 1
                }
            }
        }
        
        let brakingConsistency = calculateConsistency(from: decelerations)
        
        return BrakingMetrics(
            sixtyToZero: nil, // TODO: Calculate from deceleration data
            hundredToZero: nil,
            maxDeceleration: maxDeceleration * 0.44704, // Convert to m/s²
            brakingConsistency: brakingConsistency,
            emergencyStops: emergencyStops
        )
    }
    
    private func calculateCornering(from points: [GPSPoint]) -> CorneringMetrics {
        var cornerSpeeds: [Double] = []
        var maxLateralG: Double = 0
        var cornerCount = 0
        
        for i in 2..<points.count-1 {
            let prev = points[i-1]
            let current = points[i]
            let next = points[i+1]
            
            // Detect corners by heading change
            if let prevHeading = prev.heading,
               let currentHeading = current.heading,
               let nextHeading = next.heading {
                
                let headingChange1 = abs(currentHeading - prevHeading)
                let headingChange2 = abs(nextHeading - currentHeading)
                
                // Significant heading change indicates a corner
                if headingChange1 > 10 || headingChange2 > 10 {
                    cornerCount += 1
                    cornerSpeeds.append(current.speed * 2.23694) // Convert to mph
                    
                    // Estimate lateral G-force (simplified)
                    let speed = current.speed // m/s
                    let headingChangeRate = max(headingChange1, headingChange2) * .pi / 180 // rad
                    let lateralAccel = speed * headingChangeRate // Very rough approximation
                    let lateralG = lateralAccel / 9.81
                    
                    maxLateralG = max(maxLateralG, lateralG)
                }
            }
        }
        
        let avgCornerSpeed = cornerSpeeds.isEmpty ? 0 : cornerSpeeds.reduce(0, +) / Double(cornerSpeeds.count)
        let corneringConsistency = calculateConsistency(from: cornerSpeeds)
        
        return CorneringMetrics(
            avgCornerSpeed: avgCornerSpeed,
            maxLateralG: maxLateralG,
            corneringConsistency: corneringConsistency,
            apexAccuracy: 50, // Placeholder - would need racing line data
            cornerCount: cornerCount
        )
    }
    
    private func calculateSmoothness(from points: [GPSPoint]) -> SmoothnessMetrics {
        var speedChanges: [Double] = []
        var accelerations: [Double] = []
        
        for i in 1..<points.count {
            let timeDiff = points[i].timestamp.timeIntervalSince(points[i-1].timestamp)
            if timeDiff > 0 {
                let speedChange = abs(points[i].speed - points[i-1].speed)
                speedChanges.append(speedChange)
                
                let acceleration = speedChange / timeDiff
                accelerations.append(acceleration)
            }
        }
        
        let accelerationSmoothness = 100 - min(100, calculateVariance(from: accelerations) * 10)
        let overallSmoothness = accelerationSmoothness
        let jerkiness = accelerations.filter { $0 > 2.0 }.count // Sudden changes per drive
        
        return SmoothnessMetrics(
            accelerationSmoothness: accelerationSmoothness,
            brakingSmoothness: accelerationSmoothness, // Simplified for now
            steeringSmoothness: accelerationSmoothness,
            overallSmoothness: overallSmoothness,
            jerkiness: Double(jerkiness)
        )
    }
    
    private func findAccelerationStart(from points: [GPSPoint], endIndex: Int, targetSpeed: Double) -> Date? {
        for i in (0..<endIndex).reversed() {
            if points[i].speed * 2.23694 < targetSpeed {
                return points[i].timestamp
            }
        }
        return nil
    }
    
    private func calculateConsistency(from values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let variance = calculateVariance(from: values)
        return max(0, 100 - variance * 10) // Convert to 0-100 scale
    }
    
    private func calculateVariance(from values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / Double(values.count - 1)
        return sqrt(variance) // Return standard deviation
    }
}

// MARK: - GPS Point Model

struct GPSPoint {
    let latitude: Double
    let longitude: Double
    let speed: Double // m/s
    let timestamp: Date
    let altitude: Double?
    let heading: Double?
    let accuracy: Double?
}
