import Foundation

/// Minimal Icom CI-V framing, as used by the Xiegu G90 CAT port.
/// Frame: FE FE <to> <from> <cmd> [data...] FD
enum CIV {
    static let radioAddress: UInt8 = 0x70     // G90 default
    static let controllerAddress: UInt8 = 0xE0
    static let ok: UInt8 = 0xFB
    static let ng: UInt8 = 0xFA

    struct Frame {
        let to: UInt8
        let from: UInt8
        let cmd: UInt8
        let payload: [UInt8]
    }

    static func encode(_ cmd: [UInt8], radio: UInt8 = radioAddress) -> [UInt8] {
        [0xFE, 0xFE, radio, controllerAddress] + cmd + [0xFD]
    }

    /// Pull every complete frame out of `buffer`, leaving any trailing partial frame in place.
    static func extractFrames(from buffer: inout [UInt8]) -> [Frame] {
        var frames: [Frame] = []
        var i = 0
        while i + 1 < buffer.count {
            guard buffer[i] == 0xFE, buffer[i + 1] == 0xFE else { i += 1; continue }
            guard let end = buffer[(i + 2)...].firstIndex(of: 0xFD) else { break }
            let body = Array(buffer[(i + 2)..<end])
            if body.count >= 3 {
                frames.append(Frame(to: body[0], from: body[1], cmd: body[2], payload: Array(body.dropFirst(3))))
            }
            i = end + 1
        }
        buffer.removeFirst(min(i, buffer.count))
        return frames
    }

    /// Frequency is 5 BCD bytes, least significant digit pair first.
    static func encodeFrequency(_ hz: Int) -> [UInt8] {
        var v = hz
        return (0..<5).map { _ in
            let lo = UInt8(v % 10); v /= 10
            let hi = UInt8(v % 10); v /= 10
            return hi << 4 | lo
        }
    }

    static func decodeFrequency(_ bytes: [UInt8]) -> Int {
        bytes.prefix(5).reversed().reduce(0) { $0 * 100 + Int($1 >> 4) * 10 + Int($1 & 0x0F) }
    }

    /// Two BCD bytes, 0000...0255.
    static func decodeBCD16(_ bytes: [UInt8]) -> Int {
        bytes.prefix(2).reduce(0) { $0 * 100 + Int($1 >> 4) * 10 + Int($1 & 0x0F) }
    }
}

enum RadioMode: UInt8, CaseIterable, Identifiable {
    case lsb = 0x00, usb = 0x01, am = 0x02, cw = 0x03, rtty = 0x04, fm = 0x05, cwr = 0x07
    var id: UInt8 { rawValue }
    var label: String {
        switch self {
        case .lsb: "LSB"
        case .usb: "USB"
        case .am: "AM"
        case .cw: "CW"
        case .rtty: "RTTY"
        case .fm: "FM"
        case .cwr: "CW-R"
        }
    }
}
