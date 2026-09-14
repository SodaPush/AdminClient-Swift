import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Group {
            switch store.sessionState {
            case .restoring:
                ProgressView("Restoring session…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .signedOut:
                ServerSetupView()
            case .authenticated:
                DashboardView()
            }
        }
        .task { await store.restoreSession() }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppStore())
}
