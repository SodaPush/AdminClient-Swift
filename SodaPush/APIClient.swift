import Foundation

enum APIError: Error, LocalizedError, Sendable {
    case invalidURL
    case unauthorized
    case server(message: String, code: String?, requestID: String?)
    case invalidResponse
    case encoding(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            String(localized: "Enter a valid HTTPS server URL without a path, query, or credentials.")
        case .unauthorized:
            String(localized: "Your session has expired. Please sign in again.")
        case let .server(message, _, requestID):
            if let requestID, !requestID.isEmpty {
                "\(message) (Request ID: \(requestID))"
            } else {
                message
            }
        case .invalidResponse:
            String(localized: "The server returned an invalid response.")
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

    func login(username: String, password: String) async throws -> LoginResponse {
        let response: LoginResponse = try await send(
            pathComponents: ["v1", "auth", "login"],
            method: "POST",
            body: LoginRequest(username: username, password: password),
            authenticated: false
        )
        accessToken = response.accessToken
        return response
    }

    func currentUser() async throws -> AuthUser {
        let response: MeResponse = try await send(pathComponents: ["v1", "me"], method: "GET")
        return response.user
    }

    func apps() async throws -> [AppSummary] {
        let response: AppsResponse = try await send(pathComponents: ["v1", "apps"], method: "GET")
        return response.apps
    }

    func devices(appID: String) async throws -> [DeviceSummary] {
        let response: DevicesResponse = try await send(
            pathComponents: ["v1", "apps", appID, "devices"],
            method: "GET"
        )
        return response.devices
    }

    func createPush(appID: String, request: PushRequest) async throws -> PushResponse {
        try await send(
            pathComponents: ["v1", "apps", appID, "pushes"],
            method: "POST",
            body: request
        )
    }

    private func send<Response: Decodable & Sendable>(
        pathComponents: [String],
        method: String,
        authenticated: Bool = true
    ) async throws -> Response {
        try await sendData(
            pathComponents: pathComponents,
            method: method,
            body: nil,
            authenticated: authenticated
        )
    }

    private func send<Request: Encodable & Sendable, Response: Decodable & Sendable>(
        pathComponents: [String],
        method: String,
        body: Request,
        authenticated: Bool = true
    ) async throws -> Response {
        let data: Data
        do {
            data = try encoder.encode(body)
        } catch {
            throw APIError.encoding(error.localizedDescription)
        }
        return try await sendData(
            pathComponents: pathComponents,
            method: method,
            body: data,
            authenticated: authenticated
        )
    }

    private func sendData<Response: Decodable & Sendable>(
        pathComponents: [String],
        method: String,
        body: Data?,
        authenticated: Bool
    ) async throws -> Response {
        let url = pathComponents.reduce(profile.baseURL) { partialURL, component in
            partialURL.appendingPathComponent(component)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if authenticated, let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 { throw APIError.unauthorized }
            let errorBody = try? decoder.decode(ServerErrorResponse.self, from: data)
            let fallback = String(
                format: String(localized: "Request failed (HTTP %d)"),
                httpResponse.statusCode
            )
            throw APIError.server(
                message: errorBody?.message ?? fallback,
                code: errorBody?.code,
                requestID: errorBody?.requestID ?? httpResponse.value(forHTTPHeaderField: "X-Request-ID")
            )
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }

    private struct ServerErrorResponse: Decodable, Sendable {
        let code: String?
        let message: String?
        let requestID: String?
    }
}
