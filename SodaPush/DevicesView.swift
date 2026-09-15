import SwiftUI

private enum DeviceEnvironmentFilter: String, CaseIterable, Identifiable {
    case all, development, production
    var id: Self { self }
    var title: String { self == .development ? "Sandbox" : rawValue.capitalized }
}

struct DevicesView: View {
    @EnvironmentObject private var store: AppStore
    let app: AppSummary

    @State private var state: CollectionLoadState<[DeviceSummary]> = .idle
    @State private var searchText = ""
    @State private var environment: DeviceEnvironmentFilter = .all
    @State private var showInactive = false
    @State private var selectedIDs: Set<String> = []
    @State private var pendingDeactivation: DeviceSummary?
    @State private var showingComposer = false

    var body: some View {
        VStack(spacing: 0) {
            filters
            List {
                if isLoading {
                    ProgressView("Loading devices…")
                } else if case let .loaded(devices) = state, filtered(devices).isEmpty {
                    ContentUnavailableView("No Devices", systemImage: "iphone.slash", description: Text("No devices match the current filters."))
                } else if case let .loaded(devices) = state {
                    ForEach(filtered(devices)) { device in
                        DeviceRow(
                            device: device,
                            isSelected: selectedIDs.contains(device.id),
                            selectionEnabled: app.role.canSendPushes && app.disabledAt == nil,
                            toggleSelection: { toggle(device) },
                            deactivate: app.role.canManageApps && device.status == "active" ? { pendingDeactivation = device } : nil
                        )
                    }
                } else if case let .failed(message) = state {
                    ContentUnavailableView {
                        Label("Could Not Load Devices", systemImage: "wifi.exclamationmark")
                    } description: { Text(message) } actions: {
                        Button("Try Again") { Task { await load() } }
                    }
                }
            }
            .refreshable { await load() }
        }
        .toolbar {
            ToolbarItemGroup {
                Button { Task { await load() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                if app.role.canSendPushes && app.disabledAt == nil && !selectedIDs.isEmpty {
                    Button { showingComposer = true } label: { Label("Send to \(selectedIDs.count)", systemImage: "paperplane.fill") }
                }
            }
        }
        .sheet(isPresented: $showingComposer) {
            PushComposerView(app: app, initialInstallationIDs: selectedInstallationIDs)
        }
        .alert("Deactivate Device?", isPresented: deactivationPresented, presenting: pendingDeactivation) { device in
            Button("Deactivate", role: .destructive) { deactivate(device) }
            Button("Cancel", role: .cancel) { pendingDeactivation = nil }
        } message: { device in
            Text("\(device.installationID) will stop receiving \(device.environment.rawValue) pushes until it registers again.")
        }
        .task(id: app.id) { await load() }
    }

    private var filters: some View {
        HStack(spacing: 14) {
            Picker("Environment", selection: $environment) {
                ForEach(DeviceEnvironmentFilter.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Toggle("Show inactive", isOn: $showInactive)
                .toggleStyle(.switch)
                .fixedSize()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
        .searchable(text: $searchText, prompt: "Installation ID, version, or locale")
    }

    private var isLoading: Bool {
        if case .idle = state { return true }
        if case .loading = state { return true }
        return false
    }

    private var deactivationPresented: Binding<Bool> {
        Binding(get: { pendingDeactivation != nil }, set: { if !$0 { pendingDeactivation = nil } })
    }

    private var selectedInstallationIDs: [String] {
        guard case let .loaded(devices) = state else { return [] }
        return devices.filter { selectedIDs.contains($0.id) }.map(\.installationID)
    }

    private func filtered(_ devices: [DeviceSummary]) -> [DeviceSummary] {
        devices.filter { device in
            let matchesEnvironment = environment == .all || device.environment.rawValue == environment.rawValue
            let matchesStatus = showInactive || device.status == "active"
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch = query.isEmpty || ([device.installationID, device.platform, device.appVersion, device.appBuild, device.locale, device.language, device.userID]
                .compactMap { $0 }
                + (device.tags ?? []))
                .contains { $0.localizedCaseInsensitiveContains(query) }
            return matchesEnvironment && matchesStatus && matchesSearch
        }
    }

    private func load() async {
        if case .loaded = state {} else { state = .loading }
        do {
            let devices = try await store.devices(appID: app.id)
            state = .loaded(devices)
            selectedIDs.formIntersection(Set(devices.map(\.id)))
        } catch is CancellationError { return }
        catch { state = .failed(error.localizedDescription) }
    }

    private func toggle(_ device: DeviceSummary) {
        if !selectedIDs.insert(device.id).inserted { selectedIDs.remove(device.id) }
    }

    private func deactivate(_ device: DeviceSummary) {
        pendingDeactivation = nil
        Task {
            do {
                let updated = try await store.deactivateDevice(appID: app.id, installationID: device.installationID, environment: device.environment)
                if case var .loaded(devices) = state, let index = devices.firstIndex(where: { $0.id == updated.id }) {
                    devices[index] = updated
                    state = .loaded(devices)
                    selectedIDs.remove(updated.id)
                }
            } catch { state = .failed(error.localizedDescription) }
        }
    }
}

private struct DeviceRow: View {
    let device: DeviceSummary
    let isSelected: Bool
    let selectionEnabled: Bool
    let toggleSelection: () -> Void
    let deactivate: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if selectionEnabled {
                Button(action: toggleSelection) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isSelected ? "Deselect device" : "Select device")
            }
            VStack(alignment: .leading, spacing: 7) {
                Text(device.installationID)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                HStack(spacing: 6) {
                    StatusBadge(text: device.environment.title, tint: StatusBadge.color(for: device.environment.rawValue))
                    StatusBadge(text: device.status.capitalized, tint: StatusBadge.color(for: device.status))
                    Text(device.platform).font(.caption).foregroundStyle(.secondary)
                }
                Text(metadata)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let tags = device.tags, !tags.isEmpty {
                    Text(tags.map { "#\($0)" }.joined(separator: "  "))
                        .font(.caption2)
                        .foregroundStyle(.tint)
                }
            }
            Spacer()
            if let deactivate {
                Menu {
                    Button("Deactivate", role: .destructive, action: deactivate)
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private var metadata: String {
        let versionText: String
        switch (device.appVersion, device.appBuild) {
        case let (version?, build?): versionText = "\(version) (build \(build))"
        case let (version?, nil): versionText = version
        case let (nil, build?): versionText = "Build \(build)"
        case (nil, nil): versionText = "Unknown version"
        }
        return [versionText, device.language, device.locale, device.userID.map { "User \($0)" }, device.timeZone, "Updated \(SodaDate.formatted(device.updatedAt))"]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}
