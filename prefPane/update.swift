// SPDX-FileCopyrightText: Estonian Information System Authority
// SPDX-License-Identifier: LGPL-2.1-or-later

import CryptoTokenKit

#if !NO_CONFIG_MODULE
import config
#endif

@objc public enum UpdateError: Int, Error {
    case invalidSignature = 1000
    case dateLaterThanCurrent = 1001
    case fileNotFound = 1002
    case jsonError = 1004
}

@objc public protocol UpdateDelegate: AnyObject {
    func didFinish(_ error: Error?)
    func message(_ message: String)
    func updateAvailable(_ available: String, filename: URL)
}

open class Update: NSObject, URLSessionDelegate {
    public var delegate: UpdateDelegate?
    @objc public var baseVersion: String? { Update.versionInfo("ee.ria.open-eid") }
    @objc(cert_bundle) public var certBundle: [Data] = []

    private let url: URL
    private let key: SecKey
    private let algorithm: SecKeyAlgorithm
    private let decoder = {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMddHHmmss'Z'"
        df.timeZone = TimeZone(secondsFromGMT: 0)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .formatted(df)
        return decoder
    }()

    @objc
    public init?(delegate: UpdateDelegate?) {
        guard let url = URL(string: CONFIG_URL) else {
            return nil
        }
        let pem = withUnsafeBytes(of: config_ecpub) {
            String(decoding: $0.bindMemory(to: UInt8.self), as: UTF8.self)
        }
        let keyData = Data(base64Encoded: pem
            .replacingOccurrences(of: "-----BEGIN PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----END PUBLIC KEY-----", with: ""), options: .ignoreUnknownCharacters)!
        guard let record = TKBERTLVRecord(from: keyData),
              let eckey = TKBERTLVRecord
            .sequenceOfRecords(from: record.value)?
            .first(where: { $0.tag == 0x03 })?
            .value.dropFirst() else {
            NSLog("Failed to parse key")
            return nil
        }
        let parameters = [
            kSecAttrKeyType: kSecAttrKeyTypeEC,
            kSecAttrKeyClass: kSecAttrKeyClassPublic,
        ]
        var err: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(eckey as CFData, parameters as CFDictionary, &err) else {
            NSLog("Failed to create key: \(String(describing: err))")
            return nil
        }
        guard let attributes = SecKeyCopyAttributes(key) as? [CFString: Any],
            let keySize = attributes[kSecAttrKeySizeInBits] as? Int else {
            NSLog("Failed to get key size")
            return nil
        }
        self.delegate = delegate
        self.key = key
        self.url = url.deletingLastPathComponent()
        switch keySize {
        case 256: algorithm = .ecdsaSignatureMessageX962SHA256
        case 384: algorithm = .ecdsaSignatureMessageX962SHA384
        default:  algorithm = .ecdsaSignatureMessageX962SHA512
        }
    }

    func checkCertificatePinning(_ challenge: URLAuthenticationChallenge) -> Bool {
        guard let serverTrust = challenge.protectionSpace.serverTrust else { return false }
        var error: CFError?
        if !SecTrustEvaluateWithError(serverTrust, &error) {
            NSLog("SecTrustEvaluateWithError \(String(describing: error))")
            //return false
        }

        var trustResult = SecTrustResultType.invalid
        SecTrustGetTrustResult(serverTrust, &trustResult)
        if (trustResult == .unspecified ||
           trustResult == .proceed ||
           trustResult == .recoverableTrustFailure),
           let chain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate],
           let firstCert = chain.first {
            return certBundle.contains(SecCertificateCopyData(firstCert) as Data)
        }
        return false
    }

    @objc(request) public func makeRequest() {
        Task {
            do {
                var request = URLRequest(url: url.appendingPathComponent("config.ecc"), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
                request.addValue(userAgent(diagnostics: true), forHTTPHeaderField: "User-Agent")
                var (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200,
                      !data.isEmpty else {
                    self.delegate?.didFinish(UpdateError.fileNotFound)
                    return
                }
                guard let signature = Data(base64Encoded: data, options: .ignoreUnknownCharacters) else {
                    NSLog("Invalid signature encoding")
                    self.delegate?.didFinish(UpdateError.invalidSignature)
                    return
                }
                request.url = url.appendingPathComponent("config.json")
                (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200,
                      !data.isEmpty else {
                    self.delegate?.didFinish(UpdateError.fileNotFound)
                    return
                }
                await self.receivedData(data: data, signature: signature)
            } catch {
                NSLog("Failed to fetch file \(error)")
                self.delegate?.didFinish(UpdateError.fileNotFound)
            }
        }
    }

    private func receivedData(data: Data, signature: Data) async {
        var error: Unmanaged<CFError>?
        guard SecKeyVerifySignature(key, algorithm, data as CFData, signature as CFData, &error) else {
            NSLog("Verify error: \(error?.takeRetainedValue() as Error?)")
            delegate?.didFinish(UpdateError.invalidSignature)
            return
        }
        let config: Config
        do {
            config = try decoder.decode(Config.self, from: data)
        } catch {
            NSLog("Failed to parse json: \(error)")
            delegate?.didFinish(UpdateError.jsonError)
            return
        }
        guard config.metaInfo.DATE < Date() else {
            NSLog("Failed to parse json: \(config.metaInfo.DATE) < \(Date())")
            delegate?.didFinish(UpdateError.dateLaterThanCurrent)
            return
        }

        NSLog("Config: \(config.metaInfo.SERIAL) \(config.metaInfo.URL) \(config.metaInfo.DATE)")
        certBundle = config.certBundle

        NSLog("Remote version: \(config.osxLatest) base version: \(baseVersion ?? "nil")")
        if config.osxLatest.compare(baseVersion ?? "", options: .numeric) == .orderedDescending {
            delegate?.updateAvailable(config.osxLatest, filename: config.osxDownload)
        }

        if let messageURL = config.updaterMessageURL {
            do {
                var request = URLRequest(url: messageURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
                request.addValue(userAgent(diagnostics: false), forHTTPHeaderField: "User-Agent")
                let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
                let (data, response) = try await session.data(for: request)
                if let httpResponse = response as? HTTPURLResponse,
                   httpResponse.statusCode == 200,
                   let message = String(data: data, encoding: .utf8) {
                    self.delegate?.message(message)
                }
            } catch {
                NSLog("Failed to fetch message \(error)")
            }
        }

        if let message = config.osxMessage {
            NSLog("Message: \(message)", message)
            delegate?.message(message)
        }
        delegate?.didFinish(nil)
    }

    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
            checkCertificatePinning(challenge) {
            completionHandler(.useCredential, URLCredential(trust: challenge.protectionSpace.serverTrust!))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    @objc(userAgent:) public func userAgent(diagnostics: Bool) -> String {
        let os = NSDictionary(contentsOfFile: "/System/Library/CoreServices/SystemVersion.plist") as? [String: Any]
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafeBytes(of: systemInfo.machine) {
            String(cString: $0.bindMemory(to: CChar.self).baseAddress!)
        }
        let devices = TKSmartCardSlotManager.default?.slotNames.joined(separator: "/") ?? ""
        var agent = ["id-updater/\(Update.versionInfo("ee.ria.ID-updater") ?? "0.0.0.0")"]

        if diagnostics, let digidoc4 = Update.versionInfo("ee.ria.qdigidoc4"), !digidoc4.isEmpty {
            agent.append("qdigidoc4/\(digidoc4)")
        }

        let locale = Locale.current.identifier
        agent.append("(Mac OS \(os?["ProductVersion"] as? String ?? "0.0.0") (\(MemoryLayout<UInt>.size * 8)/\(machine)) Locale: \(locale) / UTF-8 Devices: \(devices)")

        return agent.joined(separator: " ")
    }

    static func versionInfo(_ pkg: String) -> String? {
        let list = NSDictionary(contentsOfFile: "/var/db/receipts/\(pkg).plist")
        return list?["PackageVersion"] as? String
    }
}

struct Config: Decodable {
    struct MetaInfo: Decodable {
        let VER: Int
        let SERIAL: Int
        let URL: URL
        let DATE: Date
    }

    let metaInfo: MetaInfo
    let osxDownload: URL
    let osxLatest: String
    let osxMessage: String?
    let updaterMessageURL: URL?
    let certBundle: [Data]

    private enum CodingKeys: String, CodingKey {
        case metaInfo = "META-INF"
        case osxDownload = "OSX-DOWNLOAD"
        case osxLatest = "OSX-LATEST"
        case osxMessage = "OSX-MESSAGE"
        case updaterMessageURL = "UPDATER-MESSAGE-URL"
        case certBundle = "CERT-BUNDLE"
    }
}
