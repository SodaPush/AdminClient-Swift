import SwiftUI

struct AppMembersView: View {
    @EnvironmentObject private var store: AppStore
    let app: AppSummary

    @State private var state: CollectionLoadState<[AppMember]> = .idle
    @State private var showingAddMember = false
    @State private var pendingRemoval: AppMember?

    var body: some View {
        Group {
            switch state {
            case .idle, .loading:
                ProgressView("Loading members…").frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .loaded(members) where members.isEmpty:
                ContentUnavailableView("No Members", systemImage: "person.2.slash")
            case let .loaded(members):
                List(members) { member in
                    MemberRow(member: member, canManage: app.role.canManageMembers, updateRole: { update(member, role: $0) }, remove: { pendingRemoval = member })
                }
                .refreshable { await load() }
            case let .failed(message):
                ContentUnavailableView {
                    Label("Could Not Load Members", systemImage: "person.2.slash")
                } description: { Text(message) } actions: {
                    Button("Try Again") { Task { await load() } }
                }
            }
        }
        .toolbar {
            if app.role.canManageMembers {
                Button { showingAddMember = true } label: { Label("Add Member", systemImage: "person.badge.plus") }
            }
        }
        .sheet(isPresented: $showingAddMember) { AddMemberView(app: app) { await load() } }
        .alert("Remove App Member?", isPresented: removalPresented, presenting: pendingRemoval) { member in
            Button("Remove", role: .destructive) { remove(member) }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: { member in
            Text("\(member.username) will no longer be able to access \(app.name).")
        }
        .task(id: app.id) { await load() }
    }

    private var removalPresented: Binding<Bool> {
        Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })
    }

    private func load() async {
        if case .loaded = state {} else { state = .loading }
        do { state = .loaded(try await store.appMembers(appID: app.id)) }
        catch is CancellationError { return }
        catch { state = .failed(error.localizedDescription) }
    }

    private func update(_ member: AppMember, role: AppRole) {
        Task {
            do {
                let updated = try await store.putAppMember(appID: app.id, userID: member.userID, role: role)
                if case var .loaded(members) = state, let index = members.firstIndex(where: { $0.id == updated.id }) {
                    members[index] = updated
                    state = .loaded(members)
                }
            } catch { state = .failed(error.localizedDescription) }
        }
    }

    private func remove(_ member: AppMember) {
        Task {
            do {
                try await store.deleteAppMember(appID: app.id, userID: member.userID)
                if case var .loaded(members) = state {
                    members.removeAll { $0.id == member.id }
                    state = .loaded(members)
                }
            } catch { state = .failed(error.localizedDescription) }
        }
    }
}

private struct MemberRow: View {
    let member: AppMember
    let canManage: Bool
    let updateRole: (AppRole) -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.fill").font(.title2).foregroundStyle(member.role.tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(member.username).font(.headline)
                Text(member.userID).font(.caption2.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Spacer()
            if canManage && member.role != .owner {
                Menu {
                    ForEach([AppRole.admin, .developer, .viewer]) { role in
                        Button(role.title) { updateRole(role) }
                    }
                    Divider()
                    Button("Remove", role: .destructive, action: remove)
                } label: { StatusBadge(text: member.role.title, tint: member.role.tint) }
            } else {
                StatusBadge(text: member.role.title, tint: member.role.tint)
            }
        }
        .padding(.vertical, 5)
    }
}

private struct AddMemberView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    let app: AppSummary
    let onAdded: () async -> Void

    @State private var userID = ""
    @State private var role: AppRole = .viewer
    @State private var isAdding = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Member") {
                    TextField("User ID", text: $userID).font(.body.monospaced()).autocorrectionDisabled()
                    Picker("App Role", selection: $role) {
                        ForEach([AppRole.admin, .developer, .viewer]) { Text($0.title).tag($0) }
                    }
                }
                Section {
                    Text("Create users from the Users screen, then copy their ID here. Owners already have access to every app.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let errorMessage { Section { InlineErrorView(message: errorMessage) } }
            }
            .formStyle(.grouped)
            .navigationTitle("Add App Member")
            .interactiveDismissDisabled(isAdding)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: dismiss.callAsFunction).disabled(isAdding) }
                ToolbarItem(placement: .confirmationAction) { Button("Add", action: add).disabled(userID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAdding) }
            }
        }
        .sodaSheetFrame()
    }

    private func add() {
        Task {
            isAdding = true
            errorMessage = nil
            defer { isAdding = false }
            do {
                _ = try await store.putAppMember(appID: app.id, userID: userID.trimmingCharacters(in: .whitespacesAndNewlines), role: role)
                await onAdded()
                dismiss()
            } catch { errorMessage = error.localizedDescription }
        }
    }
}
