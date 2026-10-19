// xcode: set sdk=iOS

import AVFoundation
import UIKit

/// Renders a real 2-second movie file without a camera, so the full
/// capture → reel → archive flow works in the Simulator.
enum SimulatedClipWriter {
    static let palettes: [[UIColor]] = [
        [UIColor(hex: 0xFFD9E0), UIColor(hex: 0xE2B4BD)],
        [UIColor(hex: 0xF9D8D2), UIColor(hex: 0xC9A39B)],
        [UIColor(hex: 0xCFEACE), UIColor(hex: 0x8FAE90)],
        [UIColor(hex: 0xEAE8E7), UIColor(hex: 0xB5A9A6)],
        [UIColor(hex: 0xD8CCE0), UIColor(hex: 0x9E8FAE)],
        [UIColor(hex: 0xE8C9B8), UIColor(hex: 0xB98B78)],
    ]

    static let notes = [
        "", "", "boba break", "ARC after class", "biking past the cows", "walking home on 3rd St",
        "Silo lunch", "Shields 3rd floor", "Unitrans window views", "Picnic Day prep", "Woodstock's run",
    ]

    private static let fps: Int32 = 24

    static func write(to url: URL, title: String, subtitle: String, palette: [UIColor], landscape: Bool) async throws {
        let size = landscape ? CGSize(width: 960, height: 540) : CGSize(width: 540, height: 960)
        try? FileManager.default.removeItem(at: url)

        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? SetlogError.exportFailed }
        writer.startSession(atSourceTime: .zero)

        let frameCount = Int(Double(fps) * CameraService.clipLength)
        for frame in 0..<frameCount {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            guard let pool = adaptor.pixelBufferPool else { throw SetlogError.exportFailed }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { throw SetlogError.exportFailed }

            let progress = Double(frame) / Double(frameCount - 1)
            if let image = renderFrame(size: size, progress: progress, title: title, subtitle: subtitle, palette: palette) {
                draw(image, into: buffer)
            }
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
        }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed { throw writer.error ?? SetlogError.exportFailed }
    }

    private static func draw(_ image: CGImage, into buffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }

    private static func renderFrame(size: CGSize, progress: Double, title: String, subtitle: String, palette: [UIColor]) -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = ctx.cgContext
            let p = CGFloat(progress)

            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: palette.map(\.cgColor) as CFArray, locations: nil) {
                let drift = p * size.width * 0.5
                cg.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: -drift, y: 0),
                    end: CGPoint(x: size.width + drift, y: size.height),
                    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
                )
            }

            // A soft light leak drifting across the frame gives each take some motion.
            let short = min(size.width, size.height)
            let radius = short * 0.42
            let center = CGPoint(x: size.width * (0.15 + 0.7 * p), y: size.height * 0.32)
            cg.setFillColor(UIColor.white.withAlphaComponent(0.28).cgColor)
            cg.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))

            let ink = UIColor(hex: 0x4A4A4A)
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedDigitSystemFont(ofSize: short * 0.2, weight: .semibold),
                .foregroundColor: ink,
            ]
            let subtitleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: short * 0.05, weight: .medium),
                .foregroundColor: ink.withAlphaComponent(0.7),
            ]
            let titleSize = (title as NSString).size(withAttributes: titleAttributes)
            let subtitleSize = (subtitle as NSString).size(withAttributes: subtitleAttributes)
            let top = (size.height - titleSize.height - subtitleSize.height) / 2
            (title as NSString).draw(at: CGPoint(x: (size.width - titleSize.width) / 2, y: top), withAttributes: titleAttributes)
            (subtitle as NSString).draw(at: CGPoint(x: (size.width - subtitleSize.width) / 2, y: top + titleSize.height), withAttributes: subtitleAttributes)

            cg.setFillColor(UIColor(hex: 0x79545C).cgColor)
            cg.fill(CGRect(x: 0, y: size.height - 10, width: size.width * p, height: 10))
        }
        return image.cgImage
    }
}
