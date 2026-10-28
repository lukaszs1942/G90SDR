import Foundation

/// Audio → text Morse decoder core. No UI or threading; feed it sample blocks, get decoded text back.
///
/// Pipeline: Goertzel filter at the CW pitch (20 ms window, 5 ms hop) → adaptive threshold with hysteresis
/// → mark/gap timing → dit/dah classification with self-adjusting speed → character and word breaks.
struct CWDemodulator {
    var toneHz = 700.0
    private(set) var wpm = 20
    private(set) var keyDown = false

    private static let hopMs = 5.0
    private static let windowMs = 20.0
    private static let minMarkMs = 15.0     // shorter "marks" are treated as noise

    private var sampleRate = 0.0
    private var hop = 0
    private var window = 0
    private var buffer: [Float] = []

    private var peak: Float = 1e-3
    private var noise: Float = 1e-3
    private var warmup = 100                 // hops (~0.5 s) spent learning the noise floor before decoding
    private var run = 0                      // hops spent in the current key state
    private var ditMs = 80.0                 // running estimates of dit and dah length
    private var dahMs = 240.0
    private var marks: [Double] = []         // durations (ms) of the current character's marks
    private var learned = 0                  // marks seen so far; adapts faster while small
    private var charFlushed = true
    private var spaceEmitted = true

    /// Returns any newly decoded text (characters, and spaces between words).
    mutating func process(_ samples: UnsafeBufferPointer<Float>, sampleRate fs: Double) -> String {
        if fs != sampleRate {
            sampleRate = fs
            hop = max(1, Int(fs * Self.hopMs / 1000))
            window = max(hop, Int(fs * Self.windowMs / 1000))
            buffer.removeAll()
        }
        buffer.append(contentsOf: samples)
        var out = ""
        var consumed = 0
        while buffer.count - consumed >= window {
            step(magnitude(at: consumed), &out)
            consumed += hop
        }
        buffer.removeFirst(consumed)
        return out
    }

    mutating func reset() {
        buffer.removeAll(); marks.removeAll(); run = 0; keyDown = false; warmup = 100
        charFlushed = true; spaceEmitted = true
    }

    // MARK: - DSP

    /// Goertzel amplitude of `toneHz` over one window starting at `start`.
    private func magnitude(at start: Int) -> Float {
        let coeff = Float(2 * cos(2 * Double.pi * toneHz / sampleRate))
        var s1: Float = 0, s2: Float = 0
        buffer.withUnsafeBufferPointer { p in
            for i in start..<(start + window) {
                let s0 = p[i] + coeff * s1 - s2
                s2 = s1; s1 = s0
            }
        }
        let power = max(s1 * s1 + s2 * s2 - coeff * s1 * s2, 0)
        return 2 * power.squareRoot() / Float(window)
    }

    private mutating func step(_ mag: Float, _ out: inout String) {
        if warmup > 0 {
            warmup -= 1
            noise += (mag - noise) * 0.1
            peak = max(peak * 0.98, mag)
            return
        }
        peak = max(mag, peak * 0.9995)                          // ~10 s decay
        if !keyDown { noise += (mag - noise) * 0.01 }
        let valid = peak > 0.002 && peak > noise * 3
        let thrOn = noise + 0.5 * (peak - noise)
        let thrOff = noise + 0.35 * (peak - noise)              // hysteresis
        let isOn = valid && (keyDown ? mag > thrOff : mag > thrOn)

        if isOn == keyDown {
            run += 1
            if !keyDown { checkGap(&out) }
            return
        }
        if keyDown { markEnded(Double(run) * Self.hopMs) }
        keyDown = isOn
        run = 1
    }

    // MARK: - Timing

    private var unitMs: Double { (ditMs + dahMs / 3) / 2 }

    private mutating func markEnded(_ ms: Double) {
        guard ms >= Self.minMarkMs else { return }
        marks.append(ms)
        charFlushed = false
        spaceEmitted = false
    }

    /// Turns the collected marks into dits/dahs. A character containing both kinds calibrates itself
    /// (split between the shortest and longest mark), so the very first character is not guesswork.
    private mutating func classifyCharacter() -> String {
        var threshold = (ditMs * dahMs).squareRoot()
        if let lo = marks.min(), let hi = marks.max(), hi / lo > 2 {
            threshold = (lo * hi).squareRoot()
        }
        var symbols = ""
        for ms in marks {
            let rate = learned < 10 ? 0.5 : 0.25
            if ms > threshold {
                symbols += "-"
                dahMs += rate * (ms - dahMs)
                ditMs += 0.1 * (dahMs / 3 - ditMs)
            } else {
                symbols += "."
                ditMs += rate * (ms - ditMs)
                dahMs += 0.1 * (3 * ditMs - dahMs)
            }
            learned += 1
        }
        marks.removeAll()
        ditMs = min(max(ditMs, 18), 300)
        dahMs = min(max(dahMs, 3 * 18), 900)
        wpm = Int((1200 / unitMs).rounded())
        return symbols
    }

    private mutating func checkGap(_ out: inout String) {
        let ms = Double(run) * Self.hopMs
        // Until calibrated, trust the shortest mark heard so far if it is shorter than the default unit,
        // so fast senders get their character gaps recognised from the very first letter.
        var unit = unitMs
        if learned < 10, let shortest = marks.min() { unit = min(unit, shortest) }
        if !charFlushed && ms > 2 * unit {
            out += Self.table[classifyCharacter()] ?? "?"
            charFlushed = true
        }
        if !spaceEmitted && charFlushed && ms > 5 * unitMs {
            out += " "
            spaceEmitted = true
        }
    }

    private static let table: [String: String] = [
        ".-": "A", "-...": "B", "-.-.": "C", "-..": "D", ".": "E", "..-.": "F", "--.": "G", "....": "H",
        "..": "I", ".---": "J", "-.-": "K", ".-..": "L", "--": "M", "-.": "N", "---": "O", ".--.": "P",
        "--.-": "Q", ".-.": "R", "...": "S", "-": "T", "..-": "U", "...-": "V", ".--": "W", "-..-": "X",
        "-.--": "Y", "--..": "Z",
        "-----": "0", ".----": "1", "..---": "2", "...--": "3", "....-": "4",
        ".....": "5", "-....": "6", "--...": "7", "---..": "8", "----.": "9",
        ".-.-.-": ".", "--..--": ",", "..--..": "?", "-..-.": "/", "-...-": "=", ".-.-.": "+",
        "-....-": "-", "-.--.": "(", "-.--.-": ")", "---...": ":", ".--.-.": "@", ".----.": "'",
        ".-..-.": "\"", "...-.-": "<SK>", ".-...": "<AS>", "........": "<ERR>"
    ]
}
