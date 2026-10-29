import SwiftUI

@main
struct JavaMCApp: App {
    @ObservedObject private var model = AppModel.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .onAppear { model.boot() }
        }
    }
}
