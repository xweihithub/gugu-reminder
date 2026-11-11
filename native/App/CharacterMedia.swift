import AVFoundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import Vision

enum CharacterMedia {
    static func prepareReference(from source: URL, to destination: URL) throws {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1440
              ] as CFDictionary), min(image.width, image.height) >= 128 else {
            throw CharacterError("请选择能打开、短边至少 128 像素的 PNG 或 JPG 图片。")
        }
        let subject = foreground(of: image) ?? image
        let side = 1440
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let canvas = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                     bytesPerRow: side * 4, space: space,
                                     bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw CharacterError("无法创建形象画布。")
        }
        canvas.setFillColor(red: 0, green: 1, blue: 0, alpha: 1)
        canvas.fill(CGRect(x: 0, y: 0, width: side, height: side))
        let scale = Double(side) * 0.78 / Double(max(subject.width, subject.height))
        let width = Double(subject.width) * scale
        let height = Double(subject.height) * scale
        canvas.interpolationQuality = .high
        canvas.draw(subject, in: CGRect(x: (Double(side) - width) / 2, y: (Double(side) - height) / 2,
                                        width: width, height: height))
        guard let composed = canvas.makeImage() else { throw CharacterError("无法生成形象预览。") }
        try writePNG(composed, to: destination)
    }

    private static func foreground(of image: CGImage) -> CGImage? {
        if [.first, .last, .premultipliedFirst, .premultipliedLast].contains(image.alphaInfo) { return nil }
        guard #available(macOS 14.0, *) else { return nil }
        let handler = VNImageRequestHandler(cgImage: image)
        let request = VNGenerateForegroundInstanceMaskRequest()
        guard (try? handler.perform([request])) != nil,
              let result = request.results?.first, result.allInstances.count == 1,
              let buffer = try? result.generateMaskedImage(ofInstances: result.allInstances, from: handler,
                                                            croppedToInstancesExtent: true) else { return nil }
        let output = CIImage(cvPixelBuffer: buffer)
        return CIContext().createCGImage(output, from: output.extent)
    }

    private static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let output = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw CharacterError("无法保存形象图片。")
        }
        CGImageDestinationAddImage(output, image, nil)
        guard CGImageDestinationFinalize(output) else { throw CharacterError("无法保存形象图片。") }
    }

    static func importClip(_ source: URL, movie: URL, still: URL) async throws {
        let asset = AVURLAsset(url: source)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw CharacterError("文件没有可播放的视频轨道。")
        }
        let duration = try await asset.load(.duration)
        let size = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let needsGreenKey = try await !track.load(.mediaCharacteristics).contains(.containsAlphaChannel)
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        guard transform.isIdentity, width == height, (256...4096).contains(width), width.isMultiple(of: 2),
              duration.seconds.isFinite, (1...20).contains(duration.seconds) else {
            throw CharacterError("需要正向方形视频，边长 256–4096 像素、时长 1–20 秒。")
        }
        let reader = try AVAssetReader(asset: asset)
        let decoded = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        decoded.alwaysCopiesSampleData = false
        guard reader.canAdd(decoded) else { throw CharacterError("无法解码视频。") }
        reader.add(decoded)
        let writer = try AVAssetWriter(outputURL: movie, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevcWithAlpha,
            AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoQualityKey: 1.0,
                kVTCompressionPropertyKey_TargetQualityForAlpha as String: 1.0,
                kVTCompressionPropertyKey_AlphaChannelMode as String: kVTAlphaChannelMode_StraightAlpha
            ]
        ])
        let output = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ])
        guard writer.canAdd(input) else { throw CharacterError("此 Mac 无法编码该尺寸的透明视频。") }
        writer.add(input)
        guard reader.startReading(), writer.startWriting() else {
            throw CharacterError("无法开始视频转换。")
        }
        defer {
            if reader.status == .reading { reader.cancelReading() }
            if writer.status == .writing { writer.cancelWriting() }
        }
        writer.startSession(atSourceTime: .zero)
        guard let pool = output.pixelBufferPool else { throw CharacterError("无法分配视频缓冲区。") }
        var start: CMTime?
        var last = CMTime.zero
        while let sample = decoded.copyNextSampleBuffer() {
            try Task.checkCancellation()
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sample)
            if start == nil { start = timestamp }
            let time = timestamp - (start ?? .zero)
            let deadline = ProcessInfo.processInfo.systemUptime + 10
            while !input.isReadyForMoreMediaData {
                guard writer.status == .writing, ProcessInfo.processInfo.systemUptime < deadline else {
                    throw CharacterError("透明视频编码超时。")
                }
                try await Task.sleep(nanoseconds: 2_000_000)
            }
            try autoreleasepool {
                guard let frame = CMSampleBufferGetImageBuffer(sample) else { throw CharacterError("视频帧不完整。") }
                var buffer: CVPixelBuffer?
                guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
                      let buffer else { throw CharacterError("无法分配视频帧。") }
                try processAlpha(from: frame, into: buffer, keyGreen: needsGreenKey)
                guard output.append(buffer, withPresentationTime: time) else { throw CharacterError("无法保存透明视频帧。") }
            }
            last = time
        }
        guard reader.status == .completed, start != nil, last.seconds > 0 else {
            throw CharacterError("视频未完整解码。")
        }
        writer.endSession(atSourceTime: duration)
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw CharacterError("无法保存透明 MOV。") }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: movie))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let stillImage = try await generator.image(at: last).image
        try writePNG(stillImage, to: still)
    }

    private static func processAlpha(from source: CVPixelBuffer, into target: CVPixelBuffer, keyGreen: Bool) throws {
        CVPixelBufferLockBaseAddress(source, .readOnly)
        CVPixelBufferLockBaseAddress(target, [])
        defer {
            CVPixelBufferUnlockBaseAddress(target, [])
            CVPixelBufferUnlockBaseAddress(source, .readOnly)
        }
        guard let sourceBase = CVPixelBufferGetBaseAddress(source), let targetBase = CVPixelBufferGetBaseAddress(target) else {
            throw CharacterError("无法访问视频像素。")
        }
        let width = CVPixelBufferGetWidth(target)
        let height = CVPixelBufferGetHeight(target)
        let sourceStride = CVPixelBufferGetBytesPerRow(source)
        let targetStride = CVPixelBufferGetBytesPerRow(target)
        var clearPixels = 0
        var opaquePixels = 0
        for y in 0..<height {
            let src = sourceBase.advanced(by: y * sourceStride).assumingMemoryBound(to: UInt8.self)
            let dst = targetBase.advanced(by: y * targetStride).assumingMemoryBound(to: UInt8.self)
            for offset in stride(from: 0, to: width * 4, by: 4) {
                let blue = Int(src[offset])
                let green = Int(src[offset + 1])
                let red = Int(src[offset + 2])
                let spill = keyGreen ? max(0, green - max(blue, red)) : 0
                let dominance = Float(spill) / Float(max(green, 1))
                let coverage = min(1, max(0, (0.18 - dominance) / 0.13))
                let alpha = coverage * coverage * (3 - 2 * coverage)
                let opacity = min(Int(src[offset + 3]), Int((255 * alpha).rounded()))
                dst[offset] = UInt8(blue)
                dst[offset + 1] = UInt8(green - Int(Float(spill) * (1 - alpha) * 0.95))
                dst[offset + 2] = UInt8(red)
                dst[offset + 3] = UInt8(opacity)
                if opacity == 0 { clearPixels += 1 }
                if opacity >= 250 { opaquePixels += 1 }
            }
        }
        let area = width * height
        let cornerOffsets = [0, (width - 1) * 4, (height - 1) * targetStride,
                             (height - 1) * targetStride + (width - 1) * 4]
        guard clearPixels > area / 20, opaquePixels > area / 100,
              cornerOffsets.allSatisfy({ targetBase.load(fromByteOffset: $0 + 3, as: UInt8.self) < 16 }) else {
            throw CharacterError("这段视频缺少干净的绿幕或透明背景，请在 Grok 中重做该动作。")
        }
    }
}
