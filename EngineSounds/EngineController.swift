import Observation
import UIKit

@Observable
@MainActor
final class EngineController {
    private(set) var isRunning = false
    private(set) var speed: Double = 0        // m/s estimate
    private(set) var throttle: Double = 0     // 0...1 driving the synth
    private(set) var errorMessage: String?

    var profile: SoundProfile = .jetson { didSet { synth.params.profile = profile } }
    var volume: Double = 0.8 { didSet { synth.params.volume = Float(volume) } }
    /// Speed (m/s) that maps to full throttle. Lower = more sensitive.
    var topSpeed: Double = 2.0
    /// Held "rev" button — also lets you test in the Simulator, which has no accelerometer.
    var manualRev = false { didSet { pushThrottle() } }

    var motionAvailable: Bool { motion.isAvailable }

    private let synth = EngineSynth()
    private let motion = MotionSpeedEstimator()

    func toggle() { isRunning ? stop() : start() }

    func start() {
        do {
            synth.params.profile = profile
            synth.params.volume = Float(volume)
            try synth.start()
        } catch {
            errorMessage = "Audio failed to start: \(error.localizedDescription)"
            return
        }
        motion.start { [weak self] speed in
            MainActor.assumeIsolated {
                self?.speed = speed
                self?.pushThrottle()
            }
        }
        UIApplication.shared.isIdleTimerDisabled = true
        isRunning = true
    }

    func stop() {
        motion.stop()
        synth.stop()
        UIApplication.shared.isIdleTimerDisabled = false
        speed = 0
        throttle = 0
        isRunning = false
    }

    private func pushThrottle() {
        let fromMotion = min(speed / topSpeed, 1)
        throttle = manualRev ? max(fromMotion, 1) : fromMotion
        synth.params.throttle = Float(throttle)
    }
}
