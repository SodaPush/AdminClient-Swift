import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        NavigationSplitView {
            List {
                Section("Workspace") {
                    NavigationLink { OverviewView() } label: { Label("Overview", systemImage: "square.grid.2x2") }
                    NavigationLink { AppsWorkspaceView() } label: { Label("Applications", systemImage: "app.badge") }
                    if store.currentUser?.role.canManageUsers == true {
                        NavigationLink { UserManagementView() } label: { Label("Users", systemImage: "person.2") }
                    }
                }
                Section {
                    NavigationLink { SettingsView() } label: { Label("Settings", systemImage: "gearshape") }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("SodaPush")
            .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 300)
            .safeAreaInset(edge: .bottom) { accountFooter }
        } detail: {
            OverviewView()
        }
        .alert("Account Error", isPresented: sessionErrorPresented) {
            Button("OK", role: .cancel) { store.sessionError = nil }
        } message: {
            Text(store.sessionError ?? "")
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    SodaBrandIcon(size: 64)
                        .accessibilityHidden(true)
                    Label("YOUR APNS CONTROL PLANE", systemImage: "cloud.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tint)
                    Text("Your push infrastructure, your rules.")
                        .font(.largeTitle.bold())
                    Text("Manage Apple notifications from the backend you deployed. Credentials, devices, and delivery records stay in your account.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let host = store.activeProfile?.baseURL.host {
                        Label(host, systemImage: "network")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(26)
                .background {
                    RoundedRectangle(cornerRadius: 22)
                        .fill(LinearGradient(colors: [Color.accentColor.opacity(0.16), Color.accentColor.opacity(0.03)], startPoint: .topLeading, endPoint: .bottomTrailing))
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 14)], spacing: 14) {
                    MetricTile(title: "Applications", value: "\(apps.count)", systemImage: "square.stack.3d.up")
                    MetricTile(title: "Active", value: "\(apps.filter { $0.disabledAt == nil }.count)", systemImage: "checkmark.circle", tint: .green)
                    MetricTile(title: "Disabled", value: "\(apps.filter { $0.disabledAt != nil }.count)", systemImage: "pause.circle", tint: .orange)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Start with an application", systemImage: "paperplane.fill")
                            .font(.headline)
                        Text("Open an app to configure APNs, rotate registration keys, inspect devices, and send notifications.")
                            .foregroundStyle(.secondary)
                        NavigationLink {
                            AppsWorkspaceView()
                        } label: {
                            Label("Open Applications", systemImage: "arrow.right.circle.fill")
                        }
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
            List {
                if isLoading {
                    ForEach(0..<4, id: \.self) { _ in AppPlaceholderRow() }
                        .redacted(reason: .placeholder)
                } else if case let .loaded(apps) = store.appsState, filtered(apps).isEmpty {
                    ContentUnavailableView {
                        Label(searchText.isEmpty ? "No Applications" : "No Matches", systemImage: "app.dashed")
                    } description: {
                        Text(searchText.isEmpty ? "Create your first application to configure APNs and register devices." : "Try a different search term.")
                    } actions: {
                        if searchText.isEmpty && store.currentUser?.role.canManageApps == true {
                            Button("Create Application") { showingCreateApp = true }
                        }
                    }
                } else if case let .loaded(apps) = store.appsState {
                    ForEach(filtered(apps)) { app in
                        NavigationLink {
                            AppDetailView(app: app)
                        } label: {
                            AppRow(app: app)
                        }
                    }
                } else if case let .failed(message) = store.appsState {
                    ContentUnavailableView {
                        Label("Could Not Load Applications", systemImage: "wifi.exclamationmark")
                    } description: { Text(message) } actions: {
                        Button("Try Again") { Task { await store.reloadApps() } }
                    }
                }
            }
            .refreshable { await store.reloadApps() }
            .navigationTitle("Applications")
            .searchable(text: $searchText, prompt: "Name or bundle ID")
            .toolbar {
                ToolbarItemGroup {
                    Button { Task { await store.reloadApps() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    if store.currentUser?.role.canManageApps == true {
                        Button { showingCreateApp = true } label: { Label("New Application", systemImage: "plus.circle.fill") }
                            .buttonStyle(.borderedProminent)
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

    private var isLoading: Bool {
        if case .idle = store.appsState { return true }
        if case .loading = store.appsState { return true }
        return false
    }
}

private struct AppRow: View {
    let app: AppSummary

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: app.disabledAt == nil ? "square.stack.3d.up.fill" : "square.stack.3d.up")
                .font(.title2)
                .foregroundStyle(app.disabledAt == nil ? Color.accentColor : .secondary)
                .frame(width: 44, height: 44)
                .background(Color.accentColor.opacity(0.11), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(app.name).font(.headline)
                Text(app.bundleID).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            Spacer()
            StatusBadge(text: app.disabledAt == nil ? "Active" : "Disabled", tint: app.disabledAt == nil ? .green : .red)
            StatusBadge(text: app.role.title, tint: app.role.tint)
        }
        .padding(.vertical, 8)
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
