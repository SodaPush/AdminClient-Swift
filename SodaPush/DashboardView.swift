import SwiftUI

private enum WorkspaceSection: String, CaseIterable, Identifiable {
    case overview, apps, users, settings

    var id: Self { self }
    var title: String { rawValue.capitalized }
    var systemImage: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .apps: "app.badge"
        case .users: "person.2"
        case .settings: "gearshape"
        }
    }
}

struct DashboardView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selection: WorkspaceSection? = .overview

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Workspace") {
                    sidebarRow(.overview)
                    sidebarRow(.apps)
                    if store.currentUser?.role.canManageUsers == true { sidebarRow(.users) }
                }
                Section {
                    sidebarRow(.settings)
                }
            }
            .navigationTitle("SodaPush")
            .safeAreaInset(edge: .bottom) { accountFooter }
        } detail: {
            detailContent
        }
        .alert("Account Error", isPresented: sessionErrorPresented) {
            Button("OK", role: .cancel) { store.sessionError = nil }
        } message: {
            Text(store.sessionError ?? "")
        }
    }

    private func sidebarRow(_ section: WorkspaceSection) -> some View {
        Label(section.title, systemImage: section.systemImage)
            .tag(section as WorkspaceSection?)
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selection ?? .overview {
        case .overview:
            OverviewView(openApps: { selection = .apps })
        case .apps:
            AppsWorkspaceView()
        case .users:
            UserManagementView()
        case .settings:
            SettingsView()
        }
    }

    private var accountFooter: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.circle.fill")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.currentUser?.username ?? "Account")
                    .font(.subheadline.weight(.semibold))
                Text(store.currentUser?.role.title ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(.bar)
    }

    private var sessionErrorPresented: Binding<Bool> {
        Binding(get: { store.sessionError != nil }, set: { if !$0 { store.sessionError = nil } })
    }
}

private struct OverviewView: View {
    @EnvironmentObject private var store: AppStore
    let openApps: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Good to see you, \(store.currentUser?.username ?? "operator")")
                        .font(.largeTitle.bold())
                    Text(store.activeProfile?.baseURL.host ?? "Your SodaPush workspace")
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 14)], spacing: 14) {
                    MetricTile(title: "Applications", value: "\(apps.count)", systemImage: "app.badge")
                    MetricTile(title: "Active", value: "\(apps.filter { $0.disabledAt == nil }.count)", systemImage: "checkmark.circle", tint: .green)
                    MetricTile(title: "Disabled", value: "\(apps.filter { $0.disabledAt != nil }.count)", systemImage: "pause.circle", tint: .orange)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Start with an application", systemImage: "paperplane.fill")
                            .font(.headline)
                        Text("Open an app to configure APNs, rotate registration keys, inspect devices, and send notifications.")
                            .foregroundStyle(.secondary)
                        Button("Open Applications", action: openApps)
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(28)
            .frame(maxWidth: 960, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .navigationTitle("Overview")
    }

    private var apps: [AppSummary] {
        guard case let .loaded(apps) = store.appsState else { return [] }
        return apps
    }
}

private struct AppsWorkspaceView: View {
    @EnvironmentObject private var store: AppStore
    @State private var searchText = ""
    @State private var showingCreateApp = false

    var body: some View {
        NavigationStack {
            Group {
                switch store.appsState {
                case .idle, .loading:
                    List(0..<4, id: \.self) { _ in AppPlaceholderRow() }
                        .redacted(reason: .placeholder)
                case let .loaded(apps) where filtered(apps).isEmpty:
                    ContentUnavailableView {
                        Label(searchText.isEmpty ? "No Applications" : "No Matches", systemImage: "app.dashed")
                    } description: {
                        Text(searchText.isEmpty ? "Create your first application to configure APNs and register devices." : "Try a different search term.")
                    } actions: {
                        if searchText.isEmpty && store.currentUser?.role.canManageApps == true {
                            Button("Create Application") { showingCreateApp = true }
                        }
                    }
                case let .loaded(apps):
                    List(filtered(apps)) { app in
                        NavigationLink(value: app) { AppRow(app: app) }
                    }
                    .refreshable { await store.reloadApps() }
                case let .failed(message):
                    ContentUnavailableView {
                        Label("Could Not Load Applications", systemImage: "wifi.exclamationmark")
                    } description: { Text(message) } actions: {
                        Button("Try Again") { Task { await store.reloadApps() } }
                    }
                }
            }
            .navigationTitle("Applications")
            .searchable(text: $searchText, prompt: "Name or bundle ID")
            .navigationDestination(for: AppSummary.self) { app in AppDetailView(app: app) }
            .toolbar {
                ToolbarItemGroup {
                    Button { Task { await store.reloadApps() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    if store.currentUser?.role.canManageApps == true {
                        Button { showingCreateApp = true } label: { Label("Create Application", systemImage: "plus") }
                    }
                }
            }
            .sheet(isPresented: $showingCreateApp) { CreateAppView() }
        }
    }

    private func filtered(_ apps: [AppSummary]) -> [AppSummary] {
        guard !searchText.isEmpty else { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(searchText) || $0.bundleID.localizedCaseInsensitiveContains(searchText) }
    }
}

private struct AppRow: View {
    let app: AppSummary

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: app.disabledAt == nil ? "app.badge.fill" : "app.badge")
                .font(.title2)
                .foregroundStyle(app.disabledAt == nil ? Color.accentColor : .secondary)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(app.name).font(.headline)
                Text(app.bundleID).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            Spacer()
            StatusBadge(text: app.disabledAt == nil ? "Active" : "Disabled", tint: app.disabledAt == nil ? .green : .red)
            StatusBadge(text: app.role.title, tint: app.role.tint)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }
}

private struct AppPlaceholderRow: View {
    var body: some View {
        HStack {
            Image(systemName: "app.badge.fill").font(.title2)
            VStack(alignment: .leading) { Text("Application Name"); Text("com.example.application").font(.caption) }
        }
        .padding(.vertical, 6)
    }
}
