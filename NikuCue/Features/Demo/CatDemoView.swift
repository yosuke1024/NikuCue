import NikuCueDomain
import SwiftUI

/// P01 vertical slice: the cat breathes, reacts to a tap, and celebrates a demo "done".
/// Nothing here writes a habit record (demo events live in their own namespace, docs/05 §2).
struct CatDemoView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var localizer: Localizer
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var timeOfDay: TimeOfDay = .day
    @State private var showGallery = false
    @ObservedObject private var controller: CatSceneController
    @ObservedObject private var appState: AppState

    init(controller: CatSceneController, appState: AppState) {
        self.controller = controller
        self.appState = appState
    }

    /// The one app-level Reduce Motion preference (docs/03 §7), not a demo-only switch.
    private var reduceMotionBinding: Binding<Bool> {
        Binding(get: { appState.preferences.reduceMotion },
                set: { value in Task { try? await appState.updatePreferences { $0.reduceMotion = value } } })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                CatRoom(height: 260)
                bubble
                controls
                Text(localizer.t("onboarding.demoNote"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if AppConfiguration.isDebugBuild {
                    Text("art: \(container.artProvider.artLabel)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                if AppConfiguration.isDebugBuild, !container.contractProblems.isEmpty {
                    Text(container.contractProblems.joined(separator: "\n"))
                        .font(.caption.monospaced())
                        .foregroundStyle(.red)
                }
            }
            .padding(16)
        }
        .navigationTitle(localizer.t("app.name"))
        .toolbar {
            #if DEBUG
            ToolbarItem(placement: .topBarTrailing) {
                Button("Gallery") { showGallery = true }
            }
            #endif
        }
        .navigationDestination(isPresented: $showGallery) { CharacterGalleryView(controller: container.scene.controller) }
        .onAppear {
            timeOfDay = container.currentTimeOfDay
            container.scene.setTimeOfDay(timeOfDay, animated: false)
            applyReduceMotion()
            controller.enterScene(ambient: timeOfDay.ambient, owner: "demo")
            container.dispatchDemo(kind: .sceneEntered)
        }
        .onDisappear { controller.leaveScene(owner: "demo") }
        .onChange(of: appState.preferences.reduceMotion) { _, _ in applyReduceMotion() }
        .onChange(of: systemReduceMotion) { _, _ in applyReduceMotion() }
    }

    private var bubble: some View {
        // SwiftUI text, never baked into the scene (docs/03 §2)
        Text(controller.messageKey.map { localizer.t($0) } ?? " ")
            .font(.body)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.quaternary))
            .animation(.easeInOut(duration: 0.2), value: controller.messageKey)
            .accessibilityHidden(controller.messageKey == nil)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    container.dispatchDemo(kind: .completionCommitted, category: .custom)
                } label: {
                    Label(localizer.t("common.done"), systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                Button {
                    container.dispatchDemo(kind: .skipCommitted, category: .custom)
                } label: {
                    Label(localizer.t("common.rest"), systemImage: "moon.zzz")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
            Toggle(localizer.t("settings.reduceMotion"), isOn: reduceMotionBinding)
            #if DEBUG
            // Development-only room override (raw values, not user-facing copy); the room normally follows the clock.
            Picker("Room", selection: $timeOfDay) {
                ForEach(TimeOfDay.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: timeOfDay) { _, value in container.scene.setTimeOfDay(value, animated: true) }
            #endif
        }
    }

    private func applyReduceMotion() {
        // App setting OR OS setting (docs/03 §7)
        controller.reduceMotion = appState.preferences.reduceMotion || systemReduceMotion
    }
}
