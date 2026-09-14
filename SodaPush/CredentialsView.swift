import SwiftUI
import UniformTypeIdentifiers

private struct CredentialBundle: Equatable {
    let credentials: [APNsCredential]
    let registrationKeys: [RegistrationKey]
}

struct CredentialsView: View {
    @EnvironmentObject private var store: AppStore
    let app: AppSummary

    @State private var state: CollectionLoadState<CredentialBundle> = .idle
    @State private var showingAPNsUpload = false
    @State private var revealedKey: RegistrationKey?
    @State private var isCreatingKey = false
    @State private var pendingCredential: APNsCredential?
    @State private var pendingKey: RegistrationKey?

    var body: some View {
        Group {
            switch state {
            case .idle, .loading:
                ProgressView("Loading credentials…").frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .loaded(bundle):
                List {
                    if app.role.canManageCredentials {
                        Section {
                            Button {
                                showingAPNsUpload = true
                            } label: {
                                Label("Add APNs Signing Key (.p8)", systemImage: "key.horizontal.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        }
                    }
                    Section {
                        if bundle.credentials.isEmpty {
                            Label("No APNs credential configured", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        } else {
                            ForEach(bundle.credentials) { credential in
                                APNsCredentialRow(
                                    credential: credential,
                                    canManage: app.role.canManageCredentials,
                                    makeDefault: { makeDefault(credential) },
                                    delete: { pendingCredential = credential }
                                )
                            }
                        }
                    } header: {
                        Text("APNs Credentials")
                    } footer: {
                        Text("Each environment has a default credential, and a different key can be selected for an individual push. Private key material is never returned by the server.")
                    }

                    Section {
                        if bundle.registrationKeys.isEmpty {
                            Text("No registration keys")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(bundle.registrationKeys) { key in
                                RegistrationKeyRow(key: key, canManage: app.role.canManageRegistrationKeys) {
                                    pendingKey = key
                                }
                            }
                        }
                    } header: {
                        Text("SDK Registration Keys")
                    } footer: {
                        Text("Applications use these keys to sign device registration requests.")
                    }
                }
                .refreshable { await load() }
            case let .failed(message):
                ContentUnavailableView {
                    Label("Could Not Load Credentials", systemImage: "key.slash")
                } description: { Text(message) } actions: {
                    Button("Try Again") { Task { await load() } }
                }
            }
        }
        .toolbar {
            if app.role.canManageCredentials {
                Button(action: createKey) {
                    Label(isCreatingKey ? "Creating…" : "New Registration Key", systemImage: "key.badge.plus")
                }
                .disabled(isCreatingKey)
            }
        }
        .sheet(isPresented: $showingAPNsUpload) {
            APNsUploadView(app: app) { await load() }
        }
        .sheet(item: $revealedKey) { key in RegistrationSecretView(appID: app.id, key: key) }
        .alert("Delete APNs Credential?", isPresented: credentialRemovalPresented, presenting: pendingCredential) { credential in
            Button("Delete", role: .destructive) { deleteCredential(credential) }
            Button("Cancel", role: .cancel) { pendingCredential = nil }
        } message: { credential in
            Text("The credential with key ID \(credential.keyID) will be removed from this app.")
        }
        .alert("Revoke Registration Key?", isPresented: keyRevocationPresented, presenting: pendingKey) { key in
            Button("Revoke", role: .destructive) { revokeKey(key) }
            Button("Cancel", role: .cancel) { pendingKey = nil }
        } message: { key in
            Text("Devices using \(key.keyID) will no longer be able to register.")
        }
        .task(id: app.id) { await load() }
    }

    private var credentialRemovalPresented: Binding<Bool> {
        Binding(get: { pendingCredential != nil }, set: { if !$0 { pendingCredential = nil } })
    }

    private var keyRevocationPresented: Binding<Bool> {
        Binding(get: { pendingKey != nil }, set: { if !$0 { pendingKey = nil } })
    }

    private func load() async {
        if case .loaded = state {} else { state = .loading }
        do {
            async let credentials = store.apnsCredentials(appID: app.id)
            async let keys = store.registrationKeys(appID: app.id)
            state = .loaded(try await CredentialBundle(credentials: credentials, registrationKeys: keys))
        } catch is CancellationError { return }
        catch { state = .failed(error.localizedDescription) }
    }

    private func createKey() {
        Task {
            isCreatingKey = true
            defer { isCreatingKey = false }
            do {
                revealedKey = try await store.createRegistrationKey(appID: app.id)
                await load()
            } catch { state = .failed(error.localizedDescription) }
        }
    }

    private func deleteCredential(_ credential: APNsCredential) {
        pendingCredential = nil
        Task {
            do {
                try await store.deleteAPNsCredential(appID: app.id, credentialID: credential.id)
                await load()
            } catch { state = .failed(error.localizedDescription) }
        }
    }

    private func makeDefault(_ credential: APNsCredential) {
        Task {
            do {
                _ = try await store.setDefaultAPNsCredential(appID: app.id, credentialID: credential.id)
                await load()
            } catch { state = .failed(error.localizedDescription) }
        }
    }

    private func revokeKey(_ key: RegistrationKey) {
        pendingKey = nil
        Task {
            do {
                try await store.deleteRegistrationKey(appID: app.id, keyID: key.keyID)
                await load()
            } catch { state = .failed(error.localizedDescription) }
        }
    }
}

private struct APNsCredentialRow: View {
    let credential: APNsCredential
    let canManage: Bool
    let makeDefault: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.shield.fill").font(.title2).foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 4) {
                Text(credential.keyID).font(.headline.monospaced())
                Text("Team \(credential.teamID) · Updated \(SodaDate.formatted(credential.updatedAt))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            StatusBadge(text: credential.environment.title, tint: StatusBadge.color(for: credential.environment.rawValue))
            if credential.isDefault {
                StatusBadge(text: "Default", tint: .green)
            }
            if canManage {
                Menu {
                    if !credential.isDefault { Button("Make Default", systemImage: "checkmark.circle", action: makeDefault) }
                    Button("Delete", systemImage: "trash", role: .destructive, action: delete)
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton)
            }
        }
        .padding(.vertical, 5)
    }
}

private struct RegistrationKeyRow: View {
    let key: RegistrationKey
    let canManage: Bool
    let revoke: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "key.fill").foregroundStyle(key.active ? .blue : .secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(key.keyID).font(.callout.monospaced()).textSelection(.enabled)
                Text("Created \(SodaDate.formatted(key.createdAt))").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            StatusBadge(text: key.active ? "Active" : "Revoked", tint: key.active ? .green : .red)
            if canManage && key.active {
                Button("Revoke", role: .destructive, action: revoke).buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 5)
    }
}

private struct APNsUploadView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    let app: AppSummary
    let onUploaded: () async -> Void

    @State private var teamID = ""
    @State private var keyID = ""
    @State private var privateKey = ""
    @State private var environment: PushEnvironment = .production
    @State private var makeDefault = true
    @State private var isImporting = false
    @State private var isUploading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Apple Developer Account") {
                    TextField("Team ID", text: $teamID).font(.body.monospaced()).autocorrectionDisabled()
                    TextField("Key ID", text: $keyID).font(.body.monospaced()).autocorrectionDisabled()
                }
                Section("Delivery Environment") {
                    Picker("Environment", selection: $environment) {
                        ForEach(PushEnvironment.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Toggle("Use as the default for this environment", isOn: $makeDefault)
                }
                Section("Private Key (.p8)") {
                    Button("Choose .p8 File", systemImage: "key.horizontal") { isImporting = true }
                    TextEditor(text: $privateKey)
                        .font(.caption.monospaced())
                        .frame(minHeight: 140)
                    Text("The key is uploaded directly and is not saved by this client.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let errorMessage { Section { InlineErrorView(message: errorMessage) } }
            }
            .formStyle(.grouped)
            .navigationTitle("Upload APNs Credential")
            .interactiveDismissDisabled(isUploading)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: dismiss.callAsFunction).disabled(isUploading) }
                ToolbarItem(placement: .confirmationAction) { Button("Upload", action: upload).disabled(!canUpload || isUploading) }
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.data, .plainText]) { result in
                importFile(result)
            }
        }
        .sodaSheetFrame(minHeight: 620)
    }

    private var canUpload: Bool {
        !teamID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !keyID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && privateKey.contains("PRIVATE KEY")
    }

    private func importFile(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            privateKey = try String(contentsOf: url, encoding: .utf8)
        } catch { errorMessage = error.localizedDescription }
    }

    private func upload() {
        Task {
            isUploading = true
            errorMessage = nil
            defer { isUploading = false }
            do {
                _ = try await store.createAPNsCredential(
                    appID: app.id,
                    teamID: teamID.trimmingCharacters(in: .whitespacesAndNewlines),
                    keyID: keyID.trimmingCharacters(in: .whitespacesAndNewlines),
                    p8: privateKey,
                    environment: environment,
                    makeDefault: makeDefault
                )
                privateKey = ""
                await onUploaded()
                dismiss()
            } catch { errorMessage = error.localizedDescription }
        }
    }
}

private struct RegistrationSecretView: View {
    @Environment(\.dismiss) private var dismiss
    let appID: String
    let key: RegistrationKey
    @State private var copied = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("This secret is shown once. Copy it into the SDK configuration before closing.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                Section("Key ID") { Text(key.keyID).font(.body.monospaced()).textSelection(.enabled) }
                Section("Secret") { Text(key.secret ?? "").font(.body.monospaced()).textSelection(.enabled) }
                Button(copied ? "Copied" : "Copy Key and Secret", systemImage: copied ? "checkmark" : "doc.on.doc") {
                    SodaClipboard.copy("SODAPUSH_APP_ID=\(appID)\nSODAPUSH_KEY_ID=\(key.keyID)\nSODAPUSH_SECRET=\(key.secret ?? "")")
                    copied = true
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Save Registration Key")
            .interactiveDismissDisabled(!copied)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", action: dismiss.callAsFunction).disabled(!copied) } }
        }
        .sodaSheetFrame()
    }
}
