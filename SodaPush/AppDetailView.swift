import SwiftUI

private enum AppDetailSection: String, CaseIterable, Identifiable {
    case overview, devices, pushes, credentials, access
    var id: Self { self }
    var title: String { rawValue.capitalized }
    var systemImage: String {
        switch self {
        case .overview: "rectangle.3.group"
        case .devices: "iphone"
        case .pushes: "paperplane"
        case .credentials: "key"
        case .access: "person.2"
        }
    }
}

struct AppDetailView: View {
    @EnvironmentObject private var store: AppStore
    @State private var currentApp: AppSummary
    @State private var section: AppDetailSection = .overview
    @State private var errorMessage: String?

    init(app: AppSummary) {
        _currentApp = State(initialValue: app)
    }

    var body: some View {
        VStack(spacing: 0) {
            AppHeader(app: currentApp)
            SectionPicker(selection: $section, app: currentApp)
            Divider()
            sectionContent
        }
        .navigationTitle(currentApp.name)
        .task(id: currentApp.id) { await refreshApp() }
        .alert("Could Not Complete Action", isPresented: errorPresented) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch section {
        case .overview:
            AppOverviewSection(app: currentApp, onUpdated: { currentApp = $0 })
        case .devices:
            DevicesView(app: currentApp)
        case .pushes:
            PushesView(app: currentApp)
        case .credentials:
            CredentialsView(app: currentApp)
        case .access:
            AppMembersView(app: currentApp)
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func refreshApp() async {
        do { currentApp = try await store.app(id: currentApp.id) }
        catch is CancellationError { return }
        catch { errorMessage = error.localizedDescription }
    }
}

private struct AppHeader: View {
    let app: AppSummary

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "app.badge.fill")
                .font(.system(size: 28))
                .foregroundStyle(.tint)
                .frame(width: 52, height: 52)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 4) {
                Text(app.name).font(.title2.bold())
                Text(app.bundleID).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Spacer()
            StatusBadge(text: app.disabledAt == nil ? "Active" : "Disabled", tint: app.disabledAt == nil ? .green : .red)
            StatusBadge(text: app.role.title, tint: app.role.tint)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }
}

private struct SectionPicker: View {
    @Binding var selection: AppDetailSection
    let app: AppSummary

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(visibleSections) { item in
                    Button {
                        withAnimation(.snappy) { selection = item }
                    } label: {
                        Label(item.title, systemImage: item.systemImage)
                            .font(.subheadline.weight(selection == item ? .semibold : .regular))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(selection == item ? Color.accentColor.opacity(0.14) : Color.clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selection == item ? Color.accentColor : .secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
    }

    private var visibleSections: [AppDetailSection] {
        AppDetailSection.allCases.filter { item in
            item != .credentials || app.role.canManageCredentials
        }
    }
}

private struct AppOverviewSection: View {
    @EnvironmentObject private var store: AppStore
    let app: AppSummary
    let onUpdated: (AppSummary) -> Void

    @State private var name: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(app: AppSummary, onUpdated: @escaping (AppSummary) -> Void) {
        self.app = app
        self.onUpdated = onUpdated
        _name = State(initialValue: app.name)
    }

    var body: some View {
        Form {
            Section("Identity") {
                if app.role.canManageApps {
                    TextField("Name", text: $name)
                    Button("Save Name", action: saveName)
                        .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name == app.name)
                } else {
                    LabeledContent("Name", value: app.name)
                }
                LabeledContent("Bundle ID", value: app.bundleID)
                LabeledContent("Created", value: SodaDate.formatted(app.createdAt))
                LabeledContent("Your Role") { StatusBadge(text: app.role.title, tint: app.role.tint) }
            }

            if app.role.canManageApps {
                Section("Availability") {
                    Text(app.disabledAt == nil ? "Disabling prevents new push jobs from being delivered." : "Re-enable this app to resume delivery.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(app.disabledAt == nil ? "Disable Application" : "Enable Application", role: app.disabledAt == nil ? .destructive : nil, action: toggleDisabled)
                        .disabled(isSaving)
                }
            }

            if let errorMessage { Section { InlineErrorView(message: errorMessage) } }
        }
        .formStyle(.grouped)
    }

    private func saveName() { update(UpdateAppRequest(name: name.trimmingCharacters(in: .whitespacesAndNewlines))) }
    private func toggleDisabled() { update(UpdateAppRequest(disabled: app.disabledAt == nil)) }

    private func update(_ request: UpdateAppRequest) {
        Task {
            isSaving = true
            errorMessage = nil
            defer { isSaving = false }
            do { onUpdated(try await store.updateApp(id: app.id, request: request)) }
            catch { errorMessage = error.localizedDescription }
        }
    }
}
