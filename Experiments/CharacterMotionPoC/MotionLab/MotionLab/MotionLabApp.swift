import SwiftUI

/// Technical evaluation app (not NikuCue, never shipped): the CatBehavior engine driving the official Spine sample
/// "spineboy" through spine-ios inside SwiftUI, with a SpriteKit flipbook renderer for comparison.
@main
struct MotionLabApp: App {
    @StateObject private var model = StageModel(config: .fromLaunchArguments())

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
    }
}
