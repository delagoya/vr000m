import CoreMotion
import Foundation

/// Turns accelerometer data into a speed estimate.
///
/// An accelerometer measures *acceleration*, not velocity. We integrate the
/// gravity-free acceleration (rotated into a fixed world frame so turning the
/// phone doesn't count as motion) into a velocity vector, and apply a leak so
/// the inevitable sensor drift bleeds away. Result: speed rises when you speed
/// up, and settles back to idle over a couple of seconds once you stop
/// accelerating.
final class MotionSpeedEstimator {
    private let manager = CMMotionManager()
    private var v = SIMD3<Double>(repeating: 0)   // m/s, world frame
    private var lastTimestamp: TimeInterval?

    /// Seconds for the velocity estimate to decay to ~37%.
    var leakTime: Double = 2.0
    /// Accelerations below this (in g) are treated as sensor noise.
    var deadband: Double = 0.015

    var isAvailable: Bool { manager.isDeviceMotionAvailable }

    /// Calls `onUpdate` on the main queue with the estimated speed in m/s.
    func start(onUpdate: @escaping (Double) -> Void) {
        guard manager.isDeviceMotionAvailable else { return }
        v = .zero
        lastTimestamp = nil
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            onUpdate(self.step(motion))
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }

    private func step(_ motion: CMDeviceMotion) -> Double {
        let dt: Double
        if let last = lastTimestamp { dt = min(max(motion.timestamp - last, 0), 0.1) } else { dt = 0 }
        lastTimestamp = motion.timestamp

        // Device frame → world frame (R transposed).
        let a = motion.userAcceleration
        let R = motion.attitude.rotationMatrix
        var world = SIMD3<Double>(
            a.x * R.m11 + a.y * R.m21 + a.z * R.m31,
            a.x * R.m12 + a.y * R.m22 + a.z * R.m32,
            a.x * R.m13 + a.y * R.m23 + a.z * R.m33
        )
        let mag = (world * world).sum().squareRoot()
        if mag < deadband { world = .zero }

        let decay = exp(-dt / leakTime)
        v = v * decay + world * 9.81 * dt
        return (v * v).sum().squareRoot()
    }
}
