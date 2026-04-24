import SwiftUI

@main
struct DeplogNativeApp: App {
    @StateObject private var store = DeploymentStore()

    var body: some Scene {
        MenuBarExtra {
            MenuBarRootView()
                .environmentObject(store)
                .frame(width: 360, height: 460)
                .task {
                    await store.start()
                }
        } label: {
            TrayLabel()
        }
        .menuBarExtraStyle(.window)
    }
}

struct TrayLabel: View {
    var body: some View {
        Image(systemName: "arrowtriangle.down.fill")
            .font(.system(size: 14, weight: .semibold))
    }
}
