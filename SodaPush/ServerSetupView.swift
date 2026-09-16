import SwiftUI

struct ServerSetupView: View {
    @EnvironmentObject private var store: AppStore

    @State private var serverURL = "https://"
    @State private var snapshot: ServerConnectionSnapshot?
    @State private var username = ""
    @State private var password = ""
    @State private var passwordConfirmation = ""
    @State private var bootstrapToken = ""
    @State private var isChecking = false
    @State private var localError: String?

    private var isBootstrap: Bool { snapshot?.bootstrap.initialized == false }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                WelcomeHeader()
                connectionCard
                if snapshot != nil { authenticationCard }
                Text("You need to deploy the SodaPush backend server yourself on Cloudflare Workers or your self-hosted server. For more informations, please [check out on GitHub](https://github.com/SodaPush)")
                savedServers
            }
            .frame(maxWidth: 560)
            .padding(.horizontal, 24)
            .padding(.vertical, 48)
            .frame(maxWidth: .infinity)
        }
        .background {
            LinearGradient(colors: [Color.accentColor.opacity(0.12), Color.clear], startPoint: .topLeading, endPoint: .center)
                .ignoresSafeArea()
        }
        .task {
            if serverURL == "https://" { serverURL = store.suggestedServerURL }
        }
    }

    private var connectionCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                TextField("https://push.example.com", text: $serverURL)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .disabled(snapshot != nil || isChecking || store.isSigningIn)
                    .accessibilityLabel("Server URL")

                if let snapshot {
                    HStack {
                        Label(snapshot.profile.baseURL.host ?? snapshot.profile.name, systemImage: "network")
                        Spacer()
                        StatusBadge(text: snapshot.readiness.status, tint: StatusBadge.color(for: snapshot.readiness.status))
                        Text("v\(snapshot.health.version)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }

                if snapshot == nil {
                    Button(action: checkServer) {
                        HStack {
                            if isChecking { ProgressView().controlSize(.small) }
                            Text(isChecking ? "Checking…" : "Continue")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isChecking || serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } else {
                    Button("Use a different server", action: resetConnection)
                        .font(.callout)
                }

                if let errorMessage { InlineErrorView(message: errorMessage) }
            }
            .padding(8)
        } label: {
            Label("Server", systemImage: "server.rack")
        }
    }

    private var authenticationCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                if isBootstrap {
                    Label("This server is ready for its first owner account.", systemImage: "sparkles")
                        .foregroundStyle(.secondary)
                    SecureField("Bootstrap token", text: $bootstrapToken)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Bootstrap token")
                }

                TextField("Username", text: $username)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)

                if isBootstrap {
                    SecureField("Confirm password", text: $passwordConfirmation)
                        .textFieldStyle(.roundedBorder)
                    Text("Use at least 12 characters. The bootstrap token is never saved.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button(action: authenticate) {
                    HStack {
                        if store.isSigningIn { ProgressView().controlSize(.small) }
                        Text(store.isSigningIn ? "Working…" : isBootstrap ? "Create Owner & Continue" : "Sign In")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(store.isSigningIn || !canAuthenticate)
            }
            .padding(8)
        } label: {
            Label(isBootstrap ? "Initialize Server" : "Account", systemImage: isBootstrap ? "person.badge.key.fill" : "person.crop.circle")
        }
    }

    @ViewBuilder
    private var savedServers: some View {
        if !store.profiles.isEmpty && snapshot == nil {
            VStack(alignment: .leading, spacing: 8) {
                Text("RECENT SERVERS")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(store.profiles) { profile in
                    Button {
                        serverURL = profile.baseURL.absoluteString
                        checkServer()
                    } label: {
                        HStack {
                            Image(systemName: "clock.arrow.circlepath")
                            VStack(alignment: .leading) {
                                Text(profile.name)
                                Text(profile.baseURL.absoluteString)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(12)
                    .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private var errorMessage: String? { localError ?? store.sessionError }

    private var canAuthenticate: Bool {
        let basics = !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
        guard isBootstrap else { return basics }
        return basics && password.count >= 12 && password == passwordConfirmation && !bootstrapToken.isEmpty
    }

    private func checkServer() { Task { await inspectServer() } }

    private func inspectServer() async {
        isChecking = true
        localError = nil
        store.sessionError = nil
        defer { isChecking = false }
        do {
            let result = try await store.inspectServer(serverURL: serverURL)
            guard result.readiness.status == "ready" else {
                localError = "The server responded but is not ready. Check its database and MASTER_KEY configuration."
                return
            }
            snapshot = result
        } catch is CancellationError {
            return
        } catch {
            localError = error.localizedDescription
        }
    }

    private func authenticate() {
        Task {
            localError = nil
            let cleanUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
            if isBootstrap {
                do {
                    _ = try await store.bootstrap(serverURL: serverURL, token: bootstrapToken, username: cleanUsername, password: password)
                    bootstrapToken = ""
                    password = ""
                    passwordConfirmation = ""
                } catch { localError = error.localizedDescription }
            } else {
                await store.login(serverURL: serverURL, username: cleanUsername, password: password)
            }
        }
    }

    private func resetConnection() {
        snapshot = nil
        localError = nil
        username = ""
        password = ""
        passwordConfirmation = ""
        bootstrapToken = ""
    }
}

private struct WelcomeHeader: View {
    var body: some View {
        VStack(spacing: 12) {
            SodaBrandIcon(size: 92)
                .accessibilityHidden(true)
            Text("SodaPush")
                .font(.largeTitle.bold())
            Text("Connect to the SodaPush APNs backend server. Your credentials, devices, and delivery history stay under your control.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}
