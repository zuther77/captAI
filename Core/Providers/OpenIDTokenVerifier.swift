import Foundation
import Security

/// Verifies OpenAI ID tokens (RS256) against the published JWKS.
enum OpenIDTokenVerifier {
    struct Claims: Equatable, Sendable {
        let subject: String
        let email: String?
        let name: String?
        let nonce: String?
    }

    static func verify(
        idToken: String,
        audience clientID: String,
        expectedNonce: String,
        jwksJSON: Data,
        issuer: String = ChatGPTAuth.issuer,
        now: Date = Date()
    ) throws(AppError) -> Claims {
        let parts = idToken.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3,
              let headerData = Data(base64URLEncoded: parts[0]),
              let payloadData = Data(base64URLEncoded: parts[1]),
              let signature = Data(base64URLEncoded: parts[2])
        else { throw AppError.providerAuthFailed }

        let header: [String: Any]
        let payload: [String: Any]
        do {
            header = try JSONSerialization.jsonObject(with: headerData) as? [String: Any] ?? [:]
            payload = try JSONSerialization.jsonObject(with: payloadData) as? [String: Any] ?? [:]
        } catch {
            throw AppError.providerAuthFailed
        }

        guard (header["alg"] as? String) == "RS256" else { throw AppError.providerAuthFailed }
        let kid = header["kid"] as? String

        let keys = try parseKeys(jwksJSON)
        guard let jwk = keys.first(where: { kid == nil || $0.kid == kid }) ?? keys.first else {
            throw AppError.providerAuthFailed
        }
        let signingInput = Data("\(parts[0]).\(parts[1])".utf8)
        guard verifyRS256(signingInput: signingInput, signature: signature, jwk: jwk) else {
            throw AppError.providerAuthFailed
        }

        guard (payload["iss"] as? String) == issuer else { throw AppError.providerAuthFailed }
        let audOK: Bool = {
            if let aud = payload["aud"] as? String { return aud == clientID }
            if let auds = payload["aud"] as? [String] { return auds.contains(clientID) }
            return false
        }()
        guard audOK else { throw AppError.providerAuthFailed }

        guard let exp = payload["exp"] as? TimeInterval ?? (payload["exp"] as? Int).map(Double.init) else {
            throw AppError.providerAuthFailed
        }
        guard now.timeIntervalSince1970 < exp + 5 else { throw AppError.providerAuthFailed }

        guard let sub = payload["sub"] as? String, !sub.isEmpty else { throw AppError.providerAuthFailed }
        let nonce = payload["nonce"] as? String
        guard nonce == expectedNonce else { throw AppError.providerAuthFailed }

        return Claims(
            subject: sub,
            email: payload["email"] as? String,
            name: payload["name"] as? String,
            nonce: nonce
        )
    }

    private struct JWK {
        let kid: String?
        let n: Data
        let e: Data
    }

    private static func parseKeys(_ data: Data) throws(AppError) -> [JWK] {
        let object: [String: Any]
        do {
            object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        } catch {
            throw AppError.providerAuthFailed
        }
        guard let list = object["keys"] as? [[String: Any]] else { throw AppError.providerAuthFailed }
        return list.compactMap { key in
            guard (key["kty"] as? String) == "RSA",
                  let nString = key["n"] as? String, let n = Data(base64URLEncoded: nString),
                  let eString = key["e"] as? String, let e = Data(base64URLEncoded: eString)
            else { return nil }
            return JWK(kid: key["kid"] as? String, n: n, e: e)
        }
    }

    private static func verifyRS256(signingInput: Data, signature: Data, jwk: JWK) -> Bool {
        var error: Unmanaged<CFError>?
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits as String: jwk.n.count * 8
        ]
        // PKCS#1 RSAPublicKey: SEQUENCE { INTEGER n, INTEGER e }
        guard let keyData = rsaPublicKeyDER(n: jwk.n, e: jwk.e),
              let key = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, &error)
        else { return false }
        return SecKeyVerifySignature(
            key,
            .rsaSignatureMessagePKCS1v15SHA256,
            signingInput as CFData,
            signature as CFData,
            &error
        )
    }

    private static func rsaPublicKeyDER(n: Data, e: Data) -> Data? {
        func integerASN1(_ value: Data) -> Data {
            var bytes = [UInt8](value)
            if let first = bytes.first, first >= 0x80 {
                bytes.insert(0x00, at: 0)
            }
            return asn1(tag: 0x02, content: Data(bytes))
        }
        func asn1(tag: UInt8, content: Data) -> Data {
            var result = Data([tag])
            let length = content.count
            if length < 0x80 {
                result.append(UInt8(length))
            } else if length <= 0xFF {
                result.append(contentsOf: [0x81, UInt8(length)])
            } else {
                result.append(contentsOf: [0x82, UInt8((length >> 8) & 0xFF), UInt8(length & 0xFF)])
            }
            result.append(content)
            return result
        }
        let body = integerASN1(n) + integerASN1(e)
        return asn1(tag: 0x30, content: body)
    }
}
