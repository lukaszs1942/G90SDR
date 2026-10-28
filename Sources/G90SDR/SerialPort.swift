import Foundation
import Darwin

struct SerialError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Thin POSIX termios wrapper. Not thread-safe; callers serialise access.
final class SerialPort {
    private var fd: Int32 = -1

    var isOpen: Bool { fd >= 0 }

    static func availablePorts() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? []
        return names.filter { $0.hasPrefix("cu.") && !$0.contains("Bluetooth") && !$0.contains("debug") }
            .sorted().map { "/dev/" + $0 }
    }

    func open(path: String, baud: speed_t) throws {
        close()
        let handle = Darwin.open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard handle >= 0 else { throw SerialError(message: "Cannot open \(path): \(String(cString: strerror(errno)))") }

        var tio = termios()
        guard tcgetattr(handle, &tio) == 0 else {
            Darwin.close(handle)
            throw SerialError(message: "tcgetattr failed: \(String(cString: strerror(errno)))")
        }
        cfmakeraw(&tio)
        cfsetspeed(&tio, baud)
        tio.c_cflag |= tcflag_t(CLOCAL | CREAD | CS8)
        tio.c_cflag &= ~tcflag_t(PARENB | CSTOPB | CRTSCTS)
        guard tcsetattr(handle, TCSANOW, &tio) == 0 else {
            Darwin.close(handle)
            throw SerialError(message: "tcsetattr failed: \(String(cString: strerror(errno)))")
        }
        fd = handle
    }

    func close() {
        if fd >= 0 { Darwin.close(fd) }
        fd = -1
    }

    func flushInput() {
        if fd >= 0 { tcflush(fd, TCIFLUSH) }
    }

    func write(_ bytes: [UInt8]) {
        guard fd >= 0 else { return }
        _ = bytes.withUnsafeBufferPointer { Darwin.write(fd, $0.baseAddress, $0.count) }
    }

    /// Reads whatever arrives within `timeoutMs`; returns empty on timeout.
    func read(timeoutMs: Int32) -> [UInt8] {
        guard fd >= 0 else { return [] }
        var p = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        guard poll(&p, 1, timeoutMs) > 0 else { return [] }
        var buf = [UInt8](repeating: 0, count: 256)
        let n = Darwin.read(fd, &buf, buf.count)
        return n > 0 ? Array(buf.prefix(n)) : []
    }
}
