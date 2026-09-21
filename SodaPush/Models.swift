import Foundation

struct ServerProfile: nonisolated Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var baseURL: URL

    init(id: UUID = UUID(), name: String, baseURL: URL) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
    }
}

enum AppRole: String, nonisolated Codable, CaseIterable, Identifiable, Sendable {
    case owner, admin, developer, viewer

    var id: Self { self }
    var canManageApps: Bool { self == .owner || self == .admin }
    var canManageCredentials: Bool { self == .owner || self == .admin }
    var canManageRegistrationKeys: Bool { self == .owner || self == .admin }
    var canManageUsers: Bool { self == .owner }
    var canManageMembers: Bool { self == .owner || self == .admin }
    var canSendPushes: Bool { self != .viewer }
}

struct AuthUser: nonisolated Codable, Equatable, Sendable, Identifiable {
    let id: String
    let username: String
    let role: AppRole
    let disabledAt: String?
    let createdAt: String?
    let updatedAt: String?

    init(id: String, username: String, role: AppRole, disabledAt: String? = nil, createdAt: String? = nil, updatedAt: String? = nil) {
        self.id = id
        self.username = username
        self.role = role
        self.disabledAt = disabledAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct HealthResponse: nonisolated Codable, Equatable, Sendable { let status: String; let version: String }
struct ReadinessResponse: nonisolated Codable, Equatable, Sendable { let status: String }
struct BootstrapStatusResponse: nonisolated Codable, Equatable, Sendable { let initialized: Bool }

struct ServerConnectionSnapshot: Sendable {
    let profile: ServerProfile
    let health: HealthResponse
    let readiness: ReadinessResponse
    let bootstrap: BootstrapStatusResponse
}

struct LoginRequest: nonisolated Codable, Sendable { let username: String; let password: String }
typealias BootstrapRequest = LoginRequest
struct LoginResponse: nonisolated Codable, Sendable { let user: AuthUser; let accessToken: String }
struct MeResponse: nonisolated Codable, Sendable { let user: AuthUser }

struct AppSummary: nonisolated Codable, Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let name: String
    let bundleID: String
    let role: AppRole
    let createdAt: String
    let disabledAt: String?
}

struct AppsResponse: nonisolated Codable, Sendable { let apps: [AppSummary] }
struct AppResponse: nonisolated Codable, Sendable { let app: AppSummary }
struct CreateAppRequest: nonisolated Codable, Sendable { let name: String; let bundleID: String }

struct UpdateAppRequest: nonisolated Codable, Sendable {
    let name: String?
    let disabled: Bool?

    init(name: String? = nil, disabled: Bool? = nil) {
        self.name = name
        self.disabled = disabled
    }
}

struct RegistrationKey: nonisolated Codable, Identifiable, Equatable, Sendable {
    let id: String
    let keyID: String
    let secret: String?
    let active: Bool
    let createdAt: String
    let revokedAt: String?
}

struct CreateAppResponse: nonisolated Codable, Sendable { let app: AppSummary; let registrationKey: RegistrationKey }
struct RegistrationKeysResponse: nonisolated Codable, Sendable { let registrationKeys: [RegistrationKey] }
struct RegistrationKeyResponse: nonisolated Codable, Sendable { let registrationKey: RegistrationKey }

struct APNsCredential: nonisolated Codable, Identifiable, Equatable, Sendable {
    let id: String
    let teamID: String
    let keyID: String
    let environment: PushEnvironment
    let isDefault: Bool
    let createdAt: String
    let updatedAt: String

    private enum CodingKeys: String, CodingKey { case id, teamID, keyID, environment, isDefault, createdAt, updatedAt }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        teamID = try container.decode(String.self, forKey: .teamID)
        keyID = try container.decode(String.self, forKey: .keyID)
        environment = try container.decodeIfPresent(PushEnvironment.self, forKey: .environment) ?? .production
        isDefault = try container.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? "legacy:\(keyID)"
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? updatedAt
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(teamID, forKey: .teamID)
        try container.encode(keyID, forKey: .keyID)
        try container.encode(environment, forKey: .environment)
        try container.encode(isDefault, forKey: .isDefault)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

struct APNsCredentialsResponse: nonisolated Codable, Sendable { let credentials: [APNsCredential] }
struct APNsCredentialRequest: nonisolated Codable, Sendable {
    let teamID: String
    let keyID: String
    let p8: String
    let environment: PushEnvironment
    let makeDefault: Bool
}
struct SetDefaultCredentialRequest: nonisolated Encodable, Sendable { let isDefault = true }

struct APNsCredentialResponse: nonisolated Decodable, Sendable {
    let credential: APNsCredential

    private enum CodingKeys: String, CodingKey { case credential }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        credential = try container.decodeIfPresent(APNsCredential.self, forKey: .credential) ?? APNsCredential(from: decoder)
    }
}

enum PushEnvironment: String, nonisolated Codable, CaseIterable, Identifiable, Sendable {
    case development, production
    var id: Self { self }
    var title: String { self == .development ? "Sandbox" : "Production" }
}

struct DeviceSummary: nonisolated Codable, Identifiable, Equatable, Sendable {
    let id: String
    let installationID: String
    let environment: PushEnvironment
    let platform: String
    let appVersion: String?
    let appBuild: String?
    let locale: String?
    let language: String?
    let timeZone: String?
    let userID: String?
    let tags: [String]?
    let status: String
    let createdAt: String
    let updatedAt: String
}

struct DevicesResponse: nonisolated Codable, Sendable { let devices: [DeviceSummary] }
struct UpdateDeviceRequest: nonisolated Codable, Sendable { let status: String; static let inactive = Self(status: "inactive") }
struct DeviceResponse: nonisolated Codable, Sendable { let device: DeviceSummary }

enum JSONValue: nonisolated Codable, Equatable, Sendable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .object(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

enum PushType: String, nonisolated Codable, CaseIterable, Identifiable, Sendable {
    case alert, background, liveactivity
    var id: Self { self }
}

struct PushTarget: nonisolated Codable, Equatable, Sendable {
    let all: Bool?
    let installationIds: [String]?
    let tags: [String]?
    let languages: [String]?
    let userIDs: [String]?

    init(all: Bool) { self.all = all; installationIds = nil; tags = nil; languages = nil; userIDs = nil }
    init(installationIds: [String]) { all = nil; self.installationIds = installationIds; tags = nil; languages = nil; userIDs = nil }
    init(tags: [String]) { all = nil; installationIds = nil; self.tags = tags; languages = nil; userIDs = nil }
    init(languages: [String]) { all = nil; installationIds = nil; tags = nil; self.languages = languages; userIDs = nil }
    init(userIDs: [String]) { all = nil; installationIds = nil; tags = nil; languages = nil; self.userIDs = userIDs }
}

struct PushRequest: nonisolated Codable, Sendable {
    let environment: PushEnvironment
    let credentialID: String?
    let pushType: PushType
    let target: PushTarget
    let payload: JSONValue

    init(environment: PushEnvironment, credentialID: String? = nil, pushType: PushType, target: PushTarget, payload: JSONValue) {
        self.environment = environment
        self.credentialID = credentialID
        self.pushType = pushType
        self.target = target
        self.payload = payload
    }

    init(environment: PushEnvironment, credentialID: String? = nil, pushType: PushType, target: PushTarget, payload: APNsPayload) {
        self.init(environment: environment, credentialID: credentialID, pushType: pushType, target: target, payload: payload.jsonValue)
    }
}

struct APNsPayload: nonisolated Codable, Sendable {
    let aps: APS
    var jsonValue: JSONValue { .object(["aps": aps.jsonValue]) }
}

struct APS: nonisolated Codable, Sendable {
    let alert: PushAlert
    var jsonValue: JSONValue { .object(["alert": alert.jsonValue]) }
}

struct PushAlert: nonisolated Codable, Sendable {
    let title: String
    let body: String
    var jsonValue: JSONValue { .object(["title": .string(title), "body": .string(body)]) }
}

struct PushResponse: nonisolated Codable, Sendable { let jobID: String; let status: String }

struct PushJob: nonisolated Codable, Identifiable, Equatable, Sendable {
    let id: String
    let appID: String
    let environment: PushEnvironment
    let credentialID: String?
    let pushType: PushType
    let target: PushTarget?
    let payload: JSONValue?
    let status: String
    let totalCount: Int
    let successCount: Int
    let failureCount: Int
    let createdBy: String?
    let createdAt: String
    let updatedAt: String

    private enum CodingKeys: String, CodingKey {
        case id, appID, environment, credentialID, pushType, target, payload, status
        case totalCount, successCount, failureCount, createdBy, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        appID = try container.decodeIfPresent(String.self, forKey: .appID) ?? ""
        environment = try container.decodeIfPresent(PushEnvironment.self, forKey: .environment) ?? .development
        credentialID = try container.decodeIfPresent(String.self, forKey: .credentialID)
        pushType = try container.decodeIfPresent(PushType.self, forKey: .pushType) ?? .alert
        target = try container.decodeIfPresent(PushTarget.self, forKey: .target)
        payload = try container.decodeIfPresent(JSONValue.self, forKey: .payload)
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "unknown"
        totalCount = try container.decodeIfPresent(Int.self, forKey: .totalCount) ?? 0
        successCount = try container.decodeIfPresent(Int.self, forKey: .successCount) ?? 0
        failureCount = try container.decodeIfPresent(Int.self, forKey: .failureCount) ?? 0
        createdBy = try container.decodeIfPresent(String.self, forKey: .createdBy)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? createdAt
    }
}

struct PushesResponse: nonisolated Codable, Sendable { let pushes: [PushJob] }

struct Delivery: nonisolated Codable, Identifiable, Equatable, Sendable {
    let id: String
    let deviceID: String?
    let apnsID: String?
    let status: String
    let apnsStatus: Int?
    let reason: String?
    let createdAt: String
    let updatedAt: String
}

struct PushDetailResponse: nonisolated Codable, Sendable { let push: PushJob; let deliveries: [Delivery] }
struct UsersResponse: nonisolated Codable, Sendable { let users: [AuthUser] }
struct UserResponse: nonisolated Codable, Sendable { let user: AuthUser }
struct CreateUserRequest: nonisolated Codable, Sendable { let username: String; let password: String; let role: AppRole }

struct UpdateUserRequest: nonisolated Codable, Sendable {
    let username: String?
    let password: String?
    let currentPassword: String?
    let role: AppRole?
    let disabled: Bool?

    init(username: String? = nil, password: String? = nil, currentPassword: String? = nil, role: AppRole? = nil, disabled: Bool? = nil) {
        self.username = username
        self.password = password
        self.currentPassword = currentPassword
        self.role = role
        self.disabled = disabled
    }
}

struct AppMember: nonisolated Codable, Identifiable, Equatable, Sendable {
    let userID: String
    let username: String
    let role: AppRole
    let disabledAt: String?
    let createdAt: String
    var id: String { userID }
}

struct AppMembersResponse: nonisolated Codable, Sendable { let members: [AppMember] }
struct MemberCandidatesResponse: nonisolated Codable, Sendable { let users: [AuthUser] }
struct AppMemberResponse: nonisolated Codable, Sendable { let member: AppMember }
struct SaveAppMemberRequest: nonisolated Codable, Sendable { let role: AppRole }
