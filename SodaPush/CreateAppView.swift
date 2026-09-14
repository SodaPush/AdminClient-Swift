import SwiftUI

struct CreateAppView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore

    @State private var name = ""
    @State private var bundleID = ""
    @State private var createdApp: AppSummary?
    @State private var registrationKey: RegistrationKey?
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var copied = false

    var body: some View {
        NavigationStack {
            Form {
                if let registrationKey {
                    Section("Application Created") {
                        Label("Save this registration key now. The secret cannot be shown again.", systemImage: "key.fill")
                            .foregroundStyle(.orange)
                        if let createdApp {
                            LabeledContent("Application ID", value: createdApp.id)
                                .textSelection(.enabled)
                            LabeledContent("Bundle ID", value: createdApp.bundleID)
                        }
                        LabeledContent("Key ID", value: registrationKey.keyID)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Secret").font(.caption).foregroundStyle(.secondary)
                            Text(registrationKey.secret ?? "")
                                .font(.body.monospaced())
                                .textSelection(.enabled)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        }
                        Button(copied ? "Copied" : "Copy Key and Secret", systemImage: copied ? "checkmark" : "doc.on.doc") {
                            SodaClipboard.copy("SODAPUSH_APP_ID=\(createdApp?.id ?? "")\nSODAPUSH_KEY_ID=\(registrationKey.keyID)\nSODAPUSH_SECRET=\(registrationKey.secret ?? "")")
                            copied = true
                        }
                    }
                } else {
                    Section("Application") {
                        TextField("Name", text: $name)
                        TextField("Bundle ID", text: $bundleID)
                            .font(.body.monospaced())
                            .autocorrectionDisabled()
                    }
                    Section {
                        Text("The server creates an SDK registration key together with the application.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let errorMessage { Section { InlineErrorView(message: errorMessage) } }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(registrationKey == nil ? "New Application" : "Save Registration Key")
            .interactiveDismissDisabled(isCreating || (registrationKey != nil && !copied))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(registrationKey == nil ? "Cancel" : "Done") { dismiss() }
                        .disabled(isCreating || (registrationKey != nil && !copied))
                }
                if registrationKey == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create", action: create)
                            .disabled(!canCreate || isCreating)
                    }
                }
            }
        }
        .sodaSheetFrame()
    }

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && bundleID.range(of: #"^[A-Za-z0-9]+(?:[.-][A-Za-z0-9]+)+$"#, options: .regularExpression) != nil
    }

    private func create() {
        Task {
            isCreating = true
            errorMessage = nil
            defer { isCreating = false }
            do {
                let response = try await store.createApp(name: name.trimmingCharacters(in: .whitespacesAndNewlines), bundleID: bundleID)
                createdApp = response.app
                registrationKey = response.registrationKey
            } catch { errorMessage = error.localizedDescription }
        }
    }
}
