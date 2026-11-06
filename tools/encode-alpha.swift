// 将 FFmpeg 解码的 BGRA 帧写为系统可播放的 HEVC with Alpha；仅用于素材维护。
import AVFoundation
import Foundation

let args = CommandLine.arguments
guard args.count == 5, let width = Int(args[2]), let height = Int(args[3]),
      let fps = Int(args[4]), width > 0, height > 0, fps > 0 else {
    fputs("用法: encode-alpha output.mov width height fps < frames.bgra\n", stderr)
    exit(1)
}
let output = URL(fileURLWithPath: args[1])
do {
    let writer = try AVAssetWriter(outputURL: output, fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.hevcWithAlpha,
        AVVideoWidthKey: width, AVVideoHeightKey: height,
        AVVideoCompressionPropertiesKey: [
            AVVideoQualityKey: 1.0,
            kVTCompressionPropertyKey_TargetQualityForAlpha as String: 1.0,
            kVTCompressionPropertyKey_AlphaChannelMode as String: kVTAlphaChannelMode_StraightAlpha
        ]
    ])
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
        sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ])
    guard writer.canAdd(input) else { throw NSError(domain: "AlphaEncoder", code: 1) }
    writer.add(input)
    guard writer.startWriting() else { throw writer.error! }
    writer.startSession(atSourceTime: .zero)
    let frameSize = width * height * 4
    var frames = 0
    while true {
        var data = Data()
        while data.count < frameSize {
            let chunk = try FileHandle.standardInput.read(upToCount: frameSize - data.count) ?? Data()
            if chunk.isEmpty { break }
            data.append(chunk)
        }
        if data.isEmpty { break }
        guard data.count == frameSize else { throw NSError(domain: "帧不完整", code: 2) }
        while !input.isReadyForMoreMediaData {
            if writer.status == .failed { throw writer.error! }
            Thread.sleep(forTimeInterval: 0.002)
        }
        var buffer: CVPixelBuffer?
        guard let pool = adaptor.pixelBufferPool,
              CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
              let buffer else { throw NSError(domain: "无法分配像素缓冲", code: 3) }
        CVPixelBufferLockBaseAddress(buffer, [])
        data.withUnsafeBytes { raw in
            let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
            for row in 0..<height {
                memcpy(CVPixelBufferGetBaseAddress(buffer)!.advanced(by: row * rowBytes),
                       raw.baseAddress!.advanced(by: row * width * 4), width * 4)
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frames), timescale: Int32(fps))) else {
            throw writer.error ?? NSError(domain: "写入视频失败", code: 4)
        }
        frames += 1
    }
    guard frames > 0 else { throw NSError(domain: "没有输入帧", code: 5) }
    input.markAsFinished()
    let done = DispatchSemaphore(value: 0)
    writer.finishWriting { done.signal() }
    done.wait()
    guard writer.status == .completed else { throw writer.error! }
    print("HEVC Alpha: \(frames) 帧，\(Double(frames) / Double(fps)) 秒 → \(output.lastPathComponent)")
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}
