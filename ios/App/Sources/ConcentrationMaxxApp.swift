import SwiftUI

@main
struct ConcentrationMaxxApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 12) {
                Image(systemName: "scope")
                    .font(.system(size: 56))
                Text("ConcentrationMaxx")
                    .font(.title.bold())
            }
        }
    }
}
