// Samples frames from a Simulator recording into the job log (one base64 JPEG per line), so a reviewer who can read
// the log but cannot download artifacts can rebuild a low-resolution copy of the recording
// (scripts/decode_video_frames.py). AVFoundation + ImageIO only (macOS runner).
//
//   swift scripts/extract_video_frames.swift <video.mp4> <name> [fps=4] [width=180] [maxSeconds=120]
import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count >= 3 else { print("usage: extract_video_frames.swift <video> <name> [fps] [width] [maxSeconds]"); exit(2) }
let name = args[2]
let fps = args.count > 3 ? Double(args[3]) ?? 4 : 4
let width = args.count > 4 ? Double(args[4]) ?? 180 : 180
let maxSeconds = args.count > 5 ? Double(args[5]) ?? 120 : 120
let asset = AVURLAsset(url: URL(fileURLWithPath: args[1]))
let generator = AVAssetImageGenerator(asset: asset)
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 120)
generator.maximumSize = CGSize(width: width, height: width * 4)
let fullDuration = try await asset.load(.duration).seconds
let duration = min(fullDuration, maxSeconds)
var index = 0
var t = 0.0
print("VIDEO_FRAMES_BEGIN \(name) fps=\(fps) duration=\(String(format: "%.2f", duration))")
while t < duration {
    if let result = try? await generator.image(at: CMTime(seconds: t, preferredTimescale: 600)) {
        let data = NSMutableData()
        if let dest = CGImageDestinationCreateWithData(data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) {
            let options = [kCGImageDestinationLossyCompressionQuality as String: 0.45] as CFDictionary
            CGImageDestinationAddImage(dest, result.image, options)
            if CGImageDestinationFinalize(dest) {
                let stamp = String(format: "%.3f", result.actualTime.seconds)
                print("VF \(name) \(index) \(stamp) \((data as Data).base64EncodedString())")
            }
        }
    }
    index += 1
    t = Double(index) / fps
}
print("VIDEO_FRAMES_END \(name) frames=\(index)")
