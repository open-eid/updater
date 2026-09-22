/*
 * id-updater
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 *
 */

import Foundation
import Security
import xar

private enum Failure: Error {
    case failedStaging(Error)
    case untrustedDiskImage(String)
    case failedDiskImageVerification(Int32)
    case packageNotFound
    case invalidPackage(String)
    case failedOpenXarArchive(String)
    case missingSignature
    case missingCMSSignature(String)
    case noMatchingCertificate
    case failedCopySignature
    case failedVerifySignature(String)
    case untrustedSigner(String)
}

private final class StagedDiskImage {
    private static let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("id-updater", isDirectory: true)
    private static let mountDirectoryName = "mnt"

    let diskImageURL: URL
    let mountPoint: URL

    private let directory: URL
    private var isKept = false

    init(downloadedURL: URL) throws {
        let directory = Self.root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        self.directory = directory
        diskImageURL = directory.appendingPathComponent("update.dmg")
        mountPoint = directory.appendingPathComponent(Self.mountDirectoryName, isDirectory: true)

        Self.discardPreviousRuns()
        do {
            if !FileManager.default.fileExists(atPath: Self.root.path) {
                try FileManager.default.createDirectory(at: Self.root, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
            }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                            attributes: [.posixPermissions: 0o700])
            try FileManager.default.moveItem(at: downloadedURL, to: diskImageURL)
        } catch {
            // deinit does not run for an initializer that throws.
            Self.discard(directory)
            throw Failure.failedStaging(error)
        }
    }

    deinit {
        guard !isKept else { return }
        Self.discard(directory)
    }

    /// Mounts the image and returns the package it holds.
    func mount() throws -> URL {
        do {
            try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: false,
                                            attributes: [.posixPermissions: 0o700])
        } catch {
            throw Failure.failedStaging(error)
        }
        let status = Self.run("/usr/bin/hdiutil", arguments: [
            "attach",
            "-verify",
            "-readonly",
            "-nobrowse",
            "-noautoopen",
            "-mountpoint",
            mountPoint.path,
            diskImageURL.path,
        ])
        guard status == 0 else {
            throw Failure.failedDiskImageVerification(status)
        }

        let entries: [String]
        do {
            entries = try FileManager.default.contentsOfDirectory(atPath: mountPoint.path)
        } catch {
            throw Failure.invalidPackage("Failed to list disk image: \(error.localizedDescription)")
        }

        let packageNames = entries.filter { $0.hasSuffix(".pkg") }
        guard packageNames.count == 1, let name = packageNames.first else {
            if packageNames.isEmpty {
                throw Failure.packageNotFound
            }
            throw Failure.invalidPackage("Expected one top-level package, found \(packageNames.count)")
        }

        return mountPoint.appendingPathComponent(name)
    }

    func openPackage(_ packageURL: URL) {
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = [packageURL.path]
        task.launch()
        isKept = true
    }

    private static func discardPreviousRuns() {
        for previous in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
            discard(previous)
        }
    }

    private static func discard(_ directory: URL) {
        let mountPoint = directory.appendingPathComponent(mountDirectoryName, isDirectory: true)
        if FileManager.default.fileExists(atPath: mountPoint.path) {
            run("/usr/bin/hdiutil", arguments: ["detach", mountPoint.path])
        }
        try? FileManager.default.removeItem(at: directory)
    }

    @discardableResult
    private static func run(_ path: String, arguments: [String]) -> Int32 {
        let task = Process()
        task.launchPath = path
        task.arguments = arguments
        task.launch()
        task.waitUntilExit()
        return task.terminationStatus
    }
}

@objcMembers
public final class VerifiedPackageInstaller: NSObject {
    private let localizedBundle: Bundle

    @objc(initWithLocalizedBundle:)
    public init(localizedBundle: Bundle) {
        self.localizedBundle = localizedBundle
        super.init()
    }

    @objc(installVerifiedPackageFromDownloadedDiskImage:trustedCertificates:)
    public func installVerifiedPackage(
        fromDownloadedDiskImage downloadedURL: URL,
        trustedCertificates: [Data]
    ) -> String? {
        do {
            let image = try StagedDiskImage(downloadedURL: downloadedURL)
            try verifyDiskImageSignature(image.diskImageURL, trustedCertificates: trustedCertificates)
            let packageURL = try image.mount()
            try verifyPackageSignature(packageURL, trustedCertificates: trustedCertificates)
            image.openPackage(packageURL)
            return nil
        } catch {
            return message(for: error)
        }
    }

    private func installerTeamIdentifiers(in trustedCertificates: [Data]) -> Set<String> {
        Set(trustedCertificates.compactMap { data in
            guard let certificate = SecCertificateCreateWithData(nil, data as CFData),
                  certificate.isDeveloperIDInstaller else {
                return nil
            }
            return certificate.organizationalUnit
        })
    }

    private func verifyDiskImageSignature(_ diskImageURL: URL, trustedCertificates: [Data]) throws {
        let teamIdentifiers = installerTeamIdentifiers(in: trustedCertificates)
        guard !teamIdentifiers.isEmpty else {
            throw Failure.untrustedDiskImage("CERT-BUNDLE contains no Developer ID Installer certificate")
        }

        var code: SecStaticCode?
        var status = SecStaticCodeCreateWithPath(diskImageURL as CFURL, [], &code)
        guard status == errSecSuccess, let code else {
            throw Failure.untrustedDiskImage("SecStaticCodeCreateWithPath: \(status.securityMessage)")
        }

        var requirement: SecRequirement?
        status = SecRequirementCreateWithString("anchor apple generic and notarized" as CFString, [], &requirement)
        guard status == errSecSuccess, let requirement else {
            throw Failure.untrustedDiskImage("SecRequirementCreateWithString: \(status.securityMessage)")
        }

        status = SecStaticCodeCheckValidity(code, [], requirement)
        guard status == errSecSuccess else {
            throw Failure.untrustedDiskImage(status.securityMessage)
        }

        var information: CFDictionary?
        status = SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information)
        guard status == errSecSuccess,
              let signingInformation = information as? [String: Any],
              let teamIdentifier = signingInformation[kSecCodeInfoTeamIdentifier as String] as? String else {
            throw Failure.untrustedDiskImage("SecCodeCopySigningInformation: \(status.securityMessage)")
        }
        guard teamIdentifiers.contains(teamIdentifier) else {
            throw Failure.untrustedDiskImage("Disk image team \(teamIdentifier) signs no certificate in CERT-BUNDLE")
        }
    }

    private func verifyPackageSignature(_ packageURL: URL, trustedCertificates: [Data]) throws {
        guard let archive = xar_open(packageURL.path, 0) else {
            throw Failure.failedOpenXarArchive(packageURL.path)
        }
        defer { xar_close(archive) }

        guard let first = xar_signature_first(archive) else {
            throw Failure.missingSignature
        }

        var types: [String] = []
        var candidate: xar_signature_t? = first
        var cmsSignature: xar_signature_t?
        while let current = candidate {
            let type = xar_signature_type(current).map { String(cString: $0) } ?? "unknown"
            types.append(type)
            if type == "CMS" {
                cmsSignature = current
                break
            }
            candidate = xar_signature_next(current)
        }
        guard let signature = cmsSignature else {
            throw Failure.missingCMSSignature(types.joined(separator: ", "))
        }

        let chain = certificateChain(in: signature)
        guard let signerIndex = chain.firstIndex(where: { certificate in
            trustedCertificates.contains(SecCertificateCopyData(certificate) as Data)
        }) else {
            throw Failure.noMatchingCertificate
        }
        let signerCertificate = chain[signerIndex]

        var signedDataPointer: UnsafeMutablePointer<UInt8>?
        var signatureDataPointer: UnsafeMutablePointer<UInt8>?
        var signedDataSize: UInt32 = 0
        var signatureDataSize: UInt32 = 0
        var offset: off_t = 0
        let err = xar_signature_copy_signed_data(signature,
            &signedDataPointer, &signedDataSize,
            &signatureDataPointer, &signatureDataSize,
            &offset
        )
        guard err == 0,
              let signedDataPointer,
              let signatureDataPointer else {
            throw Failure.failedCopySignature
        }

        let signatureData = Data(bytesNoCopy: signatureDataPointer, count: Int(signatureDataSize), deallocator: .free)
        let signedData = Data(bytesNoCopy: signedDataPointer, count: Int(signedDataSize), deallocator: .free)
        let signingTime = try verifyCMSSignature(signatureData: signatureData, data: signedData, signerCertificate: signerCertificate)
        try requireInstallerSigningTrust(signerCertificate: signerCertificate, chain: chain, verifyDate: signingTime)
    }

    private func verifyCMSSignature(
        signatureData: Data,
        data: Data,
        signerCertificate: SecCertificate
    ) throws -> Date? {
        var decoder: CMSDecoder?
        var status = CMSDecoderCreate(&decoder)
        if status != errSecSuccess { throw Failure.failedVerifySignature("CMSDecoderCreate: \(status.securityMessage)") }
        guard let decoder else { throw Failure.failedVerifySignature("Failed to create CMS decoder") }

        status = signatureData.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return errSecParam }
            return CMSDecoderUpdateMessage(decoder, baseAddress, signatureData.count)
        }
        if status != errSecSuccess { throw Failure.failedVerifySignature("CMSDecoderUpdateMessage: \(status.securityMessage)") }

        status = CMSDecoderFinalizeMessage(decoder)
        if status != errSecSuccess { throw Failure.failedVerifySignature("CMSDecoderFinalizeMessage: \(status.securityMessage)") }

        status = CMSDecoderSetDetachedContent(decoder, data as CFData)
        if status != errSecSuccess { throw Failure.failedVerifySignature("CMSDecoderSetDetachedContent: \(status.securityMessage)") }

        var numSigners: size_t = 0
        status = CMSDecoderGetNumSigners(decoder, &numSigners)
        if status != errSecSuccess { throw Failure.failedVerifySignature("CMSDecoderGetNumSigners: \(status.securityMessage)") }
        if numSigners != 1 { throw Failure.failedVerifySignature("Invalid number of signers: \(numSigners)") }

        // evaluateSecTrust is false: requireInstallerSigningTrust() evaluates the chain
        // with the installer-signing requirements and, when present, the timestamp.
        var signerStatus = CMSSignerStatus.unsigned
        status = CMSDecoderCopySignerStatus(decoder, 0, SecPolicyCreateBasicX509(), false, &signerStatus, nil, nil)
        if status != errSecSuccess { throw Failure.failedVerifySignature("CMSDecoderCopySignerStatus: \(status.securityMessage)") }
        guard signerStatus == .valid else { throw Failure.failedVerifySignature("Invalid signer status: \(signerStatus.rawValue)") }

        var signerCert: SecCertificate?
        status = CMSDecoderCopySignerCert(decoder, 0, &signerCert)
        if status != errSecSuccess { throw Failure.failedVerifySignature("CMSDecoderCopySignerCert: \(status.securityMessage)") }
        guard let signerCert else { throw Failure.failedVerifySignature("Failed to copy signer certificate") }

        guard SecCertificateCopyData(signerCert) as Data == SecCertificateCopyData(signerCertificate) as Data else {
            throw Failure.failedVerifySignature("Signer certificate does not match the certificate bundle")
        }

        var timestamp = CFAbsoluteTime()
        guard CMSDecoderCopySignerTimestamp(decoder, 0, &timestamp) == errSecSuccess else {
            return nil
        }
        return Date(timeIntervalSinceReferenceDate: timestamp)
    }

    private func requireInstallerSigningTrust(
        signerCertificate: SecCertificate,
        chain: [SecCertificate],
        verifyDate: Date?
    ) throws {
        guard signerCertificate.isDeveloperIDInstaller else {
            throw Failure.untrustedSigner("Signer is not a Developer ID Installer certificate")
        }

        let certificates = [signerCertificate] + chain.filter { $0 != signerCertificate }
        var trust: SecTrust?
        let status = SecTrustCreateWithCertificates(certificates as CFArray, SecPolicyCreateBasicX509(), &trust)
        guard status == errSecSuccess, let trust else {
            throw Failure.untrustedSigner("SecTrustCreateWithCertificates: \(status.securityMessage)")
        }
        if let verifyDate {
            SecTrustSetVerifyDate(trust, verifyDate as CFDate)
        }

        var error: CFError?
        guard SecTrustEvaluateWithError(trust, &error) else {
            throw Failure.untrustedSigner(error?.localizedDescription ?? "Trust evaluation failed")
        }
    }

    private func certificateChain(in signature: xar_signature_t) -> [SecCertificate] {
        (0..<xar_signature_get_x509certificate_count(signature)).compactMap { index -> SecCertificate? in
            var size: UInt32 = 0
            var dataPointer: UnsafePointer<UInt8>?
            guard xar_signature_get_x509certificate_data(signature, index, &dataPointer, &size) == 0,
                  let dataPointer else {
                return nil
            }
            let certificateData = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: dataPointer), count: Int(size), deallocator: .none)
            return SecCertificateCreateWithData(nil, certificateData as CFData)
        }
    }

    private func message(for error: Error) -> String {
        guard let failure = error as? Failure else {
            return error.localizedDescription
        }

        switch failure {
        case .failedStaging(let error):
            return error.localizedDescription
        case .untrustedDiskImage(let reason):
            NSLog("Untrusted disk image: %@", reason)
            return localized("Failed to verify signature")
        case .failedDiskImageVerification(let status):
            return "Verify failed, status: \(status)"
        case .packageNotFound:
            return localized("File not found")
        case .invalidPackage(let reason):
            NSLog("Invalid package in disk image: %@", reason)
            return localized("File not found")
        case .failedOpenXarArchive(let path):
            return String(format: localized("Failed to open xar archive: %@"), path)
        case .missingSignature:
            return localized("Failed to copy signature")
        case .missingCMSSignature(let types):
            NSLog("Package has no CMS signature, found: %@", types)
            return localized("Failed to verify signature")
        case .noMatchingCertificate:
            return localized("No matching certificate")
        case .failedCopySignature:
            return localized("Failed to copy signature")
        case .failedVerifySignature(let reason):
            NSLog("Failed to verify signature: %@", reason)
            return localized("Failed to verify signature")
        case .untrustedSigner(let reason):
            NSLog("Untrusted signer: %@", reason)
            return localized("Failed to verify signature")
        }
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: localizedBundle)
    }
}

private extension OSStatus {
    var securityMessage: String {
        SecCopyErrorMessageString(self, nil) as String? ?? "status \(self)"
    }
}

private extension SecCertificate {
    /// DER contents of the Developer ID Installer extended key usage 1.2.840.113635.100.4.13.
    static let developerIDInstallerUsage = Data([0x2a, 0x86, 0x48, 0x86, 0xf7, 0x63, 0x64, 0x04, 0x0d])

    var isDeveloperIDInstaller: Bool {
        var error: Unmanaged<CFError>?
        guard let values = SecCertificateCopyValues(self, [kSecOIDExtendedKeyUsage] as CFArray, &error) as? [String: Any],
              let extendedKeyUsage = values[kSecOIDExtendedKeyUsage as String] as? [String: Any],
              let extendedKeyUsages = extendedKeyUsage[kSecPropertyKeyValue as String] as? [Data] else {
            return false
        }
        return extendedKeyUsages.contains(Self.developerIDInstallerUsage)
    }

    var organizationalUnit: String? {
        var error: Unmanaged<CFError>?
        guard let values = SecCertificateCopyValues(self, [kSecOIDX509V1SubjectName] as CFArray, &error) as? [String: Any],
              let subject = values[kSecOIDX509V1SubjectName as String] as? [String: Any],
              let entries = subject[kSecPropertyKeyValue as String] as? [[String: Any]] else {
            return nil
        }
        let unit = entries.first { $0[kSecPropertyKeyLabel as String] as? String == kSecOIDOrganizationalUnitName as String }
        return unit?[kSecPropertyKeyValue as String] as? String
    }
}
