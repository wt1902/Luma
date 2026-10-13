import SwiftUI

@main
@MainActor
struct LumaApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .tint(Color(red: 0.14, green: 0.56, blue: 0.96))
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        model.setApplicationActive(true)
                    case .background:
                        model.setApplicationActive(false)
                    case .inactive:
                        // App switcher, Control Center and system pickers
                        // (photo gallery) make the scene briefly inactive;
                        // locking here would block the picker and the
                        // unlock screen would replace the app mid-flow.
                        break
                    @unknown default:
                        break
                    }
                }
        }
#if os(macOS)
        .defaultSize(width: 1_080, height: 720)
#endif
    }
}
