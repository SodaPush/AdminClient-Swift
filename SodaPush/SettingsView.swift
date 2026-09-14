import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var errorMessage: String?
    @State private var pendingRemoval: ServerProfile?
    @State private var editingUser: AuthUser?

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    if let user = store.currentUser {
                        LabeledContent("Username", value: user.username)
                        LabeledContent("Role") { StatusBadge(text: user.role.title, tint: user.role.tint) }
                        Button("Edit Username or Password", systemImage: "person.crop.circle.badge.checkmark") {
                            editingUser = user
                        }
                    }
                    Button("Sign Out", role: .destructive, action: store.logout)
                }

                Section("Current Server") {
                    LabeledContent("Name", value: store.activeProfile?.name ?? "—")
                    LabeledContent("URL", value: store.activeProfile?.baseURL.absoluteString ?? "—")
                }

                if !store.profiles.isEmpty {
                    Section("Saved Servers") {
                        ForEach(store.profiles) { profile in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(profile.name)
                                    Text(profile.baseURL.absoluteString)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if store.activeProfile?.id == profile.id {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                } else {
                                    Button("Switch") { Task { await store.selectProfile(profile) } }
                                        .buttonStyle(.bordered)
                                }
                                Button("Remove", role: .destructive) { pendingRemoval = profile }
                                    .buttonStyle(.borderless)
                            }
                        }
                    }
                }

                Section("About") {
                    LabeledContent("Client", value: "SodaPush 1.0")
                    Text("A native management console for your self-hosted SodaPush service.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage { Section { InlineErrorView(message: errorMessage) } }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
        }
        .alert("Remove Saved Server?", isPresented: removalPresented, presenting: pendingRemoval) { profile in
            Button("Remove", role: .destructive) { remove(profile) }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: { profile in
            Text("The saved connection and its local session token for \(profile.name) will be removed.")
        }
        .sheet(item: $editingUser) { user in
            EditUserView(user: user, requiresCurrentPassword: user.role != .owner) { _ in }
        }
    }

    private var removalPresented: Binding<Bool> {
        Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })
    }

    private func remove(_ profile: ServerProfile) {
        pendingRemoval = nil
        do { try store.removeProfile(profile) }
        catch { errorMessage = error.localizedDescription }
    }
}
