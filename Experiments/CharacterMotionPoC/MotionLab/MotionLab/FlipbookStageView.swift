import CatBehavior
import QuartzCore
import SpineiOS
import SpineSwift
import SpriteKit
import SwiftUI

/// The SpriteKit comparison: what "keep SpriteKit, use proper sprite animation" means in practice. Every clip is a
/// sequence of full pre-rendered frames (here baked once at launch from the same Spine data, standing in for an
/// artist's sprite sheets), shown on an `SKSpriteNode`. Clip changes can only cross-fade two frames, a look-at
/// needs a pre-rendered pose per direction (not available here), and memory grows with every frame.
@MainActor
final class FlipbookLibrary: ObservableObject {
    struct Clip {
        let frames: [SKTexture]
        let fps: Double
        /// The frame box in stage units (root at the origin); every frame of the clip uses the same box.
        let box: CGRect
    }

    static let fps = 24.0
    @Published private(set) var clips: [String: Clip] = [:]
    @Published private(set) var progress = 0.0
    @Published private(set) var failure: String?
    private(set) var textureBytes = 0
    private(set) var frameCount = 0
    private(set) var bakeSeconds = 0.0

    /// Bakes idle / walk / turn / hop at `pixelsPerUnit` (the on-screen density, so frames are drawn 1:1).
    func bake(profile: MotionProfile, pixelsPerUnit: CGFloat) async {
        guard clips.isEmpty else { return }
        let started = CACurrentMediaTime()
        do {
            let drawable = try await SkeletonDrawableWrapper.fromBundle(atlasFileName: "spineboy-pma.atlas",
                                                                       skeletonFileName: "spineboy-pro.skel")
            defer { drawable.dispose() }
            drawable.animationStateData.defaultMix = 0
            let standing = CGRect(x: -330, y: -30, width: 720, height: 800)
            let airborne = CGRect(x: -330, y: -30, width: 720, height: 1560)
            let specs: [(ClipSpec, CGRect)] = [(profile.idle, standing), (profile.walk.clip, standing),
                                               (profile.turn, standing), (profile.hop, airborne)]
            let total = specs.reduce(0) { $0 + max(1, Int(($1.0.duration * FlipbookLibrary.fps).rounded())) }
            var done = 0
            var result: [String: Clip] = [:]
            for (spec, box) in specs {
                let n = max(1, Int((spec.duration * FlipbookLibrary.fps).rounded()))
                var frames: [SKTexture] = []
                for i in 0..<n {
                    drawable.animationState.clearTracks()
                    drawable.skeleton.setupPose()
                    let entry = drawable.animationState.setAnimation(0, spec.name, true)
                    entry.trackTime = Float(Double(i) / FlipbookLibrary.fps)
                    drawable.skeleton.x = 0
                    drawable.skeleton.y = 0
                    drawable.update(delta: 0)
                    let size = CGSize(width: box.width * pixelsPerUnit, height: box.height * pixelsPerUnit)
                    guard let image = try drawable.renderToImage(
                        size: size, boundsProvider: RawBounds(x: box.minX, y: box.minY, width: box.width, height: box.height),
                        backgroundColor: .clear, scaleFactor: 1)
                    else { continue }
                    let texture = SKTexture(cgImage: image)
                    texture.filteringMode = .linear
                    frames.append(texture)
                    textureBytes += image.width * image.height * 4
                    frameCount += 1
                    done += 1
                    progress = Double(done) / Double(total)
                    await Task.yield()
                }
                result[spec.name] = Clip(frames: frames, fps: FlipbookLibrary.fps, box: box)
            }
            clips = result
            bakeSeconds = CACurrentMediaTime() - started
            labLog(String(format: "ML_FLIPBOOK frames=%d textureMB=%.1f bake=%.2fs ppu=%.3f", frameCount,
                         Double(textureBytes) / 1_048_576, bakeSeconds, pixelsPerUnit))
        } catch {
            failure = "\(error)"
        }
    }
}

final class FlipbookScene: SKScene {
    weak var model: StageModel?
    var library: FlipbookLibrary?
    private let front = SKSpriteNode()
    private let back = SKSpriteNode()
    private var lastSerial = -1
    private var fadeStart = 0.0
    private var fadeDuration = 0.0

    override func didMove(to view: SKView) {
        backgroundColor = .clear
        scaleMode = .resizeFill
        anchorPoint = .zero
        for s in [back, front] {
            s.zPosition = s === front ? 1 : 0
            addChild(s)
        }
        back.alpha = 0
    }

    override func update(_ currentTime: TimeInterval) {
        MainActor.assumeIsolated { step() }
    }

    @MainActor
    private func step() {
        guard let model, let library, !library.clips.isEmpty, size.width > 0 else { return }
        let s = model.tick(now: CACurrentMediaTime())
        let scale = model.viewScale(for: size)
        guard let clip = library.clips[s.base.clip] else { return }
        if s.base.serial != lastSerial {
            // a flipbook cannot blend poses: the outgoing frame is held and faded under the incoming one
            back.texture = front.texture
            back.size = front.size
            back.anchorPoint = front.anchorPoint
            back.position = front.position
            back.xScale = front.xScale
            back.alpha = lastSerial < 0 ? 0 : 1
            fadeStart = s.time
            fadeDuration = lastSerial < 0 ? 0 : s.base.mix
            lastSerial = s.base.serial
        }
        let n = clip.frames.count
        guard n > 0 else { return }
        var index = Int((s.baseClipTime * clip.fps).rounded(.down))
        index = s.base.loop ? ((index % n) + n) % n : min(max(index, 0), n - 1)
        front.texture = clip.frames[index]
        front.size = CGSize(width: clip.box.width * scale, height: clip.box.height * scale)
        front.anchorPoint = CGPoint(x: -clip.box.minX / clip.box.width, y: -clip.box.minY / clip.box.height)
        front.position = model.viewPoint(fromStage: Point(x: s.x, y: 0), size: size).flippedY(in: size)
        front.xScale = CGFloat(s.facing.sign)
        let u = fadeDuration > 0 ? min(1, (s.time - fadeStart) / fadeDuration) : 1
        if u < 1 {
            front.alpha = CGFloat(u)
            back.alpha = CGFloat(1 - u)
        } else {
            front.alpha = 1
            back.alpha = 0
        }
    }
}

private extension CGPoint {
    /// SwiftUI y grows downwards, SpriteKit y upwards.
    func flippedY(in size: CGSize) -> CGPoint { CGPoint(x: x, y: size.height - y) }
}

struct FlipbookStageView: View {
    @ObservedObject var model: StageModel
    @StateObject private var library = FlipbookLibrary()
    @State private var scene = FlipbookScene(size: CGSize(width: 390, height: 360))
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { geo in
            ZStack {
                SpriteView(scene: scene, isPaused: !model.isActive, preferredFramesPerSecond: 60,
                           options: [.allowsTransparency])
                if library.clips.isEmpty {
                    VStack(spacing: 6) {
                        ProgressView(value: library.progress)
                        Text(library.failure ?? "Baking flipbook frames…").font(.caption)
                    }
                    .padding(24)
                }
            }
            .task {
                scene.model = model
                scene.library = library
                await library.bake(profile: model.profile, pixelsPerUnit: model.viewScale(for: geo.size) * displayScale)
                model.diagnostics.mark(String(format: "flipbook baked: %d frames, %.1f MB textures, %.1fs",
                                              library.frameCount, Double(library.textureBytes) / 1_048_576,
                                              library.bakeSeconds), at: model.engine.time)
            }
        }
    }
}
