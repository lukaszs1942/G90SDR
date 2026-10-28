import Foundation

/// UI-facing wrapper around `CWDemodulator`. `process` runs on the audio thread; published state is updated on main.
final class CWDecoder: ObservableObject {
    @Published var enabled = true { didSet { withLock { enabledFlag = enabled } } }
    @Published var autoPitch = true
    @Published var pitch: Double = 700 { didSet { withLock { demod.toneHz = pitch } } }
    @Published private(set) var text = ""
    @Published private(set) var wpm = 20
    @Published private(set) var keyed = false

    private static let maxChars = 2000
    private let lock = NSLock()
    private var demod = CWDemodulator()
    private var enabledFlag = true
    private var lastKeyed = false
    private var lastWPM = 20

    func clear() {
        text = ""
        withLock { demod.reset() }
    }

    /// Audio thread.
    func process(_ samples: UnsafeBufferPointer<Float>, sampleRate: Double) {
        lock.lock()
        guard enabledFlag else { lock.unlock(); return }
        let out = demod.process(samples, sampleRate: sampleRate)
        let key = demod.keyDown, rate = demod.wpm
        lock.unlock()

        guard !out.isEmpty || key != lastKeyed || rate != lastWPM else { return }
        lastKeyed = key; lastWPM = rate
        DispatchQueue.main.async {
            self.keyed = key
            self.wpm = rate
            if !out.isEmpty {
                self.text += out
                if self.text.count > Self.maxChars { self.text = String(self.text.suffix(Self.maxChars)) }
            }
        }
    }

    /// Main thread, called with each FFT row (dB, low → high frequency). Pulls `pitch` towards a clear CW tone.
    func observe(row: [Float], binHz: Double) {
        guard autoPitch, enabled, binHz > 0 else { return }
        let lo = Int(300 / binHz), hi = min(row.count - 1, Int(1200 / binHz))
        guard hi > lo else { return }
        let band = row[lo...hi]
        guard let peakIndex = band.indices.max(by: { row[$0] < row[$1] }) else { return }
        let median = band.sorted()[band.count / 2]
        guard row[peakIndex] - median > 12 else { return }   // no clear tone
        let target = Double(peakIndex) * binHz
        if abs(target - pitch) > 3 { pitch += (target - pitch) * 0.2 }
    }

    private func withLock(_ body: () -> Void) {
        lock.lock(); body(); lock.unlock()
    }
}
