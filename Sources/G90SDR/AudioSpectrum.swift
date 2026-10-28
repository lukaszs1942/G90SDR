import Foundation
import AVFoundation
import Accelerate
import CoreAudio
import AudioToolbox

struct AudioInputDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String

    static func all() -> [AudioInputDevice] {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == 0 else { return [] }
        return ids.compactMap { id in
            guard inputChannels(id) > 0 else { return nil }
            return AudioInputDevice(id: id, name: name(id))
        }
    }

    private static func inputChannels(_ id: AudioDeviceID) -> Int {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                              mScope: kAudioDevicePropertyScopeInput,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw) == 0 else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func name(_ id: AudioDeviceID) -> String {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var cf: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &cf) == 0, let s = cf?.takeRetainedValue() else { return "Device \(id)" }
        return s as String
    }
}

/// Captures audio from the radio's data/line-out via a sound card and publishes FFT rows
/// covering the 0...`maxFrequency` audio passband.
final class AudioSpectrum: ObservableObject {
    static let fftSize = 2048
    static let maxFrequency: Double = 4000

    @Published var devices: [AudioInputDevice] = AudioInputDevice.all()
    @Published var selectedDevice: AudioDeviceID = 0
    @Published var running = false
    @Published var error: String?

    /// Called on the main thread with one row of dB values (low → high frequency).
    var onRow: (([Float]) -> Void)?

    private let engine = AVAudioEngine()
    private var accumulator: [Float] = []
    private let log2n = vDSP_Length(11)
    private let setup: FFTSetup
    private let window: [Float]

    init() {
        setup = vDSP_create_fftsetup(vDSP_Length(11), FFTRadix(kFFTRadix2))!
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized,
                             count: Self.fftSize, isHalfWindow: false)
        selectedDevice = devices.first?.id ?? 0
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    func refreshDevices() { devices = AudioInputDevice.all() }

    func start() {
        stop()
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                guard granted else { self.error = "Microphone access denied (System Settings → Privacy → Microphone)"; return }
                self.startEngine()
            }
        }
    }

    func stop() {
        if engine.isRunning { engine.stop(); engine.inputNode.removeTap(onBus: 0) }
        running = false
    }

    private func startEngine() {
        error = nil
        accumulator.removeAll()
        let input = engine.inputNode
        if var dev = Optional(selectedDevice), dev != 0, let unit = input.audioUnit {
            let st = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                          &dev, UInt32(MemoryLayout<AudioDeviceID>.size))
            if st != noErr { error = "Could not select input device (\(st))"; return }
        }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { error = "Input device has no valid format"; return }
        let sampleRate = format.sampleRate
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self, let ch = buffer.floatChannelData?[0] else { return }
            self.accumulator.append(contentsOf: UnsafeBufferPointer(start: ch, count: Int(buffer.frameLength)))
            while self.accumulator.count >= Self.fftSize {
                let row = self.fft(Array(self.accumulator.prefix(Self.fftSize)), sampleRate: sampleRate)
                self.accumulator.removeFirst(Self.fftSize / 2)   // 50% overlap
                DispatchQueue.main.async { self.onRow?(row) }
            }
        }
        do {
            try engine.start()
            running = true
        } catch {
            input.removeTap(onBus: 0)
            self.error = error.localizedDescription
        }
    }

    private func fft(_ samples: [Float], sampleRate: Double) -> [Float] {
        let n = Self.fftSize
        var windowed = [Float](repeating: 0, count: n)
        vDSP.multiply(samples, window, result: &windowed)

        var real = [Float](repeating: 0, count: n / 2)
        var imag = [Float](repeating: 0, count: n / 2)
        var mags = [Float](repeating: 0, count: n / 2)
        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                windowed.withUnsafeBufferPointer { wp in
                    wp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(n / 2))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))
                vDSP_zvmags(&split, 1, &mags, 1, vDSP_Length(n / 2))
            }
        }
        let binHz = sampleRate / Double(n)
        let usable = min(n / 2, Int(Self.maxFrequency / binHz))
        // Scale so a full-scale sine lands near 0 dB.
        let scale = 1 / Float(n * n)
        return mags.prefix(usable).map { 10 * log10f($0 * scale + 1e-12) }
    }
}
