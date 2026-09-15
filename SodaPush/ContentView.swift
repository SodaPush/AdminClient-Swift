import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ZStack {
            Color.clear
            if case .restoring = store.sessionState {
                VStack(spacing: 14) {
                    SodaBrandIcon(size: 64)
                        .accessibilityHidden(true)
                    ProgressView("Restoring your workspace…")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if case .signedOut = store.sessionState {
                ServerSetupView()
            } else {
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
