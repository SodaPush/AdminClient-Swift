import SwiftUI

struct UserManagementView: View {
    @EnvironmentObject private var store: AppStore
    @State private var state: CollectionLoadState<[AuthUser]> = .idle
    @State private var showingCreate = false

    var body: some View {
        NavigationStack {
            Group {
                switch state {
                case .idle, .loading:
                    ProgressView("Loading users…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case let .loaded(users) where users.isEmpty:
                    ContentUnavailableView("No Users", systemImage: "person.2.slash")
                case let .loaded(users):
                    List(users) { user in UserRow(user: user, update: updateUser) }
                        .refreshable { await load() }
                case let .failed(message):
                    ContentUnavailableView {
                        Label("Could Not Load Users", systemImage: "person.crop.circle.badge.exclamationmark")
                    } description: { Text(message) } actions: {
                        Button("Try Again") { Task { await load() } }
                    }
                }
            }
            .navigationTitle("Users")
            .toolbar {
                Button { showingCreate = true } label: { Label("New User", systemImage: "person.badge.plus") }
            }
            .sheet(isPresented: $showingCreate) { CreateUserView { await load() } }
            .task { if case .idle = state { await load() } }
        }
    }

    private func load() async {
        state = .loading
        do { state = .loaded(try await store.users()) }
        catch is CancellationError { return }
        catch { state = .failed(error.localizedDescription) }
    }

    private func updateUser(_ user: AuthUser, role: AppRole?, disabled: Bool?) {
        Task {
            do {
                let updated = try await store.updateUser(id: user.id, request: UpdateUserRequest(role: role, disabled: disabled))
                if case var .loaded(users) = state, let index = users.firstIndex(where: { $0.id == updated.id }) {
                    users[index] = updated
                    state = .loaded(users)
                }
            } catch { state = .failed(error.localizedDescription) }
        }
    }
}

private struct UserRow: View {
    let user: AuthUser
    let update: (AuthUser, AppRole?, Bool?) -> Void
    @State private var copied = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.fill")
                .font(.title2)
                .foregroundStyle(user.disabledAt == nil ? user.role.tint : .secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(user.username).font(.headline)
                HStack(spacing: 4) {
                    Text(user.id).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                    Button {
                        SodaClipboard.copy(user.id)
                        copied = true
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(copied ? .green : .secondary)
                    .accessibilityLabel(copied ? "User ID copied" : "Copy user ID")
                }
                Text("Created \(SodaDate.formatted(user.createdAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                ForEach(AppRole.allCases) { role in
                    Button(role.title) { update(user, role, nil) }
                }
            } label: {
                StatusBadge(text: user.role.title, tint: user.role.tint)
            }
            Menu {
                Button(user.disabledAt == nil ? "Disable" : "Enable", role: user.disabledAt == nil ? .destructive : nil) {
                    update(user, nil, user.disabledAt == nil)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("More actions for \(user.username)")
        }
        .padding(.vertical, 5)
    }
}

private struct CreateUserView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    let onCreated: () async -> Void

    @State private var username = ""
    @State private var password = ""
    @State private var role: AppRole = .viewer
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    TextField("Username", text: $username).autocorrectionDisabled()
                    SecureField("Password (12+ characters)", text: $password)
                    Picker("Role", selection: $role) {
                        ForEach(AppRole.allCases) { Text($0.title).tag($0) }
                    }
                }
                if let errorMessage { Section { InlineErrorView(message: errorMessage) } }
            }
            .formStyle(.grouped)
            .navigationTitle("New User")
            .interactiveDismissDisabled(isCreating)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: dismiss.callAsFunction).disabled(isCreating) }
                ToolbarItem(placement: .confirmationAction) { Button("Create", action: create).disabled(!canCreate || isCreating) }
            }
        }
    }

    private var canCreate: Bool {
        username.range(of: #"^[A-Za-z0-9_.-]{3,64}$"#, options: .regularExpression) != nil && password.count >= 12
    }

    private func create() {
        Task {
            isCreating = true
            errorMessage = nil
            defer { isCreating = false }
            do {
                _ = try await store.createUser(CreateUserRequest(username: username, password: password, role: role))
                password = ""
                await onCreated()
                dismiss()
            } catch { errorMessage = error.localizedDescription }
        }
    }
}
