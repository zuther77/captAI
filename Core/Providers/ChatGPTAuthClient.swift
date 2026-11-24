import Foundation

/// Official Sign in with ChatGPT (OSS) OAuth client: PKCE, loopback callback, token exchange, refresh.
struct ChatGPTAuthClient: Sendable {
    var transport: any HTTPTransport = URLSessionTransport()
    /// Opens the system browser. The Settings UI supplies `NSWorkspace.shared.open`.
    var openURL: @Sendable (URL) -> Void

    init(
        transport: any HTTPTransport = URLSessionTransport(),
        openURL: @escaping @Sendable (URL) -> Void
    ) {
        self.transport = transport
        self.openURL = openURL
    }

    /// Runs browser sign-in and returns a validated session with plan-usage scopes when granted.
    func signIn(store: any ChatGPTSessionStore) async throws(AppError) -> ChatGPTSession {
        let hostID = try store.hostID()
        let existing = try? store.load()
        let server = LoopbackAuthServer()
        let redirectURI: URL
        do {
            redirectURI = try await server.start()
        } catch {
            throw AppError.providerUnavailable
        }
        defer { server.cancel() }

        let state = ChatGPTPKCE.makeState()
        let nonce = ChatGPTPKCE.makeNonce()
        let verifier = ChatGPTPKCE.makeVerifier()
        let challenge = ChatGPTPKCE.challenge(for: verifier)

        let clientIDForAuth = existing?.clientID ?? ChatGPTAuth.dynamicClientID
        var items: [URLQueryItem] = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: clientIDForAuth),
            .init(name: "redirect_uri", value: redirectURI.absoluteString),
            .init(name: "scope", value: ChatGPTAuth.scope),
            .init(name: "resource", value: ChatGPTAuth.resource),
            .init(name: "state", value: state),
            .init(name: "nonce", value: nonce),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "ext_agent_host_id", value: hostID),
        ]
        if clientIDForAuth == ChatGPTAuth.dynamicClientID {
            items.append(.init(name: "agent_name_hint", value: ChatGPTAuth.appName))
        } else if let idToken = existing?.idToken {
            items.append(.init(name: "id_token_hint", value: idToken))
            if let email = existing?.email {
                items.append(.init(name: "login_hint", value: email))
            }
        }

        var components = URLComponents(url: ChatGPTAuth.authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = items
        guard let authorizeURL = components.url else { throw AppError.providerRequestRejected }
        openURL(authorizeURL)

        let callback: LoopbackAuthServer.Callback
        do {
            callback = try await server.waitForCallback()
        } catch is CancellationError {
            throw AppError.operationCancelled
        } catch {
            throw AppError.providerUnavailable
        }

        if callback.query["error"] != nil {
            throw AppError.cloudConsentDeclined
        }
        guard callback.query["state"] == state else { throw AppError.providerAuthFailed }
        guard let code = callback.query["code"], !code.isEmpty else { throw AppError.providerAuthFailed }

        let issuedClientID: String
        if let fromCallback = callback.query["client_id"], !fromCallback.isEmpty {
            if clientIDForAuth != ChatGPTAuth.dynamicClientID, fromCallback != clientIDForAuth {
                throw AppError.providerAuthFailed
            }
            issuedClientID = fromCallback
        } else if clientIDForAuth != ChatGPTAuth.dynamicClientID {
            issuedClientID = clientIDForAuth
        } else {
            throw AppError.providerAuthFailed
        }

        let token = try await exchangeCode(
            code: code,
            clientID: issuedClientID,
            verifier: verifier,
            redirectURI: redirectURI
        )
        let jwks = try await fetchJWKS()
        let claims = try OpenIDTokenVerifier.verify(
            idToken: token.idToken,
            audience: issuedClientID,
            expectedNonce: nonce,
            jwksJSON: jwks
        )

        let session = ChatGPTSession(
            email: claims.email ?? existing?.email,
            name: claims.name ?? existing?.name,
            subject: claims.subject,
            clientID: issuedClientID,
            hostID: hostID,
            idToken: token.idToken,
            accessToken: token.accessToken,
            refreshToken: token.refreshToken ?? existing?.refreshToken,
            tokenType: token.tokenType,
            scopes: token.scopes,
            savedAt: Date(),
            expiresIn: token.expiresIn
        )
        try store.save(session)
        return session
    }

    func refresh(_ session: ChatGPTSession, store: any ChatGPTSessionStore) async throws(AppError) -> ChatGPTSession {
        guard let refreshToken = session.refreshToken, !refreshToken.isEmpty else {
            throw AppError.providerAuthFailed
        }
        var request = URLRequest(url: ChatGPTAuth.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(form([
            "grant_type": "refresh_token",
            "client_id": session.clientID,
            "refresh_token": refreshToken,
            "resource": ChatGPTAuth.resource,
        ]).utf8)

        let status: Int
        let data: Data
        do {
            (status, data) = try await transport.data(for: request)
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.providerUnavailable
        }
        guard (200..<300).contains(status) else { throw AppError.providerAuthFailed }
        let token = try parseTokenResponse(data)
        var updated = session
        updated.accessToken = token.accessToken
        if !token.idToken.isEmpty { updated.idToken = token.idToken }
        updated.refreshToken = token.refreshToken ?? session.refreshToken
        updated.tokenType = token.tokenType
        if !token.scopes.isEmpty { updated.scopes = token.scopes }
        updated.savedAt = Date()
        updated.expiresIn = token.expiresIn
        try store.save(updated)
        return updated
    }

    /// Ensures a usable access token (refreshing when expired).
    func validAccessToken(store: any ChatGPTSessionStore) async throws(AppError) -> (token: String, session: ChatGPTSession) {
        guard var session = try store.load() else { throw AppError.providerAuthFailed }
        if session.isAccessTokenExpired {
            session = try await refresh(session, store: store)
        }
        guard session.planUsageEnabled else { throw AppError.providerRequestRejected }
        return (session.accessToken, session)
    }

    // MARK: Private

    private struct TokenPayload {
        let accessToken: String
        let idToken: String
        let refreshToken: String?
        let tokenType: String
        let expiresIn: TimeInterval
        let scopes: [String]
    }

    private func exchangeCode(
        code: String,
        clientID: String,
        verifier: String,
        redirectURI: URL
    ) async throws(AppError) -> TokenPayload {
        var request = URLRequest(url: ChatGPTAuth.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(form([
            "grant_type": "authorization_code",
            "client_id": clientID,
            "code": code,
            "code_verifier": verifier,
            "redirect_uri": redirectURI.absoluteString,
            "resource": ChatGPTAuth.resource,
        ]).utf8)
        let status: Int
        let data: Data
        do {
            (status, data) = try await transport.data(for: request)
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.providerUnavailable
        }
        guard (200..<300).contains(status) else { throw AppError.providerAuthFailed }
        return try parseTokenResponse(data)
    }

    private func fetchJWKS() async throws(AppError) -> Data {
        var request = URLRequest(url: ChatGPTAuth.jwksURL)
        request.httpMethod = "GET"
        let status: Int
        let data: Data
        do {
            (status, data) = try await transport.data(for: request)
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.providerUnavailable
        }
        guard (200..<300).contains(status) else { throw AppError.providerUnavailable }
        return data
    }

    private func parseTokenResponse(_ data: Data) throws(AppError) -> TokenPayload {
        let object: [String: Any]
        do {
            object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        } catch {
            throw AppError.providerResponseInvalid
        }
        guard let access = object["access_token"] as? String, !access.isEmpty else {
            throw AppError.providerAuthFailed
        }
        let idToken = object["id_token"] as? String ?? ""
        let refresh = object["refresh_token"] as? String
        let type = object["token_type"] as? String ?? "Bearer"
        let expires = (object["expires_in"] as? TimeInterval)
            ?? (object["expires_in"] as? Int).map(Double.init)
            ?? 3600
        let scopeString = object["scope"] as? String ?? ""
        let scopes = scopeString.split(separator: " ").map(String.init)
        return TokenPayload(
            accessToken: access,
            idToken: idToken,
            refreshToken: refresh,
            tokenType: type,
            expiresIn: expires,
            scopes: scopes
        )
    }

    private func form(_ fields: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return fields.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }
        .joined(separator: "&")
    }
}
