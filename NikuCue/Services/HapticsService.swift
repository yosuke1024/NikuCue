import UIKit

/// Optional haptics (docs/01 §4: sound off by default, haptics on/off). Every state is also visible without them.
@MainActor
final class HapticsService {
    var isEnabled = true

    func success() {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func light() {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
