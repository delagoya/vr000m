import SwiftUI

struct ContentView: View {
    @State private var engine = EngineController()

    var body: some View {
        VStack(spacing: 28) {
            Text("Engine Sounds")
                .font(.largeTitle.bold())

            SpeedGauge(throttle: engine.throttle, speed: engine.speed)
                .frame(width: 240, height: 240)

            Picker("Sound", selection: $engine.profile) {
                ForEach(SoundProfile.allCases) { p in
                    Label(p.name, systemImage: p.symbol).tag(p)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 6) {
                Text("Sensitivity").font(.subheadline.weight(.semibold))
                // Slider runs "more sensitive" to the right → smaller top speed.
                Slider(value: Binding(get: { 5.5 - engine.topSpeed },
                                      set: { engine.topSpeed = 5.5 - $0 }),
                       in: 0.5...5.0)
                Text("Volume").font(.subheadline.weight(.semibold))
                Slider(value: $engine.volume, in: 0...1)
            }

            HStack(spacing: 16) {
                Button(engine.isRunning ? "Stop" : "Start") { engine.toggle() }
                    .buttonStyle(.borderedProminent)
                    .tint(engine.isRunning ? .red : .green)

                Text("Hold to Rev")
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(engine.manualRev ? Color.orange : Color.gray.opacity(0.2),
                                in: Capsule())
                    .opacity(engine.isRunning ? 1 : 0.4)
                    .onLongPressGesture(minimumDuration: 10, pressing: { pressing in
                        engine.manualRev = pressing && engine.isRunning
                    }, perform: {})
            }
            .controlSize(.large)

            if !engine.motionAvailable {
                Text("No motion sensor (Simulator?) — use Hold to Rev.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let err = engine.errorMessage {
                Text(err).font(.footnote).foregroundStyle(.red)
            }
        }
        .padding(24)
    }
}

struct SpeedGauge: View {
    let throttle: Double
    let speed: Double

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(Color.gray.opacity(0.2), style: .init(lineWidth: 18, lineCap: .round))
                .rotationEffect(.degrees(135))
            Circle()
                .trim(from: 0, to: 0.75 * throttle)
                .stroke(AngularGradient(colors: [.cyan, .purple, .pink],
                                        center: .center,
                                        startAngle: .degrees(0), endAngle: .degrees(270)),
                        style: .init(lineWidth: 18, lineCap: .round))
                .rotationEffect(.degrees(135))
                .animation(.easeOut(duration: 0.1), value: throttle)
            VStack(spacing: 2) {
                Text("\(Int(throttle * 100))")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("throttle %").font(.caption).foregroundStyle(.secondary)
                Text(String(format: "%.1f m/s est.", speed))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
