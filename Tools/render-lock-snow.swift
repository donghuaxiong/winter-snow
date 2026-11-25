import AppKit
import AVFoundation
import VideoToolbox

// Rebuild the bundled lock-screen movie from the original Snowglow cabin art.
let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    fputs("Usage: swift Tools/render-lock-snow.swift Resources\n", stderr)
    exit(2)
}
let resources = URL(fileURLWithPath: arguments[1], isDirectory: true)
let baseURL = resources.appending(path: "WinterCabin.jpg")
let movieURL = resources.appending(path: "LockSnow.mov")
let posterURL = resources.appending(path: "LockSnow.png")
let temporaryMovie = resources.appending(path: "LockSnow-render-\(UUID().uuidString).mov")
let width = 1920, height = 1080, fps: Int32 = 30
let cycleSeconds = 30
let seconds = 90
let dimensions = CGRect(x: 0, y: 0, width: width, height: height)
let colorSpace = CGColorSpace(name: CGColorSpace.itur_709)!
let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue
let background = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(baseURL as CFURL, nil)!, 0, nil)!

struct Flake {
    let x: CGFloat
    let y: CGFloat
    let radius: CGFloat
    let alpha: CGFloat
    let speed: CGFloat
    let phase: CGFloat
    let wind: CGFloat
}

var seed: UInt64 = 584_632_173
func random() -> CGFloat {
    seed = seed &* 2_862_933_555_777_941_757 &+ 3_037_000_493
    return CGFloat((seed >> 33) & 0x7fff_ffff) / 2_147_483_648
}
let flakes = (0..<365).map { index -> Flake in
    let layer: CGFloat = index < 210 ? 0 : index < 304 ? 1 : 2
    return Flake(x: -35 + random() * CGFloat(width + 70), y: random(), radius: 0.65 + 0.74 * layer + random() * (0.65 + layer * 0.36),
                 alpha: 0.16 + 0.12 * layer + random() * 0.24, speed: layer + 1, phase: random() * 2 * .pi,
                 wind: 11 + layer * 7 + random() * 12)
}
let writer = try AVAssetWriter(outputURL: temporaryMovie, fileType: .mov)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.hevc,
    AVVideoWidthKey: width, AVVideoHeightKey: height,
    AVVideoColorPropertiesKey: [
        AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
        AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
        AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
    ],
    AVVideoCompressionPropertiesKey: [
        AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main10_AutoLevel,
        AVVideoAverageBitRateKey: 2_800_000,
        AVVideoExpectedSourceFrameRateKey: fps,
        AVVideoMaxKeyFrameIntervalKey: fps * 2,
    ],
])
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    kCVPixelBufferWidthKey as String: width,
    kCVPixelBufferHeightKey as String: height,
    kCVPixelBufferCGImageCompatibilityKey as String: true,
    kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
])
writer.add(input)
guard writer.startWriting() else { throw writer.error! }
writer.startSession(atSourceTime: .zero)

for frame in 0..<(seconds * Int(fps)) {
    while !input.isReadyForMoreMediaData {
        if writer.status == .failed { throw writer.error! }
        Thread.sleep(forTimeInterval: 0.004)
    }
    try autoreleasepool {
        var storage: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &storage)
        let pixels = storage!
        CVPixelBufferLockBaseAddress(pixels, [])
        let context = CGContext(data: CVPixelBufferGetBaseAddress(pixels), width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixels),
                                space: colorSpace, bitmapInfo: bitmapInfo)!
        context.draw(background, in: dimensions)
        let framesPerCycle = cycleSeconds * Int(fps)
        let phase = CGFloat(frame % framesPerCycle) / CGFloat(framesPerCycle)
        for flake in flakes {
            let travel = (flake.y + phase * flake.speed).truncatingRemainder(dividingBy: 1)
            let x = flake.x + flake.wind * sin(2 * .pi * phase + flake.phase)
            let y = CGFloat(height + 60) * (1 - travel) - 30
            let r = flake.radius
            context.setFillColor(red: 0.87, green: 0.93, blue: 1, alpha: flake.alpha * 0.22)
            context.fillEllipse(in: CGRect(x: x - r * 1.45, y: y - r * 1.45, width: r * 2.9, height: r * 2.9))
            context.setFillColor(red: 0.96, green: 0.98, blue: 1, alpha: flake.alpha)
            context.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
        }
        if frame == 0 {
            let destination = CGImageDestinationCreateWithURL(posterURL as CFURL, "public.png" as CFString, 1, nil)!
            CGImageDestinationAddImage(destination, context.makeImage()!, nil)
            precondition(CGImageDestinationFinalize(destination))
        }
        CVPixelBufferUnlockBaseAddress(pixels, [])
        guard adaptor.append(pixels, withPresentationTime: CMTime(value: Int64(frame), timescale: fps)) else {
            throw writer.error ?? CocoaError(.fileWriteUnknown)
        }
    }
}
input.markAsFinished()
let finished = DispatchSemaphore(value: 0)
writer.finishWriting { finished.signal() }
finished.wait()
guard writer.status == .completed else { throw writer.error! }
if FileManager.default.fileExists(atPath: movieURL.path) {
    _ = try FileManager.default.replaceItemAt(movieURL, withItemAt: temporaryMovie)
} else {
    try FileManager.default.moveItem(at: temporaryMovie, to: movieURL)
}
print("Rendered \(seconds) seconds at \(width)×\(height)")
