import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedApp: AppSummary?

    var body: some View {
        NavigationSplitView {
            appList
                .navigationTitle("Apps")
                .toolbar {
                    ToolbarItem {
                        Button("Sign Out", action: store.logout)
                    }
                }
        } detail: {
            if let selectedApp {
                AppDetailView(app: selectedApp)
                    .id(selectedApp.id)
            } else {
                ContentUnavailableView(
                    "Select an App",
                    systemImage: "app.dashed",
                    description: Text("Choose an app to view devices and send pushes")
                )
            }
        }
        .alert(
            "Account Error",
            isPresented: Binding(
                get: { store.sessionError != nil },
                set: { if !$0 { store.sessionError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.sessionError ?? "")
        }
    }

    @ViewBuilder
    private var appList: some View {
        switch store.appsState {
        case .idle, .loading:
            ProgressView("Loading apps…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .loaded(apps) where apps.isEmpty:
            ContentUnavailableView(
                "No Apps",
                systemImage: "app.dashed",
                description: Text("Create an app through the server API, then refresh this list.")
            )
            .toolbar { refreshButton }
        case let .loaded(apps):
            List(apps, selection: $selectedApp) { app in
                Label(app.name, systemImage: "app.badge")
                    .tag(app as AppSummary?)
            }
            .refreshable { await store.reloadApps() }
            .toolbar { refreshButton }
        case let .failed(message):
            ContentUnavailableView {
                Label("Could Not Load Apps", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") {
                    Task { await store.reloadApps() }
                }
            }
        }
    }

    private var refreshButton: some View {
        Button {
            Task { await store.reloadApps() }
        } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
        }
    }
}
