import NikuCueDomain
import SwiftUI

/// Onboarding O01–O05 (docs/02 §1): intro with the cat → name → first habit → reminder → Home.
///
/// `RootView` shows this view while `preferences.onboardingStep != .finished` and switches to Home by itself
/// once the flow persists `.finished`. The flow is a `NavigationStack` whose path is restored from the persisted
/// step, so a crash resumes where the person left off. No ads and no purchase dialog appear in this first pass.
struct OnboardingFlow: View {
    @EnvironmentObject private var container: AppContainer
    @State private var model: OnboardingViewModel?

    var body: some View {
        Group {
            if let model {
                OnboardingNavigator(model: model)
            } else {
                // The model needs the container, which is only available from the environment, not in `init`.
                Color.clear
                    .onAppear { model = OnboardingViewModel(container: container) }
            }
        }
    }
}

/// Navigation shell: intro as root, the other steps and the demo as pushed pages.
struct OnboardingNavigator: View {
    @EnvironmentObject private var container: AppContainer
    @ObservedObject var model: OnboardingViewModel

    init(model: OnboardingViewModel) {
        _model = ObservedObject(wrappedValue: model)
    }

    var body: some View {
        NavigationStack(path: $model.path) {
            OnboardingIntroStep(model: model, controller: container.scene.controller)
                .navigationDestination(for: OnboardingViewModel.Page.self) { page in
                    switch page {
                    case .demo:
                        // Existing demo: plays reactions in the demo namespace and shows onboarding.demoNote (no records).
                        CatDemoView(controller: container.scene.controller)
                    case .name:
                        OnboardingNameStep(model: model)
                    case .habit:
                        OnboardingHabitStep(model: model, editor: model.editor)
                    case .reminder:
                        OnboardingReminderStep(model: model)
                    }
                }
        }
        .onChange(of: model.path) { oldValue, newValue in
            model.pathChanged(from: oldValue, to: newValue)
        }
    }
}
