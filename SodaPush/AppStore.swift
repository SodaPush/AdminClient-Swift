import Combine
import Foundation

enum SessionState: Equatable {
    case restoring
    case signedOut
    case authenticated(AuthUser)
}

enum CollectionLoadState<Value: Equatable>: Equatable {
    case idle
    case loading
    case loaded(Value)
    case failed(String)
}

enum AppStoreError: Error, LocalizedError {
    case notAuthenticated
    case staleOperation

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: String(localized: "Sign in before making this request.")
        case .staleOperation: String(localized: "The operation was superseded by a newer session.")
        }
    }
}

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var profiles: [ServerProfile] = []
    @Published private(set) var sessionState: SessionState = .restoring
    @Published private(set) var appsState: CollectionLoadState<[AppSummary]> = .idle
    @Published private(set) var isSigningIn = false
    @Published var sessionError: String?

    private var selectedProfile: ServerProfile?
    private var client: APIClient?
    private var sessionGeneration: UInt = 0
    private var appsReloadGeneration: UInt = 0

    var currentUser: AuthUser? {
        guard case let .authenticated(user) = sessionState else { return nil }
        return user
    }

    var activeProfile: ServerProfile? { selectedProfile }

    var suggestedServerURL: String {
        selectedProfile?.baseURL.absoluteString ?? profiles.first?.baseURL.absoluteString ?? "https://"
    }

    func inspectServer(serverURL: String) async throws -> ServerConnectionSnapshot {
        let baseURL = try APIClient.normalizedBaseURL(from: serverURL)
        let profile = profile(for: baseURL)
        let api = APIClient(profile: profile)
        let health = try await api.health()
        let readiness = try await api.readiness()
        let bootstrap = try await api.bootstrapStatus()
        return ServerConnectionSnapshot(profile: profile, health: health, readiness: readiness, bootstrap: bootstrap)
    }

    func restoreSession() async {
        guard sessionState == .restoring else { return }
        profiles = loadAndNormalizeProfiles()
        let lastProfileID = UserDefaults.standard.string(forKey: StorageKey.lastProfileID)
        guard let profile = profiles.first(where: { $0.id.uuidString == lastProfileID }) ?? profiles.first else {
            sessionState = .signedOut
            return
        }
        selectedProfile = profile
        let generation = beginSessionOperation()

        do {
            guard let token = try KeychainStore.get(account: profile.id.uuidString) else {
                guard generation == sessionGeneration else { return }
                sessionState = .signedOut
                return
            }
            let api = APIClient(profile: profile, accessToken: token)
            let user = try await api.currentUser()
            guard generation == sessionGeneration else { return }
            client = api
            sessionState = .authenticated(user)
            await reloadApps()
        } catch APIError.unauthorized {
            guard generation == sessionGeneration else { return }
            clearAuthentication(for: profile)
            sessionError = APIError.unauthorized.localizedDescription
        } catch is CancellationError {
            return
        } catch {
            guard generation == sessionGeneration else { return }
            client = nil
            sessionState = .signedOut
            sessionError = error.localizedDescription
        }
    }

    func login(serverURL: String, username: String, password: String) async {
        sessionError = nil
        isSigningIn = true
        let generation = beginSessionOperation()
        defer { if generation == sessionGeneration { isSigningIn = false } }

        do {
            let baseURL = try APIClient.normalizedBaseURL(from: serverURL)
            let profile = profile(for: baseURL)
            let api = APIClient(profile: profile)
            let response = try await api.login(username: username, password: password)
            guard generation == sessionGeneration else { return }
            try establishSession(response, profile: profile, client: api)
            await reloadApps()
        } catch is CancellationError {
            return
        } catch {
            guard generation == sessionGeneration else { return }
            sessionState = .signedOut
            sessionError = error.localizedDescription
        }
    }

    @discardableResult
    func bootstrap(serverURL: String, token: String, username: String, password: String) async throws -> AuthUser {
        sessionError = nil
        isSigningIn = true
        let generation = beginSessionOperation()
        defer { if generation == sessionGeneration { isSigningIn = false } }

        do {
            let baseURL = try APIClient.normalizedBaseURL(from: serverURL)
            let profile = profile(for: baseURL)
            let api = APIClient(profile: profile)
            let response = try await api.bootstrap(token: token, username: username, password: password)
            guard generation == sessionGeneration else { throw AppStoreError.staleOperation }
            try establishSession(response, profile: profile, client: api)
            await reloadApps()
            return response.user
        } catch {
            if generation == sessionGeneration {
                sessionState = .signedOut
                sessionError = error.localizedDescription
            }
            throw error
        }
    }

    func reloadApps() async {
        guard let client else { appsState = .idle; return }
        let session = sessionGeneration
        appsReloadGeneration &+= 1
        let reload = appsReloadGeneration
        appsState = .loading
        do {
            let apps = try await client.apps()
            guard session == sessionGeneration, reload == appsReloadGeneration else { return }
            appsState = .loaded(apps)
        } catch is CancellationError {
            return
        } catch {
            guard session == sessionGeneration, reload == appsReloadGeneration else { return }
            appsState = .failed(error.localizedDescription)
            handleAuthenticationError(error, generation: session)
        }
    }

    func app(id: String) async throws -> AppSummary { try await authenticated { try await $0.app(id: id) } }

    func createApp(name: String, bundleID: String) async throws -> CreateAppResponse {
        let response = try await authenticated { try await $0.createApp(CreateAppRequest(name: name, bundleID: bundleID)) }
        upsertApp(response.app, insertAtFront: true)
        return response
    }

    func updateApp(id: String, request: UpdateAppRequest) async throws -> AppSummary {
        let app = try await authenticated { try await $0.updateApp(id: id, request: request) }
        upsertApp(app)
        return app
    }

    func apnsCredentials(appID: String) async throws -> [APNsCredential] {
        try await authenticated { try await $0.apnsCredentials(appID: appID) }
    }

    func createAPNsCredential(appID: String, teamID: String, keyID: String, p8: String) async throws -> APNsCredential {
        try await authenticated {
            try await $0.createAPNsCredential(appID: appID, request: APNsCredentialRequest(teamID: teamID, keyID: keyID, p8: p8))
        }
    }

    func deleteAPNsCredential(appID: String, credentialID: String) async throws {
        try await authenticated { try await $0.deleteAPNsCredential(appID: appID, credentialID: credentialID) }
    }

    func registrationKeys(appID: String) async throws -> [RegistrationKey] {
        try await authenticated { try await $0.registrationKeys(appID: appID) }
    }

    func createRegistrationKey(appID: String) async throws -> RegistrationKey {
        try await authenticated { try await $0.createRegistrationKey(appID: appID) }
    }

    func deleteRegistrationKey(appID: String, keyID: String) async throws {
        try await authenticated { try await $0.deleteRegistrationKey(appID: appID, keyID: keyID) }
    }

    func devices(appID: String) async throws -> [DeviceSummary] {
        try await authenticated { try await $0.devices(appID: appID) }
    }

    func deactivateDevice(appID: String, installationID: String, environment: PushEnvironment) async throws -> DeviceSummary {
        try await authenticated { try await $0.deactivateDevice(appID: appID, installationID: installationID, environment: environment) }
    }

    func sendPush(appID: String, request: PushRequest) async throws -> PushResponse {
        try await authenticated { try await $0.createPush(appID: appID, request: request) }
    }

    func pushes(appID: String) async throws -> [PushJob] {
        try await authenticated { try await $0.pushes(appID: appID) }
    }

    func push(appID: String, pushID: String) async throws -> PushDetailResponse {
        try await authenticated { try await $0.push(appID: appID, pushID: pushID) }
    }

    func users() async throws -> [AuthUser] { try await authenticated { try await $0.users() } }
    func createUser(_ request: CreateUserRequest) async throws -> AuthUser { try await authenticated { try await $0.createUser(request) } }
    func updateUser(id: String, request: UpdateUserRequest) async throws -> AuthUser { try await authenticated { try await $0.updateUser(id: id, request: request) } }
    func appMembers(appID: String) async throws -> [AppMember] { try await authenticated { try await $0.appMembers(appID: appID) } }

    func putAppMember(appID: String, userID: String, role: AppRole) async throws -> AppMember {
        try await authenticated { try await $0.putAppMember(appID: appID, userID: userID, role: role) }
    }

    func deleteAppMember(appID: String, userID: String) async throws {
        try await authenticated { try await $0.deleteAppMember(appID: appID, userID: userID) }
    }

    func logout() {
        let api = client
        let profile = selectedProfile
        beginSessionOperation()
        clearInMemoryAuthentication()
        sessionError = nil
        if let profile {
            do { try KeychainStore.remove(account: profile.id.uuidString) }
            catch { sessionError = error.localizedDescription }
        }
        if let api { Task { try? await api.logout() } }
    }

    func selectProfile(_ profile: ServerProfile) async {
        guard profiles.contains(where: { $0.id == profile.id }) else { return }
        beginSessionOperation()
        selectedProfile = profile
        sessionState = .restoring
        UserDefaults.standard.set(profile.id.uuidString, forKey: StorageKey.lastProfileID)
        await restoreSession()
    }

    func removeProfile(_ profile: ServerProfile) throws {
        try KeychainStore.remove(account: profile.id.uuidString)
        profiles.removeAll { $0.id == profile.id }
        persistProfiles()
        if selectedProfile?.id == profile.id {
            beginSessionOperation()
            selectedProfile = profiles.first
            clearInMemoryAuthentication()
            UserDefaults.standard.set(selectedProfile?.id.uuidString, forKey: StorageKey.lastProfileID)
        }
    }

    private func authenticated<Value: Sendable>(_ operation: (APIClient) async throws -> Value) async throws -> Value {
        guard let client else { throw AppStoreError.notAuthenticated }
        let generation = sessionGeneration
        do {
            let value = try await operation(client)
            guard generation == sessionGeneration else { throw AppStoreError.staleOperation }
            return value
        } catch {
            handleAuthenticationError(error, generation: generation)
            throw error
        }
    }

    private func establishSession(_ response: LoginResponse, profile: ServerProfile, client: APIClient) throws {
        try KeychainStore.set(response.accessToken, account: profile.id.uuidString)
        removeDuplicateProfiles(for: profile)
        profiles.removeAll { $0.id == profile.id }
        profiles.insert(profile, at: 0)
        selectedProfile = profile
        self.client = client
        sessionState = .authenticated(response.user)
        persistProfiles()
        UserDefaults.standard.set(profile.id.uuidString, forKey: StorageKey.lastProfileID)
    }

    @discardableResult
    private func beginSessionOperation() -> UInt {
        sessionGeneration &+= 1
        appsReloadGeneration &+= 1
        return sessionGeneration
    }

    private func handleAuthenticationError(_ error: Error, generation: UInt) {
        guard generation == sessionGeneration, case APIError.unauthorized = error else { return }
        if let selectedProfile { clearAuthentication(for: selectedProfile) }
        else { clearInMemoryAuthentication() }
        sessionError = APIError.unauthorized.localizedDescription
    }

    private func clearAuthentication(for profile: ServerProfile) {
        try? KeychainStore.remove(account: profile.id.uuidString)
        beginSessionOperation()
        clearInMemoryAuthentication()
    }

    private func clearInMemoryAuthentication() {
        client = nil
        appsState = .idle
        sessionState = .signedOut
    }

    private func profile(for baseURL: URL) -> ServerProfile {
        profiles.first(where: { $0.baseURL == baseURL }) ?? ServerProfile(name: baseURL.host ?? "SodaPush", baseURL: baseURL)
    }

    private func upsertApp(_ app: AppSummary, insertAtFront: Bool = false) {
        guard case var .loaded(apps) = appsState else { return }
        apps.removeAll { $0.id == app.id }
        if insertAtFront { apps.insert(app, at: 0) } else { apps.append(app); apps.sort { $0.createdAt > $1.createdAt } }
        appsState = .loaded(apps)
    }

    private func loadAndNormalizeProfiles() -> [ServerProfile] {
        guard let data = UserDefaults.standard.data(forKey: StorageKey.profiles),
              let savedProfiles = try? JSONDecoder().decode([ServerProfile].self, from: data) else { return [] }
        var seenURLs = Set<URL>()
        var result: [ServerProfile] = []
        for savedProfile in savedProfiles {
            guard let normalizedURL = try? APIClient.normalizedBaseURL(from: savedProfile.baseURL.absoluteString),
                  seenURLs.insert(normalizedURL).inserted else {
                try? KeychainStore.remove(account: savedProfile.id.uuidString)
                continue
            }
            result.append(ServerProfile(id: savedProfile.id, name: savedProfile.name, baseURL: normalizedURL))
        }
        if result != savedProfiles {
            profiles = result
            persistProfiles()
        }
        return result
    }

    private func removeDuplicateProfiles(for profile: ServerProfile) {
        for duplicate in profiles where duplicate.baseURL == profile.baseURL && duplicate.id != profile.id {
            try? KeychainStore.remove(account: duplicate.id.uuidString)
        }
        profiles.removeAll { $0.baseURL == profile.baseURL && $0.id != profile.id }
    }

    private func persistProfiles() {
        if let data = try? JSONEncoder().encode(profiles) { UserDefaults.standard.set(data, forKey: StorageKey.profiles) }
    }

    private enum StorageKey {
        static let profiles = "serverProfiles"
        static let lastProfileID = "lastServerProfileID"
    }
}
