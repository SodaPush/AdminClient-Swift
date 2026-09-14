import Foundation

enum APIError: Error, LocalizedError, Sendable {
    case invalidURL
    case unauthorized
    case server(statusCode: Int, message: String, code: String?, requestID: String?)
    case invalidResponse
    case transport(String)
    case encoding(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            String(localized: "Enter a valid HTTPS server URL without a path, query, or credentials.")
        case .unauthorized:
            String(localized: "Your session has expired. Please sign in again.")
        case let .server(_, message, _, requestID):
            requestID.map { "\(message) (Request ID: \($0))" } ?? message
        case .invalidResponse:
            String(localized: "The server returned an invalid response.")
        case let .transport(details):
            details
        case let .encoding(details):
            String(format: String(localized: "Could not encode the request: %@"), details)
        case let .decoding(details):
            String(format: String(localized: "Could not read the server response: %@"), details)
        }
    }
}

actor APIClient {
    private let profile: ServerProfile
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var accessToken: String?

    init(profile: ServerProfile, accessToken: String? = nil, session: URLSession = .shared) {
        self.profile = profile
        self.accessToken = accessToken
        self.session = session
    }

    static func normalizedBaseURL(from input: String) throws -> URL {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "https",
              let host = components.host,
              !host.isEmpty,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              components.path.isEmpty || components.path == "/" else {
            throw APIError.invalidURL
        }
        components.scheme = "https"
        components.host = host.lowercased()
        components.path = ""
        guard let url = components.url else { throw APIError.invalidURL }
        return url
    }

    func health() async throws -> HealthResponse {
        try await send(path: ["healthz"], method: "GET", authenticated: false)
    }

    func readiness() async throws -> ReadinessResponse {
        try await send(path: ["readyz"], method: "GET", authenticated: false)
    }

    func bootstrapStatus() async throws -> BootstrapStatusResponse {
        try await send(path: ["v1", "bootstrap", "status"], method: "GET", authenticated: false)
    }

    func bootstrap(token: String, username: String, password: String) async throws -> LoginResponse {
        let response: LoginResponse = try await send(
            path: ["v1", "bootstrap"],
            method: "POST",
            headers: ["X-Soda-Bootstrap-Token": token],
            body: BootstrapRequest(username: username, password: password),
            authenticated: false
        )
        accessToken = response.accessToken
        return response
    }

    func login(username: String, password: String) async throws -> LoginResponse {
        let response: LoginResponse = try await send(
            path: ["v1", "auth", "login"],
            method: "POST",
            body: LoginRequest(username: username, password: password),
            authenticated: false
        )
        accessToken = response.accessToken
        return response
    }

    func logout() async throws {
        defer { accessToken = nil }
        try await sendVoid(path: ["v1", "auth", "logout"], method: "POST")
    }

    func currentUser() async throws -> AuthUser {
        let response: MeResponse = try await send(path: ["v1", "me"], method: "GET")
        return response.user
    }

    func apps() async throws -> [AppSummary] {
        let response: AppsResponse = try await send(path: ["v1", "apps"], method: "GET")
        return response.apps
    }

    func app(id: String) async throws -> AppSummary {
        let response: AppResponse = try await send(path: ["v1", "apps", id], method: "GET")
        return response.app
    }

    func createApp(_ request: CreateAppRequest) async throws -> CreateAppResponse {
        try await send(path: ["v1", "apps"], method: "POST", body: request)
    }

    func updateApp(id: String, request: UpdateAppRequest) async throws -> AppSummary {
        let response: AppResponse = try await send(path: ["v1", "apps", id], method: "PATCH", body: request)
        return response.app
    }

    func apnsCredentials(appID: String) async throws -> [APNsCredential] {
        let response: APNsCredentialsResponse = try await send(path: ["v1", "apps", appID, "apns-credentials"], method: "GET")
        return response.credentials
    }

    func createAPNsCredential(appID: String, request: APNsCredentialRequest) async throws -> APNsCredential {
        let response: APNsCredentialResponse = try await send(path: ["v1", "apps", appID, "apns-credentials"], method: "POST", body: request)
        return response.credential
    }

    func deleteAPNsCredential(appID: String, credentialID: String) async throws {
        try await sendVoid(path: ["v1", "apps", appID, "apns-credentials", credentialID], method: "DELETE")
    }

    func setDefaultAPNsCredential(appID: String, credentialID: String) async throws -> APNsCredential {
        let response: APNsCredentialResponse = try await send(
            path: ["v1", "apps", appID, "apns-credentials", credentialID],
            method: "PATCH",
            body: SetDefaultCredentialRequest()
        )
        return response.credential
    }

    func registrationKeys(appID: String) async throws -> [RegistrationKey] {
        let response: RegistrationKeysResponse = try await send(path: ["v1", "apps", appID, "registration-keys"], method: "GET")
        return response.registrationKeys
    }

    func createRegistrationKey(appID: String) async throws -> RegistrationKey {
        let response: RegistrationKeyResponse = try await send(path: ["v1", "apps", appID, "registration-keys"], method: "POST")
        return response.registrationKey
    }

    func deleteRegistrationKey(appID: String, keyID: String) async throws {
        try await sendVoid(path: ["v1", "apps", appID, "registration-keys", keyID], method: "DELETE")
    }

    func devices(appID: String) async throws -> [DeviceSummary] {
        let response: DevicesResponse = try await send(path: ["v1", "apps", appID, "devices"], method: "GET")
        return response.devices
    }

    func deactivateDevice(appID: String, installationID: String, environment: PushEnvironment) async throws -> DeviceSummary {
        let response: DeviceResponse = try await send(
            path: ["v1", "apps", appID, "devices", installationID],
            method: "PATCH",
            query: [URLQueryItem(name: "environment", value: environment.rawValue)],
            body: UpdateDeviceRequest.inactive
        )
        return response.device
    }

    func createPush(appID: String, request: PushRequest) async throws -> PushResponse {
        try await send(path: ["v1", "apps", appID, "pushes"], method: "POST", body: request)
    }

    func pushes(appID: String) async throws -> [PushJob] {
        let response: PushesResponse = try await send(path: ["v1", "apps", appID, "pushes"], method: "GET")
        return response.pushes
    }

    func push(appID: String, pushID: String) async throws -> PushDetailResponse {
        try await send(path: ["v1", "apps", appID, "pushes", pushID], method: "GET")
    }

    func deletePush(appID: String, pushID: String) async throws {
        try await sendVoid(path: ["v1", "apps", appID, "pushes", pushID], method: "DELETE")
    }

    func users() async throws -> [AuthUser] {
        let response: UsersResponse = try await send(path: ["v1", "users"], method: "GET")
        return response.users
    }

    func createUser(_ request: CreateUserRequest) async throws -> AuthUser {
        let response: UserResponse = try await send(path: ["v1", "users"], method: "POST", body: request)
        return response.user
    }

    func updateUser(id: String, request: UpdateUserRequest) async throws -> AuthUser {
        let response: UserResponse = try await send(path: ["v1", "users", id], method: "PATCH", body: request)
        return response.user
    }

    func appMembers(appID: String) async throws -> [AppMember] {
        let response: AppMembersResponse = try await send(path: ["v1", "apps", appID, "members"], method: "GET")
        return response.members
    }

    func putAppMember(appID: String, userID: String, role: AppRole) async throws -> AppMember {
        let response: AppMemberResponse = try await send(
            path: ["v1", "apps", appID, "members", userID],
            method: "PUT",
            body: PutAppMemberRequest(role: role)
        )
        return response.member
    }

    func deleteAppMember(appID: String, userID: String) async throws {
        try await sendVoid(path: ["v1", "apps", appID, "members", userID], method: "DELETE")
    }

    private func send<Response: Decodable & Sendable>(
        path: [String],
        method: String,
        query: [URLQueryItem] = [],
        headers: [String: String] = [:],
        authenticated: Bool = true
    ) async throws -> Response {
        try await sendData(path: path, method: method, query: query, headers: headers, body: nil, authenticated: authenticated)
    }

    private func send<Request: Encodable & Sendable, Response: Decodable & Sendable>(
        path: [String],
        method: String,
        query: [URLQueryItem] = [],
        headers: [String: String] = [:],
        body: Request,
        authenticated: Bool = true
    ) async throws -> Response {
        let data: Data
        do { data = try encoder.encode(body) }
        catch { throw APIError.encoding(error.localizedDescription) }
        return try await sendData(path: path, method: method, query: query, headers: headers, body: data, authenticated: authenticated)
    }

    private func sendVoid(
        path: [String],
        method: String,
        query: [URLQueryItem] = [],
        headers: [String: String] = [:],
        authenticated: Bool = true
    ) async throws {
        let (data, response) = try await perform(path: path, method: method, query: query, headers: headers, body: nil, authenticated: authenticated)
        guard (200...299).contains(response.statusCode) else { throw responseError(response, data: data) }
    }

    private func sendData<Response: Decodable & Sendable>(
        path: [String],
        method: String,
        query: [URLQueryItem],
        headers: [String: String],
        body: Data?,
        authenticated: Bool
    ) async throws -> Response {
        let (data, response) = try await perform(path: path, method: method, query: query, headers: headers, body: body, authenticated: authenticated)
        guard (200...299).contains(response.statusCode) else { throw responseError(response, data: data) }
        do { return try decoder.decode(Response.self, from: data) }
        catch { throw APIError.decoding(error.localizedDescription) }
    }

    private func perform(
        path: [String],
        method: String,
        query: [URLQueryItem],
        headers: [String: String],
        body: Data?,
        authenticated: Bool
    ) async throws -> (Data, HTTPURLResponse) {
        var url = path.reduce(profile.baseURL) { $0.appendingPathComponent($1) }
        if !query.isEmpty {
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw APIError.invalidURL }
            components.queryItems = query
            guard let queryURL = components.url else { throw APIError.invalidURL }
            url = queryURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        if authenticated, let accessToken { request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }

        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch is CancellationError { throw CancellationError() }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch { throw APIError.transport(error.localizedDescription) }
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        return (data, httpResponse)
    }

    private func responseError(_ response: HTTPURLResponse, data: Data) -> APIError {
        if response.statusCode == 401 { return .unauthorized }
        let errorBody = try? decoder.decode(ServerErrorResponse.self, from: data)
        let fallback = String(format: String(localized: "Request failed (HTTP %d)"), response.statusCode)
        return .server(
            statusCode: response.statusCode,
            message: errorBody?.message ?? fallback,
            code: errorBody?.code,
            requestID: errorBody?.requestID ?? response.value(forHTTPHeaderField: "X-Request-ID")
        )
    }

    private struct ServerErrorResponse: Decodable, Sendable {
        let code: String?
        let message: String?
        let requestID: String?
    }
}
