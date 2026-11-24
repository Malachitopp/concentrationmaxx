import SwiftUI

@main
struct ConcentrationMaxxApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(model.screenTime)
                .environmentObject(model.notifications)
        }
    }
}
