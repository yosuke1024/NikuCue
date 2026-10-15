import CatBehavior
import SwiftUI

/// Evaluation UI. Strings are inline on purpose: this lab is a development tool, not the localized product.
struct ContentView: View {
    @ObservedObject var model: StageModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 10) {
            Text("Technical evaluation · official Spine sample “spineboy” (evaluation only, not a NikuCue asset)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            stage
            controls
            if model.showHUD { hud }
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
        .background(Color(red: 0.97, green: 0.95, blue: 0.91))
        .onChange(of: scenePhase) { _, phase in model.setActive(phase == .active) }
    }

    private var stage: some View {
        GeometryReader { geo in
            ZStack {
                RoomBackdrop(model: model, size: geo.size)
                switch model.renderer {
                case .spine: SpineStageView(model: model)
                case .flipbook: FlipbookStageView(model: model)
                }
                ForEach(model.taps) { tap in
                    let p = model.viewPoint(fromStage: tap.point, size: geo.size)
                    TapRing(scripted: tap.scripted).position(p)
                }
            }
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { value in
                model.tap(at: model.stagePoint(fromView: value.location, size: geo.size))
            })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Character stage")
            .accessibilityValue(model.hud.activity)
        }
        .aspectRatio(CGFloat((model.stage.maxX - model.stage.minX) / (model.stage.height + model.floorDepth)), contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 12)
    }

    private var controls: some View {
        VStack(spacing: 8) {
            Picker("Renderer", selection: $model.renderer) {
                ForEach(RendererKind.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            HStack {
                Button("Done ✓ (celebrate)") { model.celebrate() }
                    .buttonStyle(.borderedProminent)
                Button("Skip (rest is fine)") { model.encourageRest() }
                    .buttonStyle(.bordered)
            }
            HStack {
                Toggle("Reduce Motion (app)", isOn: $model.appReduceMotion)
                Toggle("HUD", isOn: $model.showHUD).fixedSize()
            }
            .font(.footnote)
        }
        .padding(.horizontal, 16)
    }

    private var hud: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(format: "%@ · %@ · x %.0f · %.0f fps · %.0f MB", model.hud.activity, model.hud.mode, model.hud.x,
                        model.hud.fps, model.hud.memoryMB))
            Text("Reduce Motion: system \(model.systemReduceMotion ? "on" : "off"), effective \(model.effectiveReduceMotion ? "on" : "off")")
            if let remaining = model.hud.scenarioRemaining {
                Text(String(format: "scenario %@ · %.0f s left%@", model.config.scenario ?? "", remaining,
                            model.scenarioFinished ? " · done" : ""))
            }
            ForEach(model.hud.log, id: \.self) { Text($0).foregroundStyle(.secondary) }
        }
        .font(.system(size: 10, design: .monospaced))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
    }
}

/// The room, drawn in SwiftUI under the renderer with the same stage → view mapping (wall, floor, window, cushion,
/// toy). Spots come from the engine's stage layout, so what the character walks to is what you see.
struct RoomBackdrop: View {
    @ObservedObject var model: StageModel
    var size: CGSize

    var body: some View {
        Canvas { ctx, size in
            let floorY = model.viewPoint(fromStage: Point(x: 0, y: 0), size: size).y
            ctx.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: floorY)), with: .color(Color(red: 1.0, green: 0.95, blue: 0.86)))
            ctx.fill(Path(CGRect(x: 0, y: floorY, width: size.width, height: size.height - floorY)),
                     with: .color(Color(red: 0.92, green: 0.84, blue: 0.72)))
            ctx.stroke(Path { p in p.move(to: CGPoint(x: 0, y: floorY)); p.addLine(to: CGPoint(x: size.width, y: floorY)) },
                       with: .color(Color(red: 0.78, green: 0.66, blue: 0.52)), lineWidth: 1)
            let s = model.viewScale(for: size)
            if let w = model.stage.spot(.window), let look = w.lookAt {
                let c = model.viewPoint(fromStage: look, size: size)
                let rect = CGRect(x: max(4, c.x - 10), y: c.y - 160 * s, width: 300 * s, height: 360 * s)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 8), with: .color(Color(red: 0.80, green: 0.90, blue: 0.97)))
                ctx.stroke(Path(roundedRect: rect, cornerRadius: 8), with: .color(Color(red: 0.62, green: 0.52, blue: 0.42)), lineWidth: 2)
            }
            if let cushion = model.stage.spot(.cushion) {
                let c = model.viewPoint(fromStage: Point(x: cushion.x, y: 0), size: size)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 230 * s, y: c.y - 30 * s, width: 460 * s, height: 70 * s)),
                         with: .color(Color(red: 0.84, green: 0.62, blue: 0.55)))
            }
            if let toy = model.stage.spot(.toy), let look = toy.lookAt {
                let c = model.viewPoint(fromStage: Point(x: look.x, y: 0), size: size)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 34 * s, y: c.y - 68 * s, width: 68 * s, height: 68 * s)),
                         with: .color(Color(red: 0.95, green: 0.55, blue: 0.40)))
            }
        }
    }
}

struct TapRing: View {
    var scripted: Bool
    @State private var grow = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(scripted ? Color.purple : Color.blue, lineWidth: 2)
                .frame(width: grow ? 54 : 18, height: grow ? 54 : 18)
                .opacity(grow ? 0 : 0.9)
            if scripted {
                Text("scripted tap").font(.system(size: 8)).foregroundStyle(.purple).offset(y: 22)
            }
        }
        .allowsHitTesting(false)
        .onAppear { withAnimation(.easeOut(duration: 0.8)) { grow = true } }
    }
}
