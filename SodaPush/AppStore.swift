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

    var errorDescription: String? {
        String(localized: "Sign in before making this request.")
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

    var currentUser: AuthUser? {
        guard case let .authenticated(user) = sessionState else { return nil }
        return user
    }

    var suggestedServerURL: String {
        selectedProfile?.baseURL.absoluteString ?? profiles.first?.baseURL.absoluteString ?? "https://"
    }

    func restoreSession() async {
        guard sessionState == .restoring else { return }
        profiles = loadAndNormalizeProfiles()

        let lastProfileID = UserDefaults.standard.string(forKey: StorageKey.lastProfileID)
        let profile = profiles.first { $0.id.uuidString == lastProfileID } ?? profiles.first
        guard let profile else {
            sessionState = .signedOut
            return
        }
        selectedProfile = profile

        do {
            guard let token = try KeychainStore.get(account: profile.id.uuidString) else {
                sessionState = .signedOut
                return
            }
            let api = APIClient(profile: profile, accessToken: token)
            let user = try await api.currentUser()
            client = api
            sessionState = .authenticated(user)
            await reloadApps()
        } catch APIError.unauthorized {
            clearAuthentication(for: profile)
            sessionError = APIError.unauthorized.localizedDescription
        } catch {
            sessionState = .signedOut
            sessionError = error.localizedDescription
        }
    }

    func login(serverURL: String, username: String, password: String) async {
        sessionError = nil
        isSigningIn = true
        defer { isSigningIn = false }

        do {
            let baseURL = try APIClient.normalizedBaseURL(from: serverURL)
            let profile = profiles.first(where: { $0.baseURL == baseURL })
                ?? ServerProfile(name: baseURL.host ?? "SodaPush", baseURL: baseURL)
            let api = APIClient(profile: profile)
            let response = try await api.login(username: username, password: password)
            try KeychainStore.set(response.accessToken, account: profile.id.uuidString)

            removeDuplicateProfiles(for: profile)
            profiles.removeAll { $0.id == profile.id }
            profiles.insert(profile, at: 0)
            selectedProfile = profile
            client = api
            sessionState = .authenticated(response.user)
            persistProfiles()
            UserDefaults.standard.set(profile.id.uuidString, forKey: StorageKey.lastProfileID)
            await reloadApps()
        } catch {
            sessionState = .signedOut
            sessionError = error.localizedDescription
        }
    }

    func reloadApps() async {
        guard let client else {
            appsState = .idle
            return
        }
        appsState = .loading
        do {
            appsState = .loaded(try await client.apps())
        } catch {
            appsState = .failed(error.localizedDescription)
            handleAuthenticationError(error)
        }
    }

    func devices(appID: String) async throws -> [DeviceSummary] {
        guard let client else { throw AppStoreError.notAuthenticated }
        do {
            return try await client.devices(appID: appID)
        } catch {
            handleAuthenticationError(error)
            throw error
        }
    }

    func sendPush(appID: String, request: PushRequest) async throws -> PushResponse {
        guard let client else { throw AppStoreError.notAuthenticated }
        do {
            return try await client.createPush(appID: appID, request: request)
        } catch {
            handleAuthenticationError(error)
            throw error
        }
    }

    func logout() {
        do {
            if let selectedProfile {
                try KeychainStore.remove(account: selectedProfile.id.uuidString)
            }
            clearInMemoryAuthentication()
            sessionError = nil
        } catch {
            sessionError = error.localizedDescription
        }
    }

    private func handleAuthenticationError(_ error: Error) {
        guard case APIError.unauthorized = error else { return }
        if let selectedProfile {
            clearAuthentication(for: selectedProfile)
        } else {
            clearInMemoryAuthentication()
        }
        sessionError = APIError.unauthorized.localizedDescription
    }

    private func clearAuthentication(for profile: ServerProfile) {
        try? KeychainStore.remove(account: profile.id.uuidString)
        clearInMemoryAuthentication()
    }

    private func clearInMemoryAuthentication() {
        client = nil
        appsState = .idle
        sessionState = .signedOut
    }

    private func loadAndNormalizeProfiles() -> [ServerProfile] {
        guard let data = UserDefaults.standard.data(forKey: StorageKey.profiles),
              let savedProfiles = try? JSONDecoder().decode([ServerProfile].self, from: data) else {
            return []
        }

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
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: StorageKey.profiles)
        }
    }

    private enum StorageKey {
        static let profiles = "serverProfiles"
        static let lastProfileID = "lastServerProfileID"
    }
}
