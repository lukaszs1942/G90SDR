import SwiftUI

/// Holds the frequency entry text. Used instead of @State, whose macro plugin ships only with full Xcode.
final class FrequencyEntry: ObservableObject {
    @Published var text = ""
}

struct ContentView: View {
    @StateObject private var radio = RadioController()
    @StateObject private var audio = AudioSpectrum()
    @StateObject private var waterfall = Waterfall()
    @StateObject private var entry = FrequencyEntry()

    private let bands: [(String, Int)] = [
        ("80m", 3_700_000), ("40m", 7_100_000), ("30m", 10_120_000), ("20m", 14_200_000),
        ("17m", 18_100_000), ("15m", 21_200_000), ("12m", 24_950_000), ("10m", 28_400_000)
    ]

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            controls.frame(width: 300)
            VStack(alignment: .leading) {
                audioBar
                WaterfallView(waterfall: waterfall)
            }
        }
        .padding()
        .frame(minWidth: 960, minHeight: 640)
        .onAppear { audio.onRow = { waterfall.push($0) } }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox("CAT") {
                VStack(alignment: .leading) {
                    HStack {
                        Picker("Port", selection: $radio.selectedPort) {
                            ForEach(radio.ports, id: \.self) { Text($0.replacingOccurrences(of: "/dev/", with: "")).tag($0) }
                        }
                        Button("↻") { radio.refreshPorts() }
                    }
                    Button(radio.connected ? "Disconnect" : "Connect") {
                        radio.connected ? radio.disconnect() : radio.connect()
                    }
                    Text(radio.status).font(.caption).foregroundStyle(.secondary)
                }
            }

            Text(formatted(radio.frequencyHz))
                .font(.system(size: 38, weight: .medium, design: .monospaced))
                .minimumScaleFactor(0.6)

            HStack {
                ForEach([-1000, -100, 100, 1000], id: \.self) { d in
                    Button(d > 0 ? "+\(d)" : "\(d)") { radio.tune(by: d) }
                }
            }

            HStack {
                TextField("MHz", text: $entry.text).frame(width: 110)
                    .onSubmit(setFromText)
                Button("Set", action: setFromText)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4)) {
                ForEach(bands, id: \.0) { band in
                    Button(band.0) { radio.setFrequency(band.1) }
                }
            }

            Picker("Mode", selection: Binding(get: { radio.mode }, set: { if let m = $0 { radio.setMode(m) } })) {
                Text("—").tag(RadioMode?.none)
                ForEach(RadioMode.allCases) { Text($0.label).tag(RadioMode?.some($0)) }
            }

            VStack(alignment: .leading) {
                Text("S-meter").font(.caption)
                ProgressView(value: Double(min(radio.sMeter, 255)), total: 255)
            }
            Spacer()
        }
    }

    private var audioBar: some View {
        VStack(alignment: .leading) {
            HStack {
                Picker("Audio in", selection: $audio.selectedDevice) {
                    ForEach(audio.devices) { Text($0.name).tag($0.id) }
                }
                .frame(maxWidth: 380)
                Button("↻") { audio.refreshDevices() }
                Button(audio.running ? "Stop" : "Start") { audio.running ? audio.stop() : audio.start() }
            }
            HStack {
                Text("Floor").font(.caption)
                Slider(value: $waterfall.floorDB, in: -140...(-40))
                Text("Ceiling").font(.caption)
                Slider(value: $waterfall.ceilingDB, in: -80...0)
            }
            if let e = audio.error { Text(e).font(.caption).foregroundStyle(.red) }
        }
    }

    private func setFromText() {
        guard let mhz = Double(entry.text.replacingOccurrences(of: ",", with: ".")) else { return }
        radio.setFrequency(Int((mhz * 1_000_000).rounded()))
    }

    private func formatted(_ hz: Int) -> String {
        guard hz > 0 else { return "-.---.---" }
        return String(format: "%d.%03d.%03d", hz / 1_000_000, (hz / 1000) % 1000, hz % 1000)
    }
}
