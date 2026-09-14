import SwiftUI

struct AppDetailView: View {
    @EnvironmentObject private var store: AppStore
    let app: AppSummary

    @State private var devicesState: CollectionLoadState<[DeviceSummary]> = .idle
    @State private var showingComposer = false
    @State private var confirmationMessage: String?

    var body: some View {
        List {
            Section("App") {
                LabeledContent("Name", value: app.name)
                LabeledContent("Bundle ID", value: app.bundleID)
            }

            Section("Devices") {
                devicesContent
            }
        }
        .navigationTitle(app.name)
        .toolbar {
            Button {
                Task { await loadDevices() }
            } label: {
                Label("Refresh Devices", systemImage: "arrow.clockwise")
            }
            Button("Send Push") { showingComposer = true }
        }
        .sheet(isPresented: $showingComposer) {
            PushComposerView(appName: app.name, onSend: sendPush)
        }
        .task(id: app.id) { await loadDevices() }
        .alert(
            "Push Job",
            isPresented: Binding(
                get: { confirmationMessage != nil },
                set: { if !$0 { confirmationMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(confirmationMessage ?? "")
        }
    }

    @ViewBuilder
    private var devicesContent: some View {
        switch devicesState {
        case .idle, .loading:
            HStack {
                Spacer()
                ProgressView("Loading devices…")
                Spacer()
            }
        case let .loaded(devices) where devices.isEmpty:
            ContentUnavailableView("No Devices", systemImage: "iphone.slash")
        case let .loaded(devices):
            ForEach(devices) { device in
                VStack(alignment: .leading, spacing: 4) {
                    Text(device.installationID)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                    Text("\(device.platform) · \(device.environment.rawValue) · \(device.status)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        case let .failed(message):
            VStack(alignment: .leading, spacing: 8) {
                Label("Could Not Load Devices", systemImage: "wifi.exclamationmark")
                    .font(.headline)
                Text(message)
                    .foregroundStyle(.secondary)
                Button("Try Again") {
                    Task { await loadDevices() }
                }
            }
        }
    }

    private func loadDevices() async {
        devicesState = .loading
        do {
            devicesState = .loaded(try await store.devices(appID: app.id))
        } catch is CancellationError {
            return
        } catch {
            devicesState = .failed(error.localizedDescription)
        }
    }

    private func sendPush(body: String, environment: PushEnvironment) async throws {
        let request = PushRequest(
            environment: environment,
            pushType: .alert,
            target: PushTarget(all: true),
            payload: APNsPayload(aps: APS(alert: PushAlert(title: app.name, body: body)))
        )
        let response = try await store.sendPush(appID: app.id, request: request)
        confirmationMessage = String(
            format: String(localized: "Job created: %@"),
            response.jobID
        )
    }
}

private struct PushComposerView: View {
    @Environment(\.dismiss) private var dismiss
    let appName: String
    let onSend: (String, PushEnvironment) async throws -> Void

    @State private var bodyText = ""
    @State private var environment: PushEnvironment = .development
    @State private var isSending = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Destination") {
                    Picker("Environment", selection: $environment) {
                        Text("Development").tag(PushEnvironment.development)
                        Text("Production").tag(PushEnvironment.production)
                    }
                    .pickerStyle(.segmented)
                    Text("The push is sent to all active \(environment.rawValue) devices for \(appName).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Notification") {
                    TextField("Notification body", text: $bodyText, axis: .vertical)
                        .lineLimit(3...8)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Send Push")
            .interactiveDismissDisabled(isSending)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismiss.callAsFunction)
                        .disabled(isSending)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: send) {
                        if isSending {
                            ProgressView()
                        } else {
                            Text("Send")
                        }
                    }
                    .disabled(isSending || trimmedBody.isEmpty)
                }
            }
        }
    }

    private var trimmedBody: String {
        bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func send() {
        isSending = true
        errorMessage = nil
        Task {
            do {
                try await onSend(trimmedBody, environment)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSending = false
            }
        }
    }
}
