import Foundation
import Combine

@MainActor
final class SessionStore: ObservableObject {
    @Published var user: User?
    @Published var isAuthenticated = false
    @Published var isBootstrapping = true
    @Published var resetToken: String?
    @Published var pendingInviteDeepLink: String?
    @Published var errorMessage: String?

    private let tokenKey = "cokeep.authToken"

    func bootstrap() async {
        defer { isBootstrapping = false }
        if let token = UserDefaults.standard.string(forKey: tokenKey) {
            APIClient.shared.authToken = token
            do {
                let response: MeResponse = try await APIClient.shared.request("GET", path: "api/auth/me")
                user = response.user
                isAuthenticated = true
            } catch {
                clearSession()
            }
        }
    }

    func register(
        firstName: String,
        lastName: String,
        email: String,
        countryCode: String,
        phone: String,
        password: String
    ) async throws {
        let body = RegisterBody(
            firstName: firstName,
            lastName: lastName,
            email: email,
            countryCode: countryCode,
            phone: phone,
            password: password
        )
        let response: AuthResponse = try await APIClient.shared.request(
            "POST",
            path: "api/auth/register",
            body: body,
            authorized: false
        )
        applyAuth(response)
    }

    func login(email: String, password: String) async throws {
        struct LoginBody: Encodable {
            let email: String
            let password: String
        }
        let response: AuthResponse = try await APIClient.shared.request(
            "POST",
            path: "api/auth/login",
            body: LoginBody(email: email, password: password),
            authorized: false
        )
        applyAuth(response)
    }

    func logout() {
        clearSession()
    }

    func updateProfile(firstName: String, lastName: String, email: String, avatarUrl: String?) async throws {
        struct Body: Encodable {
            let firstName: String
            let lastName: String
            let email: String
            let avatarUrl: String?
        }
        let response: MeResponse = try await APIClient.shared.request(
            "PATCH",
            path: "api/users/me",
            body: Body(firstName: firstName, lastName: lastName, email: email, avatarUrl: avatarUrl)
        )
        user = response.user
    }

    func requestPasswordReset(email: String) async throws {
        struct Body: Encodable { let email: String }
        struct Ok: Codable { let ok: Bool? }
        let _: Ok = try await APIClient.shared.request(
            "POST",
            path: "api/auth/forgot-password",
            body: Body(email: email),
            authorized: false
        )
    }

    func resetPassword(token: String, password: String) async throws {
        struct Body: Encodable {
            let token: String
            let password: String
        }
        struct Ok: Codable { let ok: Bool? }
        let _: Ok = try await APIClient.shared.request(
            "POST",
            path: "api/auth/reset-password",
            body: Body(token: token, password: password),
            authorized: false
        )
        resetToken = nil
    }

    func handleDeepLink(_ url: URL) {
        guard url.scheme == "cokeep" else { return }
        if url.host == "reset-password" {
            let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            resetToken = comps?.queryItems?.first(where: { $0.name == "token" })?.value
        }
        if url.host == "invite" {
            pendingInviteDeepLink = url.absoluteString
        }
    }

    private func applyAuth(_ response: AuthResponse) {
        UserDefaults.standard.set(response.token, forKey: tokenKey)
        APIClient.shared.authToken = response.token
        user = response.user
        isAuthenticated = true
    }

    private func clearSession() {
        UserDefaults.standard.removeObject(forKey: tokenKey)
        APIClient.shared.authToken = nil
        user = nil
        isAuthenticated = false
    }
}

private struct MeResponse: Codable {
    let user: User
}

private struct RegisterBody: Encodable {
    let firstName: String
    let lastName: String
    let email: String
    let countryCode: String
    let phone: String
    let password: String
}
