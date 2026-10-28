import Foundation
import SwiftUI

/// Owns the CAT link. All serial I/O happens on `queue`; published state is updated on the main thread.
final class RadioController: ObservableObject {
    @Published var ports: [String] = SerialPort.availablePorts()
    @Published var selectedPort: String = SerialPort.availablePorts().first(where: { $0.contains("usbserial") }) ?? ""
    @Published var connected = false
    @Published var status = "Disconnected"
    @Published var frequencyHz: Int = 0
    @Published var mode: RadioMode?
    @Published var sMeter: Int = 0          // 0...255 raw
    @Published var sMeterPeak: Int = 0      // peak hold, decays slowly

    private let serial = SerialPort()
    private let queue = DispatchQueue(label: "g90sdr.civ")
    private var timer: DispatchSourceTimer?
    private var rxBuffer: [UInt8] = []
    private var failures = 0

    func refreshPorts() {
        ports = SerialPort.availablePorts()
        if !ports.contains(selectedPort) { selectedPort = ports.first ?? "" }
    }

    func connect() {
        let path = selectedPort
        queue.async { [self] in
            do {
                try serial.open(path: path, baud: 19200)
            } catch {
                publish { self.status = error.localizedDescription }
                return
            }
            failures = 0
            publish { self.connected = true; self.status = "Connected to \(path)" }
            startPolling()
        }
    }

    func disconnect() {
        queue.async { [self] in
            timer?.cancel(); timer = nil
            serial.close()
            publish { self.connected = false; self.status = "Disconnected" }
        }
    }

    func setFrequency(_ hz: Int) {
        guard hz > 0 else { return }
        queue.async { [self] in
            _ = transact([0x05] + CIV.encodeFrequency(hz))
            poll()
        }
    }

    func tune(by deltaHz: Int) { setFrequency(frequencyHz + deltaHz) }

    func setMode(_ mode: RadioMode) {
        queue.async { [self] in
            _ = transact([0x06, mode.rawValue])
            poll()
        }
    }

    // MARK: - Queue-confined

    private func publish(_ block: @escaping () -> Void) { DispatchQueue.main.async(execute: block) }

    private func startPolling() {
        timer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: .milliseconds(300))
        t.setEventHandler { [weak self] in self?.poll() }
        t.resume()
        timer = t
    }

    private func poll() {
        guard serial.isOpen else { return }
        let freq = transact([0x03]).flatMap { $0.cmd == 0x03 ? CIV.decodeFrequency($0.payload) : nil }
        let mode = transact([0x04]).flatMap { $0.cmd == 0x04 ? $0.payload.first.flatMap(RadioMode.init(rawValue:)) : nil }
        let s = transact([0x15, 0x02]).flatMap { $0.cmd == 0x15 ? CIV.decodeBCD16(Array($0.payload.dropFirst())) : nil }

        if freq == nil && mode == nil && s == nil {
            failures += 1
            if failures == 5 { publish { self.status = "No reply from radio (check CI-V address 0x70, 19200 baud)" } }
        } else if failures >= 5 {
            failures = 0
            publish { self.status = "Connected to \(self.selectedPort)" }
        } else {
            failures = 0
        }
        publish {
            if let freq { self.frequencyHz = freq }
            if let mode { self.mode = mode }
            if let s {
                self.sMeter = s
                self.sMeterPeak = max(s, self.sMeterPeak - 6)
            } else {
                self.sMeterPeak = max(self.sMeter, self.sMeterPeak - 6)
            }
        }
    }

    /// Sends one command and waits for the reply addressed to us, skipping the bus echo.
    private func transact(_ cmd: [UInt8], timeoutMs: Int = 250) -> CIV.Frame? {
        serial.flushInput()
        rxBuffer.removeAll()
        serial.write(CIV.encode(cmd))
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000)
        while Date() < deadline {
            rxBuffer += serial.read(timeoutMs: 50)
            for frame in CIV.extractFrames(from: &rxBuffer)
            where frame.to == CIV.controllerAddress && frame.from == CIV.radioAddress {
                return frame
            }
        }
        return nil
    }
}
