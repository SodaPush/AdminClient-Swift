import SwiftUI

struct PushesView: View {
    @EnvironmentObject private var store: AppStore
    let app: AppSummary

    @State private var state: CollectionLoadState<[PushJob]> = .idle
    @State private var showingComposer = false
    @State private var selectedPush: PushJob?

    var body: some View {
        Group {
            switch state {
            case .idle, .loading:
                ProgressView("Loading push history…").frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .loaded(pushes) where pushes.isEmpty:
                ContentUnavailableView {
                    Label("No Pushes Yet", systemImage: "paperplane")
                } description: {
                    Text("Created push jobs and their delivery results will appear here.")
                } actions: {
                    if canSendPushes { Button("Send a Push") { showingComposer = true } }
                }
            case let .loaded(pushes):
                List(pushes) { push in
                    Button { selectedPush = push } label: { PushJobRow(push: push) }
                        .buttonStyle(.plain)
                }
                .refreshable { await load() }
            case let .failed(message):
                ContentUnavailableView {
                    Label("Could Not Load Push History", systemImage: "wifi.exclamationmark")
                } description: { Text(message) } actions: {
                    Button("Try Again") { Task { await load() } }
                }
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button { Task { await load() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                if canSendPushes {
                    Button { showingComposer = true } label: { Label("Send Push", systemImage: "paperplane.fill") }
                }
            }
        }
        .sheet(isPresented: $showingComposer) { PushComposerView(app: app) { await load() } }
        .sheet(item: $selectedPush) { push in PushJobDetailView(app: app, initialPush: push) }
        .task(id: app.id) { await load() }
    }

    private func load() async {
        state = .loading
        do { state = .loaded(try await store.pushes(appID: app.id)) }
        catch is CancellationError { return }
        catch { state = .failed(error.localizedDescription) }
    }

    private var canSendPushes: Bool {
        app.role.canSendPushes && app.disabledAt == nil
    }
}

private struct PushJobRow: View {
    let push: PushJob

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: push.pushType == .background ? "arrow.triangle.2.circlepath" : "paperplane.fill")
                .font(.title3)
                .foregroundStyle(StatusBadge.color(for: push.status))
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(push.pushType.rawValue.capitalized).font(.headline)
                    StatusBadge(text: push.environment.rawValue.capitalized, tint: StatusBadge.color(for: push.environment.rawValue))
                }
                Text(push.id).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                Text(SodaDate.formatted(push.createdAt)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                StatusBadge(text: push.status.capitalized, tint: StatusBadge.color(for: push.status))
                if push.totalCount > 0 {
                    Text("\(push.successCount) sent · \(push.failureCount) failed")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct PushComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    let app: AppSummary
    let initialInstallationIDs: [String]
    let onSent: () async -> Void

    @State private var environment: PushEnvironment = .development
    @State private var pushType: PushType = .alert
    @State private var title = ""
    @State private var message = ""
    @State private var customPayload = false
    @State private var payloadText = ""
    @State private var sendToAll: Bool
    @State private var selectedInstallationIDs: Set<String>
    @State private var devices: [DeviceSummary] = []
    @State private var isSending = false
    @State private var errorMessage: String?

    init(app: AppSummary, initialInstallationIDs: [String] = [], onSent: @escaping () async -> Void = {}) {
        self.app = app
        self.initialInstallationIDs = initialInstallationIDs
        self.onSent = onSent
        _sendToAll = State(initialValue: initialInstallationIDs.isEmpty)
        _selectedInstallationIDs = State(initialValue: Set(initialInstallationIDs))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Delivery") {
                    Picker("Environment", selection: $environment) {
                        ForEach(PushEnvironment.allCases) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Push Type", selection: $pushType) {
                        ForEach(PushType.allCases) { Text(typeTitle($0)).tag($0) }
                    }
                    Toggle("Send to all active devices", isOn: $sendToAll)
                }

                if !sendToAll {
                    Section("Devices") {
                        if availableDevices.isEmpty {
                            Text("No active \(environment.rawValue) devices available.").foregroundStyle(.secondary)
                        } else {
                            ForEach(availableDevices) { device in
                                Button { toggle(device.installationID) } label: {
                                    HStack {
                                        Image(systemName: selectedInstallationIDs.contains(device.installationID) ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(selectedInstallationIDs.contains(device.installationID) ? Color.accentColor : .secondary)
                                        VStack(alignment: .leading) {
                                            Text(device.installationID).font(.caption.monospaced())
                                            Text([device.platform, device.appVersion].compactMap { $0 }.joined(separator: " · "))
                                                .font(.caption2).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                if pushType == .alert && !customPayload {
                    Section("Notification") {
                        TextField("Title", text: $title)
                        TextField("Message", text: $message, axis: .vertical).lineLimit(3...8)
                    }
                }

                Section("Payload") {
                    Toggle("Edit custom JSON", isOn: $customPayload)
                    if customPayload || pushType == .liveactivity {
                        TextEditor(text: $payloadText)
                            .font(.caption.monospaced())
                            .frame(minHeight: 180)
                        Text("\(payloadByteCount) / 4096 bytes")
                            .font(.caption)
                            .foregroundStyle(payloadByteCount > 4096 ? .red : .secondary)
                    } else if pushType == .background {
                        Text("A background payload with content-available: 1 will be generated.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                if let errorMessage { Section { InlineErrorView(message: errorMessage) } }
            }
            .formStyle(.grouped)
            .navigationTitle("Send Push")
            .interactiveDismissDisabled(isSending)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: dismiss.callAsFunction).disabled(isSending) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: send) {
                        if isSending { ProgressView().controlSize(.small) } else { Text("Send") }
                    }
                    .disabled(isSending || !canSend)
                }
            }
            .task { await loadDevices() }
            .onChange(of: pushType) { _, newValue in preparePayload(for: newValue) }
            .onChange(of: environment) { _, _ in
                let available = Set(availableDevices.map(\.installationID))
                selectedInstallationIDs.formIntersection(available)
            }
        }
    }

    private var availableDevices: [DeviceSummary] {
        devices.filter { $0.environment == environment && $0.status == "active" }
    }

    private var payloadByteCount: Int { payloadText.data(using: .utf8)?.count ?? 0 }

    private var canSend: Bool {
        if !sendToAll && selectedInstallationIDs.isEmpty { return false }
        if pushType == .alert && !customPayload { return !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if customPayload || pushType == .liveactivity { return !payloadText.isEmpty && payloadByteCount <= 4096 }
        return true
    }

    private func typeTitle(_ type: PushType) -> String {
        switch type {
        case .alert: "Alert"
        case .background: "Background"
        case .liveactivity: "Live Activity"
        }
    }

    private func toggle(_ id: String) {
        if !selectedInstallationIDs.insert(id).inserted { selectedInstallationIDs.remove(id) }
    }

    private func preparePayload(for type: PushType) {
        if type == .liveactivity {
            customPayload = true
            if payloadText.isEmpty { payloadText = #"{"aps":{"timestamp":0,"event":"update","content-state":{}}}"# }
        }
    }

    private func loadDevices() async {
        do {
            devices = try await store.devices(appID: app.id)
            if let selected = devices.first(where: { initialInstallationIDs.contains($0.installationID) }) {
                environment = selected.environment
            }
        } catch is CancellationError { return }
        catch { errorMessage = error.localizedDescription }
    }

    private func buildPayload() throws -> JSONValue {
        if customPayload || pushType == .liveactivity {
            guard let data = payloadText.data(using: .utf8) else { throw ComposerError.invalidPayload }
            do {
                let value = try JSONDecoder().decode(JSONValue.self, from: data)
                guard case .object = value else { throw ComposerError.invalidPayload }
                return value
            }
            catch { throw ComposerError.invalidPayload }
        }
        switch pushType {
        case .alert:
            return APNsPayload(
                aps: APS(
                    alert: PushAlert(
                        title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                        body: message.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                )
            ).jsonValue
        case .background:
            return .object(["aps": .object(["content-available": .number(1)])])
        case .liveactivity:
            throw ComposerError.invalidPayload
        }
    }

    private func send() {
        Task {
            isSending = true
            errorMessage = nil
            defer { isSending = false }
            do {
                let payload = try buildPayload()
                let encoded = try JSONEncoder().encode(payload)
                guard encoded.count <= 4096 else { throw ComposerError.payloadTooLarge }
                let target = sendToAll ? PushTarget(all: true) : PushTarget(installationIds: Array(selectedInstallationIDs).sorted())
                _ = try await store.sendPush(appID: app.id, request: PushRequest(environment: environment, pushType: pushType, target: target, payload: payload))
                await onSent()
                dismiss()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private enum ComposerError: LocalizedError {
        case invalidPayload, payloadTooLarge
        var errorDescription: String? {
            switch self {
            case .invalidPayload: "Enter a valid JSON object for the APNs payload."
            case .payloadTooLarge: "The APNs payload exceeds 4096 bytes."
            }
        }
    }
}

private struct PushJobDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    let app: AppSummary
    let initialPush: PushJob

    @State private var detail: PushDetailResponse?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Status") {
                    let push = detail?.push ?? initialPush
                    HStack {
                        StatusBadge(text: push.status.capitalized, tint: StatusBadge.color(for: push.status))
                        StatusBadge(text: push.environment.rawValue.capitalized, tint: StatusBadge.color(for: push.environment.rawValue))
                        Spacer()
                        Text(push.pushType.rawValue.capitalized).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 12) {
                        MetricTile(title: "Total", value: "\(push.totalCount)", systemImage: "tray.full")
                        MetricTile(title: "Sent", value: "\(push.successCount)", systemImage: "checkmark", tint: .green)
                        MetricTile(title: "Failed", value: "\(push.failureCount)", systemImage: "xmark", tint: .red)
                    }
                }
                Section("Job") {
                    LabeledContent("ID", value: push.id)
                    LabeledContent("Created", value: SodaDate.formatted(push.createdAt))
                    LabeledContent("Updated", value: SodaDate.formatted(push.updatedAt))
                }
                Section("Deliveries") {
                    if let deliveries = detail?.deliveries, !deliveries.isEmpty {
                        ForEach(deliveries) { DeliveryRow(delivery: $0) }
                    } else {
                        Text("No delivery results yet.").foregroundStyle(.secondary)
                    }
                }
                if let errorMessage { Section { InlineErrorView(message: errorMessage) } }
            }
            .navigationTitle("Push Details")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done", action: dismiss.callAsFunction) }
                ToolbarItem { Button { Task { await load() } } label: { Label("Refresh", systemImage: "arrow.clockwise") } }
            }
            .task { await pollUntilComplete() }
        }
    }

    private var push: PushJob { detail?.push ?? initialPush }

    private func load() async {
        do { detail = try await store.push(appID: app.id, pushID: initialPush.id); errorMessage = nil }
        catch is CancellationError { return }
        catch { errorMessage = error.localizedDescription }
    }

    private func pollUntilComplete() async {
        await load()
        while !["completed", "partial", "failed"].contains(push.status) && !Task.isCancelled {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await load()
        }
    }
}

private struct DeliveryRow: View {
    let delivery: Delivery

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: delivery.status == "sent" ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(delivery.status == "sent" ? .green : .red)
            VStack(alignment: .leading, spacing: 4) {
                Text(delivery.deviceID ?? "Unknown device").font(.caption.monospaced()).textSelection(.enabled)
                if let reason = delivery.reason { Text(reason).font(.caption).foregroundStyle(.red) }
                Text([delivery.apnsStatus.map(String.init), delivery.apnsID].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            StatusBadge(text: delivery.status.capitalized, tint: StatusBadge.color(for: delivery.status))
        }
        .padding(.vertical, 4)
    }
}
