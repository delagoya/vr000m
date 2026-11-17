import AVFoundation

/// Real-time engine synthesizer. All sound is generated procedurally, so pitch
/// and volume follow the throttle continuously with no samples or loops.
final class EngineSynth {
    /// Values written from the main thread and read on the audio thread.
    /// Aligned 32-bit loads/stores are atomic on arm64, which is sufficient
    /// for these "latest value wins" control parameters.
    final class Params {
        var throttle: Float = 0      // 0...1
        var volume: Float = 0.8      // 0...1
        var profile: SoundProfile = .jetson
    }

    let params = Params()
    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)

        let sampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let dsp = EngineDSP(sampleRate: Float(sampleRate))
        let params = self.params

        let node = AVAudioSourceNode(format: format) { _, _, frameCount, bufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            guard let out = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            dsp.render(into: out,
                       frames: Int(frameCount),
                       throttle: params.throttle,
                       volume: params.volume,
                       profile: params.profile)
            // Copy to any extra channels.
            for i in 1..<max(buffers.count, 1) {
                buffers[i].mData?.copyMemory(from: out, byteCount: Int(frameCount) * MemoryLayout<Float>.size)
            }
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        source = node
        try engine.start()
    }

    func stop() {
        engine.stop()
        if let source { engine.detach(source) }
        source = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// Pure DSP state; lives on the audio render thread only.
final class EngineDSP {
    private let sr: Float
    private let twoPi = Float.pi * 2

    // Smoothed controls (avoid zipper noise when throttle jumps).
    private var t: Float = 0
    private var vol: Float = 0
    private let tCoef: Float
    private let volCoef: Float

    // Oscillator phases (radians or cycles as noted).
    private var p1: Float = 0       // main voice (rad)
    private var p2: Float = 0       // second voice (rad)
    private var vib: Float = 0      // vibrato LFO (rad)
    private var bub: Float = 0      // "bubble" AM LFO (rad)
    private var cyc: Float = 0      // combustion cycle (0..<4, four firings)
    private var lp: Float = 0       // low-pass stage 1
    private var lp2: Float = 0      // low-pass stage 2
    private var rng: UInt32 = 0x1234_5678

    init(sampleRate: Float) {
        sr = sampleRate
        tCoef = 1 - exp(-1 / (sampleRate * 0.12))   // ~120 ms throttle glide
        volCoef = 1 - exp(-1 / (sampleRate * 0.05))
    }

    func render(into out: UnsafeMutablePointer<Float>, frames: Int,
                throttle: Float, volume: Float, profile: SoundProfile) {
        let target = min(max(throttle, 0), 1)
        for i in 0..<frames {
            t += (target - t) * tCoef
            vol += (volume - vol) * volCoef
            let s: Float
            switch profile {
            case .jetson:   s = jetson()
            case .v8:       s = v8()
            case .electric: s = electric()
            }
            out[i] = tanh(s * vol * 1.2)   // soft clip
        }
    }

    // MARK: - Voices

    /// Futuristic hover-car: theremin-like tone sweeping two octaves, with a
    /// vibrato that speeds up with throttle, a "bubbly" amplitude pulse, and a
    /// quiet detuned fifth for a spacey shimmer.
    private func jetson() -> Float {
        let base = 260 * pow(2, t * 2)                 // 260 → 1040 Hz
        let vibRate = 5.5 + 4 * t                      // Hz
        let vibDepth = 0.02 + 0.035 * t                // ± fraction of pitch
        vib = wrap(vib + twoPi * vibRate / sr)
        let f = base * (1 + vibDepth * sin(vib))

        p1 = wrap(p1 + twoPi * f / sr)
        p2 = wrap(p2 + twoPi * f * 1.503 / sr)         // slightly sharp fifth

        let tone = sin(p1) + 0.35 * sin(2 * p1) + 0.12 * sin(3 * p1)
        let shimmer = 0.22 * sin(p2)

        let bubRate = 12 + 22 * t
        bub = wrap(bub + twoPi * bubRate / sr)
        let am = 0.78 + 0.22 * sin(bub)

        let amp = 0.2 + 0.8 * t                         // louder with speed
        return (tone + shimmer) * am * amp * 0.38
    }

    /// Combustion engine: deep, bass-heavy rumble. Slow-decaying pulse per
    /// cylinder firing with an uneven 4-firing lope (cross-plane burble), a
    /// firing-rate bass tone plus 2nd harmonic, light intake noise, and a
    /// two-pole low-pass that only partly opens with throttle.
    private static let lopePattern: [Float] = [1.0, 0.62, 0.88, 0.55]

    private func v8() -> Float {
        let fire = 36 + 130 * t                        // firings/s (pitch)
        cyc += fire / sr
        if cyc >= 4 { cyc -= 4 }
        let idx = Int(cyc)
        let phase = cyc - Float(idx)
        let lope = Self.lopePattern[idx]

        let pulse = (exp(-phase * 5) - 0.2) * lope
        let bass = (0.5 * sin(twoPi * phase) + 0.2 * sin(2 * twoPi * phase)) * (0.6 + 0.4 * lope)
        let noise = nextNoise() * (0.02 + 0.08 * t)
        let raw = pulse + bass + noise

        let cutoff = 300 + 1300 * t
        let a = 1 - exp(-twoPi * cutoff / sr)
        lp += (raw - lp) * a
        lp2 += (lp - lp2) * a

        // Saturate so phone speakers (weak below ~150 Hz) still convey the
        // bass through the harmonics it generates.
        let amp = 0.35 + 0.65 * t
        return tanh(lp2 * 3) * amp * 0.5
    }

    /// Electric motor: clean sine whine rising three octaves with an
    /// inverter-style upper partial.
    private func electric() -> Float {
        let f = 160 * pow(2, t * 3)                    // 160 → 1280 Hz
        p1 = wrap(p1 + twoPi * f / sr)
        p2 = wrap(p2 + twoPi * f * 3.02 / sr)
        let s = sin(p1) + 0.18 * sin(p2) + 0.04 * nextNoise()
        let amp = 0.12 + 0.88 * t
        return s * amp * 0.4
    }

    // MARK: - Helpers

    @inline(__always) private func wrap(_ x: Float) -> Float {
        x >= twoPi ? x - twoPi : x
    }

    @inline(__always) private func nextNoise() -> Float {
        rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5   // xorshift32
        return Float(rng) / Float(UInt32.max) * 2 - 1
    }
}
