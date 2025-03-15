import AVFoundation
import CoreVideo
import CoreGraphics

public final class ReplayVideoExporter {
    public static func export(level: LevelDefinition, result: SolutionSimulator.Result) async throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
        
        let writer = try AVAssetWriter(url: tempURL, fileType: .mp4)
        
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(level.sceneSize.width),
            AVVideoHeightKey: Int(level.sceneSize.height)
        ]
        
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = false
        
        let sourcePixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: Int(level.sceneSize.width),
            kCVPixelBufferHeightKey as String: Int(level.sceneSize.height)
        ]
        
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: sourcePixelBufferAttributes)
        
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        
        let renderer = SceneRenderer(sceneSize: level.sceneSize, pixelSize: CGSize(width: level.sceneSize.width, height: level.sceneSize.height))
        
        // Physics is 60Hz. Frames are captured every 2nd step -> 30 frames per second.
        // The master plan mentions 60fps, so we advance 2/60s per frame if we use a 60 timescale.
        let frameDuration = CMTime(value: 2, timescale: 60)
        
        for (i, frame) in result.frames.enumerated() {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pixelBuffer)
            guard let pb = pixelBuffer else { throw NSError(domain: "ReplayExporter", code: 1, userInfo: nil) }
            
            CVPixelBufferLockBaseAddress(pb, [])
            let baseAddress = CVPixelBufferGetBaseAddress(pb)
            let bytesPerRow = CVPixelBufferGetBytesPerRow(pb)
            let width = CVPixelBufferGetWidth(pb)
            let height = CVPixelBufferGetHeight(pb)
            
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            // TRAP from plan: CGImageAlphaInfo.noneSkipFirst + CGBitmapInfo.byteOrder32Little
            let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue
            
            if let context = CGContext(data: baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo) {
                renderer.draw(bodies: frame.bodies, shapes: result.shapes, level: level, into: context)
            }
            CVPixelBufferUnlockBaseAddress(pb, [])
            
            let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(i))
            adaptor.append(pb, withPresentationTime: presentationTime)
        }
        
        input.markAsFinished()
        await writer.finishWriting()
        
        return tempURL
    }
}
