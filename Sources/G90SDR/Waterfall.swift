import SwiftUI
import CoreGraphics

/// Scrolling RGBA bitmap of FFT rows. Newest row is drawn at the top.
final class Waterfall: ObservableObject {
    static let width = 512
    static let height = 300

    @Published var image: CGImage?
    @Published var latest: [Float] = []
    @Published var floorDB: Float = -100
    @Published var ceilingDB: Float = -30

    private var pixels = [UInt8](repeating: 0, count: width * height * 4)

    func push(_ row: [Float]) {
        guard !row.isEmpty else { return }
        let w = Self.width, h = Self.height
        // shift existing rows down by one
        pixels.withUnsafeMutableBytes { p in
            memmove(p.baseAddress! + w * 4, p.baseAddress!, w * 4 * (h - 1))
        }
        let span = max(ceilingDB - floorDB, 1)
        for x in 0..<w {
            let src = min(row.count - 1, x * row.count / w)
            let t = min(max((row[src] - floorDB) / span, 0), 1)
            let (r, g, b) = Self.color(t)
            pixels[x * 4] = r; pixels[x * 4 + 1] = g; pixels[x * 4 + 2] = b; pixels[x * 4 + 3] = 255
        }
        latest = row
        image = pixels.withUnsafeBytes { raw -> CGImage? in
            guard let provider = CGDataProvider(data: Data(raw) as CFData) else { return nil }
            return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                           space: CGColorSpaceCreateDeviceRGB(),
                           bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                           provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        }
    }

    /// black → blue → cyan → yellow → red
    private static func color(_ t: Float) -> (UInt8, UInt8, UInt8) {
        let stops: [(Float, (Float, Float, Float))] = [
            (0.0, (0, 0, 0)), (0.25, (0, 0, 0.7)), (0.5, (0, 0.85, 0.9)), (0.75, (1, 0.95, 0)), (1.0, (1, 0.1, 0))
        ]
        for i in 1..<stops.count where t <= stops[i].0 {
            let (t0, c0) = stops[i - 1], (t1, c1) = stops[i]
            let f = (t - t0) / (t1 - t0)
            func mix(_ a: Float, _ b: Float) -> UInt8 { UInt8((a + (b - a) * f) * 255) }
            return (mix(c0.0, c1.0), mix(c0.1, c1.1), mix(c0.2, c1.2))
        }
        return (255, 26, 0)
    }
}

struct WaterfallView: View {
    @ObservedObject var waterfall: Waterfall

    var body: some View {
        VStack(spacing: 4) {
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
                let row = waterfall.latest
                guard row.count > 1 else { return }
                let span = max(waterfall.ceilingDB - waterfall.floorDB, 1)
                var path = Path()
                for (i, v) in row.enumerated() {
                    let x = size.width * CGFloat(i) / CGFloat(row.count - 1)
                    let y = size.height * (1 - CGFloat(min(max((v - waterfall.floorDB) / span, 0), 1)))
                    i == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
                }
                ctx.stroke(path, with: .color(.green), lineWidth: 1)
            }
            .frame(height: 100)

            ZStack {
                Color.black
                if let image = waterfall.image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.none)
                }
            }

            HStack {
                ForEach([0, 1, 2, 3, 4], id: \.self) { k in
                    Text("\(k) kHz").font(.caption2).foregroundStyle(.secondary)
                    if k < 4 { Spacer() }
                }
            }
        }
    }
}
