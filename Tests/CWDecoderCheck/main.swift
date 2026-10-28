import Foundation

let morse: [Character: String] = [
    "A": ".-", "B": "-...", "C": "-.-.", "D": "-..", "E": ".", "F": "..-.", "G": "--.", "H": "....", "I": "..",
    "J": ".---", "K": "-.-", "L": ".-..", "M": "--", "N": "-.", "O": "---", "P": ".--.", "Q": "--.-", "R": ".-.",
    "S": "...", "T": "-", "U": "..-", "V": "...-", "W": ".--", "X": "-..-", "Y": "-.--", "Z": "--..",
    "0": "-----", "1": ".----", "2": "..---", "3": "...--", "4": "....-", "5": ".....", "6": "-....",
    "7": "--...", "8": "---..", "9": "----.", "/": "-..-.", "?": "..--.."
]

func synth(_ text: String, wpm: Double, tone: Double, fs: Double, noiseAmp: Float, signalAmp: Float) -> [Float] {
    let unit = 1.2 / wpm
    var keyed: [(Bool, Double)] = []   // (on, seconds)
    for (wi, word) in text.split(separator: " ").enumerated() {
        if wi > 0 { keyed.append((false, 7 * unit)) }
        for (ci, ch) in word.enumerated() {
            if ci > 0 { keyed.append((false, 3 * unit)) }
            for (si, sym) in morse[ch]!.enumerated() {
                if si > 0 { keyed.append((false, unit)) }
                keyed.append((true, sym == "." ? unit : 3 * unit))
            }
        }
    }
    var out = [Float](repeating: 0, count: Int(fs * 0.5))      // lead-in silence
    var phase = 0.0
    for (on, dur) in keyed {
        let n = Int(dur * fs)
        for i in 0..<n {
            var env: Float = on ? 1 : 0
            if on {
                let ramp = Int(0.004 * fs)
                if i < ramp { env = Float(i) / Float(ramp) } else if i > n - ramp { env = Float(n - i) / Float(ramp) }
            }
            phase += 2 * .pi * tone / fs
            out.append(env * signalAmp * Float(sin(phase)))
        }
    }
    out += [Float](repeating: 0, count: Int(fs * 1.5))
    for i in out.indices { out[i] += noiseAmp * Float.random(in: -1...1) * 1.7 }
    return out
}

func decode(_ samples: [Float], fs: Double, tone: Double) -> (String, Int) {
    var d = CWDemodulator(); d.toneHz = tone
    var text = ""
    var i = 0
    while i < samples.count {                      // feed in 1024-sample blocks like the audio tap
        let end = min(i + 1024, samples.count)
        text += samples[i..<end].withUnsafeBufferPointer { d.process($0, sampleRate: fs) }
        i = end
    }
    return (text, d.wpm)
}

let msg = "CQ CQ DE W1AW K 73 5NN TEST"
var failures = 0
for (wpm, fs, noise, sig) in [(10.0, 48000.0, Float(0.02), Float(0.2)), (15, 48000, 0.02, 0.2), (20, 48000, 0.02, 0.2),
                              (25, 44100, 0.05, 0.2), (30, 48000, 0.03, 0.2), (20, 48000, 0.1, 0.2), (20, 48000, 0.0, 0.01)] {
    let (text, est) = decode(synth(msg, wpm: wpm, tone: 700, fs: fs, noiseAmp: noise, signalAmp: sig), fs: fs, tone: 700)
    let ok = text.trimmingCharacters(in: .whitespaces) == msg
    if !ok { failures += 1 }
    print(ok ? "PASS" : "FAIL", "wpm=\(wpm) fs=\(Int(fs)) noise=\(noise) sig=\(sig) est=\(est)  '\(text)'")
}
print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
