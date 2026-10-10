import NikuCueDomain
import SwiftUI

/// P02 character gallery: plays all eight clips and five expressions for visual approval (R02).
/// Debug builds only; never shown in the shipping navigation and never shows ads.
struct CharacterGalleryView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var localizer: Localizer
    @State private var actionCount = 0
    @State private var timer: Timer?

    private var controller: CatSceneController { container.scene.controller }

    private let messageKeys: [ClipID: String] = [
        .greet: "reaction.greet.1", .pet: "reaction.pet.1", .celebrate: "reaction.complete.1", .cheer: "reaction.cheer.1",
        .settle: "reaction.rest.1", .doze: "reaction.doze.1", .milestone: "reaction.milestone.3",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                CatRoom(height: 260)
                Text(controller.messageKey.map { localizer.t($0) } ?? " ")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                section("Clips") {
                    ForEach(ClipID.allCases, id: \.self) { clip in
                        Button(clip.rawValue) {
                            controller.playDemo(clip, messageKey: messageKeys[clip], dayKey: CalendarService(clock: container.clock).dayKey(for: container.clock.now))
                        }
                        .buttonStyle(.bordered)
                    }
                }
                section("Expressions") {
                    ForEach(Expression.allCases, id: \.self) { e in
                        Button(e.rawValue) { container.rig.setExpression(e, blend: container.animationSpec.expressionBlend) }
                            .buttonStyle(.bordered)
                    }
                }
                Toggle("Reduce Motion", isOn: Binding(get: { controller.reduceMotion }, set: { controller.reduceMotion = $0 }))
                Text("Active actions: \(actionCount)  ·  nodes: \(container.rig.nodes.count)  ·  art: \(container.artProvider.isProductionArt ? "production" : "prototype")")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Text("Prototype art. Not approved production art (R02).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .navigationTitle("Character Gallery")
        .onAppear {
            controller.enterScene(ambient: .idle)
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                Task { @MainActor in actionCount = controller.activeActionCount }
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
            controller.leaveScene()
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], alignment: .leading, spacing: 8) { content() }
        }
    }
}
