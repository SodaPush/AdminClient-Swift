import SwiftUI

struct UserManagementView: View {
    @EnvironmentObject private var store: AppStore
    @State private var state: CollectionLoadState<[AuthUser]> = .idle
    @State private var showingCreate = false
    @State private var selectedUser: AuthUser?

    var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    ProgressView("Loading users…")
                } else if case let .loaded(users) = state, users.isEmpty {
                    ContentUnavailableView("No Users", systemImage: "person.2.slash")
                } else if case let .loaded(users) = state {
                    ForEach(users) { user in
                        UserRow(user: user, edit: { selectedUser = user }, update: updateUser)
                    }
                } else if case let .failed(message) = state {
                    ContentUnavailableView {
                        Label("Could Not Load Users", systemImage: "person.crop.circle.badge.exclamationmark")
                    } description: { Text(message) } actions: {
                        Button("Try Again") { Task { await load() } }
                    }
                }
            }
            .refreshable { await load() }
            .navigationTitle("Users")
            .toolbar {
                Button { showingCreate = true } label: { Label("New User", systemImage: "person.badge.plus") }
            }
            .sheet(isPresented: $showingCreate) { CreateUserView { await load() } }
            .sheet(item: $selectedUser) { user in
                EditUserView(user: user, onUpdated: replaceUser)
            }
            .task { if case .idle = state { await load() } }
        }
    }

    private func load() async {
        if case .loaded = state {} else { state = .loading }
        do { state = .loaded(try await store.users()) }
        catch is CancellationError { return }
        catch { state = .failed(error.localizedDescription) }
    }

    private var isLoading: Bool {
        if case .idle = state { return true }
        if case .loading = state { return true }
        return false
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

    private func replaceUser(_ updated: AuthUser) {
        guard case var .loaded(users) = state, let index = users.firstIndex(where: { $0.id == updated.id }) else { return }
        users[index] = updated
        state = .loaded(users)
    }
}

private struct UserRow: View {
    let user: AuthUser
    let edit: () -> Void
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
            Button("Edit user", systemImage: "pencil", action: edit)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            if user.role == .owner {
                StatusBadge(text: user.role.title, tint: user.role.tint)
            } else {
                Menu {
                    ForEach([AppRole.admin, .developer, .viewer]) { role in
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
        }
        .padding(.vertical, 5)
    }
}

struct EditUserView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore

    let user: AuthUser
    let requiresCurrentPassword: Bool
    let onUpdated: (AuthUser) -> Void

    @State private var username: String
    @State private var currentPassword = ""
    @State private var password = ""
    @State private var passwordConfirmation = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(user: AuthUser, requiresCurrentPassword: Bool = false, onUpdated: @escaping (AuthUser) -> Void) {
        self.user = user
        self.requiresCurrentPassword = requiresCurrentPassword
        self.onUpdated = onUpdated
        _username = State(initialValue: user.username)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    TextField("Username", text: $username)
                        .autocorrectionDisabled()
                    LabeledContent("Role", value: user.role.title)
                }
                Section("Change Password") {
                    if requiresCurrentPassword {
                        SecureField("Current password", text: $currentPassword)
                    }
                    SecureField("New password (12+ characters)", text: $password)
                    SecureField("Confirm new password", text: $passwordConfirmation)
                    Text("Leave both password fields empty to keep the current password.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let errorMessage { Section { InlineErrorView(message: errorMessage) } }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit User")
            .interactiveDismissDisabled(isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: dismiss.callAsFunction).disabled(isSaving) }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(!canSave || isSaving) }
            }
        }
        .sodaSheetFrame()
    }

    private var normalizedUsername: String { username.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSave: Bool {
        let validUsername = normalizedUsername.range(of: #"^[A-Za-z0-9_.-]{3,64}$"#, options: .regularExpression) != nil
        let passwordUnchanged = password.isEmpty && passwordConfirmation.isEmpty
        let validNewPassword = password.count >= 12 && password == passwordConfirmation && (!requiresCurrentPassword || !currentPassword.isEmpty)
        return validUsername && (normalizedUsername != user.username || !passwordUnchanged) && (passwordUnchanged || validNewPassword)
    }

    private func save() {
        Task {
            isSaving = true
            errorMessage = nil
            defer { isSaving = false }
            do {
                let updated = try await store.updateUser(
                    id: user.id,
                    request: UpdateUserRequest(
                        username: normalizedUsername == user.username ? nil : normalizedUsername,
                        password: password.isEmpty ? nil : password,
                        currentPassword: password.isEmpty || !requiresCurrentPassword ? nil : currentPassword
                    )
                )
                password = ""
                passwordConfirmation = ""
                currentPassword = ""
                onUpdated(updated)
                dismiss()
            } catch { errorMessage = error.localizedDescription }
        }
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
                        ForEach([AppRole.admin, .developer, .viewer]) { Text($0.title).tag($0) }
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
        .sodaSheetFrame()
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
