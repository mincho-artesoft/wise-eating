import Foundation

/// Our backend (server/assistant-backend). The app never holds an OpenAI key:
/// the backend mints short-lived Realtime secrets and proxies reasoning calls.
@MainActor
final class AssistantBackendClient: ObservableObject {
    static let shared = AssistantBackendClient()

    struct Wallet: Decodable, Equatable {
        var credits: Int
        var balanceMilli: String
    }

    enum GrantState: String, Decodable { case available, used, disabled }

    struct ClientSecret: Decodable {
        var sessionId: String
        var clientSecret: String
        var expiresAt: Int?
        var model: String
        var maxMinutes: Int
        var safetyIdentifier: String?
        var wallet: Wallet
    }

    enum BackendError: LocalizedError {
        case notConfigured, insufficientCredits, http(Int, String)

        var errorDescription: String? {
            switch self {
            case .notConfigured: String(localized: "The online assistant is not set up in this build.")
            case .insufficientCredits: String(localized: "You are out of AI credits.")
            case let .http(_, message): message
            }
        }
    }

    @Published private(set) var wallet: Wallet?
    @Published private(set) var grantState: GrantState?
    private var token: String? = AssistantDeviceIdentity.deviceToken

    /// From the `AyuraAssistantBackendURL` Info.plist key, set by the
    /// `AYURA_ASSISTANT_BACKEND_URL` build setting; empty means no online assistant.
    static var baseURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "AyuraAssistantBackendURL") as? String,
              !raw.trimmingCharacters(in: .whitespaces).isEmpty,
              !raw.hasPrefix("$("),
              let url = URL(string: raw.trimmingCharacters(in: .whitespaces)) else { return nil }
        return url
    }

    static var isConfigured: Bool { baseURL != nil }

    /// Both the flag and a backend URL are needed for the paid engine.
    static var isOpenAIAvailable: Bool { FeatureFlags.openAIAssistant && isConfigured }

    // MARK: Device

    func ensureRegistered() async throws {
        if token != nil { return }
        try await register()
    }

    private struct RegisterResponse: Decodable {
        var token: String
        var wallet: Wallet
        var onboardingGrant: GrantState
        var appAccountToken: String
    }

    private func register() async throws {
        var body: [String: Any] = ["installId": AssistantDeviceIdentity.installID]
        let challenge = try await self.challenge()
        if let attested = await AssistantDeviceIdentity.attest(challenge: challenge) {
            body["keyId"] = attested.keyID
            body["attestation"] = attested.attestation
            body["challenge"] = challenge
        }
        let response: RegisterResponse = try await send("devices/register", body: body, authorized: false)
        token = response.token
        AssistantDeviceIdentity.deviceToken = response.token
        UserDefaults.standard.set(response.appAccountToken, forKey: "assistant.appAccountToken")
        wallet = response.wallet
        grantState = response.onboardingGrant
    }

    /// The UUID StoreKit purchases carry, so the server credits this install.
    var appAccountToken: UUID? {
        UserDefaults.standard.string(forKey: "assistant.appAccountToken").flatMap(UUID.init(uuidString:))
    }

    private struct ChallengeResponse: Decodable { var challenge: String }

    private func challenge() async throws -> String {
        let r: ChallengeResponse = try await send("devices/challenge", body: [:], authorized: false)
        return r.challenge
    }

    private struct WalletResponse: Decodable { var wallet: Wallet; var onboardingGrant: GrantState? }

    @discardableResult
    func refreshWallet() async throws -> Wallet {
        try await ensureRegistered()
        let r: WalletResponse = try await send("wallet", method: "GET")
        wallet = r.wallet
        grantState = r.onboardingGrant
        return r.wallet
    }

    private struct GrantResponse: Decodable { var granted: Int; var wallet: Wallet }

    /// The one-time welcome credits; proves the device with DeviceCheck and App Attest.
    func claimOnboardingGrant() async throws -> Int {
        try await ensureRegistered()
        var body: [String: Any] = [:]
        if let dc = await AssistantDeviceIdentity.deviceCheckToken() { body["deviceCheckToken"] = dc }
        let challenge = try await self.challenge()
        if let assertion = await AssistantDeviceIdentity.assertion(challenge: challenge) {
            body["assertion"] = assertion
            body["challenge"] = challenge
        }
        let r: GrantResponse = try await send("grants/onboarding", body: body)
        wallet = r.wallet
        grantState = .used
        return r.granted
    }

    // MARK: Realtime

    func clientSecret(purpose: String) async throws -> ClientSecret {
        try await ensureRegistered()
        let r: ClientSecret = try await send("realtime/client-secret", body: ["purpose": purpose])
        wallet = r.wallet
        return r
    }

    struct UsageResult: Decodable { var insufficientCredits: Bool; var ended: Bool; var wallet: Wallet }

    func reportUsage(sessionID: String, eventID: String, kind: String, usage: [String: Any]) async throws -> UsageResult {
        let r: UsageResult = try await send("realtime/sessions/\(sessionID)/usage", body: ["eventId": eventID, "kind": kind, "usage": usage])
        wallet = r.wallet
        return r
    }

    private struct EndResponse: Decodable { var wallet: Wallet }

    func endSession(_ sessionID: String) async {
        if let r: EndResponse = try? await send("realtime/sessions/\(sessionID)/end", body: [:]) {
            wallet = r.wallet
        }
    }

    // MARK: Reasoning

    struct ReasoningResponse {
        var output: [[String: Any]]
        var text: String
        var wallet: Wallet?
    }

    func reasoning(purpose: String, input: [[String: Any]], imageJPEG: Data? = nil) async throws -> ReasoningResponse {
        try await ensureRegistered()
        var body: [String: Any] = ["purpose": purpose, "requestId": UUID().uuidString, "input": input]
        if let imageJPEG { body["imageJPEGBase64"] = imageJPEG.base64EncodedString() }
        let data = try await raw("reasoning", method: "POST", body: body, authorized: true)
        let object = (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let walletData = (object["wallet"]).flatMap { try? JSONSerialization.data(withJSONObject: $0) }
        let wallet = walletData.flatMap { try? JSONDecoder().decode(Wallet.self, from: $0) }
        if let wallet { self.wallet = wallet }
        return ReasoningResponse(
            output: object["output"] as? [[String: Any]] ?? [],
            text: object["text"] as? String ?? "",
            wallet: wallet)
    }

    // MARK: App Store

    func recordTransaction(_ signedTransactionInfo: String) async throws {
        try await ensureRegistered()
        let r: WalletResponse = try await send("app-store/transactions", body: ["signedTransactionInfo": signedTransactionInfo])
        wallet = r.wallet
    }

    // MARK: HTTP

    private func send<T: Decodable>(_ path: String, method: String = "POST", body: [String: Any]? = nil, authorized: Bool = true) async throws -> T {
        let data = try await raw(path, method: method, body: body, authorized: authorized)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func raw(_ path: String, method: String, body: [String: Any]?, authorized: Bool, retried: Bool = false) async throws -> Data {
        guard let base = Self.baseURL else { throw BackendError.notConfigured }
        var request = URLRequest(url: base.appendingPathComponent("api").appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = path == "reasoning" ? 120 : 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authorized, let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body, method != "GET" { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401, authorized, !retried {
            // The device token expired or the server forgot us: register again once.
            token = nil
            AssistantDeviceIdentity.deviceToken = nil
            try await register()
            return try await raw(path, method: method, body: body, authorized: authorized, retried: true)
        }
        if status == 402 { throw BackendError.insufficientCredits }
        guard (200..<300).contains(status) else {
            let message = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["message"] as? String
            throw BackendError.http(status, message ?? String(localized: "The online assistant could not answer."))
        }
        return data
    }
}
