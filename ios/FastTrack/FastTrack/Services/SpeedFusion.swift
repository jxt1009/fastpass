import Foundation
import CoreMotion

// MARK: - 1D Kalman Filter for Speed
//
// State:     speed (m/s)
// Predict:   integrate longitudinal acceleration from IMU at 25 Hz
// Correct:   GPS Doppler speed, weighted by `speedAccuracy` from CLLocation
//
// GPS Doppler is the most accurate speed source on iPhone (better than
// position-delta), but only arrives ~1 Hz and can spike. The IMU runs
// at 25 Hz and fills the gaps, giving smooth real-time speed.

class SpeedFusion {

    // MARK: - Kalman state
    private(set) var speed: Double = 0          // m/s
    private var P: Double = 4.0                  // variance (m/s)²

    // Noise tuning
    private let Q: Double = 0.3   // process noise variance per second (IMU drift ~0.55 m/s per √s)
    private let R_min: Double = 0.16  // min GPS measurement noise (0.4 m/s std dev)

    // Course tracking for longitudinal projection
    private var lastCourse: Double = -1   // degrees, -1 = invalid
    private var lastGPSSpeed: Double = 0

    // MARK: - Predict (called at 25 Hz from CMDeviceMotion)
    /// `longAccelG` = longitudinal acceleration in **g** units, from IMU projected onto travel direction
    func predict(longAccelG: Double, dt: Double) {
        let a = longAccelG * 9.81          // convert to m/s²
        speed += a * dt
        speed = max(0, speed)              // speed is never negative
        P += Q * dt                        // grow uncertainty over time
    }

    // MARK: - Update (called at ~1 Hz when GPS fires)
    /// `gpsSpeedAccuracy` comes from CLLocation.speedAccuracy (m/s std dev); use -1 if unavailable
    func update(gpsSpeed: Double, gpsSpeedAccuracy: Double) {
        guard gpsSpeed >= 0 else { return }  // GPS returns -1 when invalid

        let sigma = gpsSpeedAccuracy > 0 ? gpsSpeedAccuracy : 1.5
        let R = max(sigma * sigma, R_min)

        let K = P / (P + R)               // Kalman gain
        let residual = gpsSpeed - speed
        // Reject wild outliers (> 20 m/s jump from prediction)
        guard abs(residual) < 20 else {
            // Just accept the GPS value wholesale — we've drifted badly
            speed = gpsSpeed
            P = R
            return
        }
        speed = speed + K * residual
        speed = max(0, speed)
        P = (1 - K) * P
        P = max(P, 0.001)                 // floor variance

        lastGPSSpeed = gpsSpeed
    }

    func updateCourse(_ course: Double) {
        if course >= 0 { lastCourse = course }
    }

    func reset() {
        speed = 0
        P = 4.0
        lastCourse = -1
        lastGPSSpeed = 0
    }
}

// MARK: - IMU Longitudinal Acceleration Extractor
//
// Projects CMDeviceMotion userAcceleration (device frame) onto the
// vehicle's forward direction using the device attitude and GPS course.
//
// Reference frame: XTrueNorthZVertical
//   X = True North, Y = East, Z = Up
// GPS course: degrees clockwise from True North
//   Forward unit vector = (cos θ, sin θ, 0) in (N, E, Up)

struct IMUProjector {

    // Returns longitudinal acceleration in **g** (positive = forward/accelerating)
    static func longitudinalAccelG(from motion: CMDeviceMotion, course: Double) -> Double? {
        guard course >= 0 else { return nil }

        let R = motion.attitude.rotationMatrix
        let a = motion.userAcceleration  // g's, gravity removed

        // Rotate from device frame → world frame (North, East, Up)
        let aN = R.m11 * a.x + R.m12 * a.y + R.m13 * a.z   // North
        let aE = R.m21 * a.x + R.m22 * a.y + R.m23 * a.z   // East

        // Dot product with forward direction
        let θ = course * .pi / 180.0
        let longG = aN * cos(θ) + aE * sin(θ)

        return longG
    }

    // Fallback when course is unavailable: horizontal acceleration magnitude,
    // signed by recent speed trend (positive if last GPS reading was higher than
    // current filter speed).
    static func fallbackAccelG(from motion: CMDeviceMotion, speedTrend: Double) -> Double {
        let a = motion.userAcceleration
        let mag = sqrt(a.x * a.x + a.y * a.y)  // horizontal magnitude
        return mag * (speedTrend >= 0 ? 1.0 : -1.0)
    }
}
