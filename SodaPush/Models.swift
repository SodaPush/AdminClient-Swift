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

struct AuthUser: nonisolated Codable, Equatable, Sendable {
    let id: String
    let username: String
    let role: String
}

struct AppSummary: nonisolated Codable, Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let name: String
    let bundleID: String
    let createdAt: String?
    let disabledAt: String?
}

enum PushEnvironment: String, nonisolated Codable, CaseIterable, Identifiable, Sendable {
    case development
    case production

    var id: Self { self }
}

struct DeviceSummary: nonisolated Codable, Identifiable, Equatable, Sendable {
    let id: String
    let installationID: String
    let environment: PushEnvironment
    let platform: String
    let status: String
    let updatedAt: String
}

struct LoginRequest: nonisolated Codable, Sendable {
    let username: String
    let password: String
}

struct LoginResponse: nonisolated Codable, Sendable {
    let user: AuthUser
    let accessToken: String
}

struct MeResponse: nonisolated Codable, Sendable {
    let user: AuthUser
}

struct AppsResponse: nonisolated Codable, Sendable {
    let apps: [AppSummary]
}

struct DevicesResponse: nonisolated Codable, Sendable {
    let devices: [DeviceSummary]
}

struct PushRequest: nonisolated Codable, Sendable {
    let environment: PushEnvironment
    let pushType: PushType
    let target: PushTarget
    let payload: APNsPayload
}

enum PushType: String, nonisolated Codable, Sendable {
    case alert
}

struct PushTarget: nonisolated Codable, Sendable {
    let all: Bool
}

struct APNsPayload: nonisolated Codable, Sendable {
    let aps: APS
}

struct APS: nonisolated Codable, Sendable {
    let alert: PushAlert
}

struct PushAlert: nonisolated Codable, Sendable {
    let title: String
    let body: String
}

struct PushResponse: nonisolated Codable, Sendable {
    let jobID: String
    let status: String
}
