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

import PreferencePanes
import Security

open class Updater: NSObject {

    @objc(verifyCMSSignature:data:cert:) static public func verifyCMSSignature(signatureData: Data, data: Data, cert: Data) -> Bool {

        func RETURN_IF_OERROR(_ status: OSStatus, _ msg: String) -> Bool {
            guard status == errSecSuccess else {
                NSLog("\(msg) (\(status))")
                return true
            }
            return false
        }

        var decoder: CMSDecoder?
        var status = CMSDecoderCreate(&decoder)
        if RETURN_IF_OERROR(status, "CMSDecoderCreate") { return false }
        guard let decoder else { return false }

        status = signatureData.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return errSecParam }
            return CMSDecoderUpdateMessage(decoder, baseAddress, signatureData.count)
        }
        if RETURN_IF_OERROR(status, "CMSDecoderUpdateMessage") { return false }

        status = CMSDecoderFinalizeMessage(decoder)
        if RETURN_IF_OERROR(status, "CMSDecoderFinalizeMessage") { return false }

        status = CMSDecoderSetDetachedContent(decoder, data as CFData)
        if RETURN_IF_OERROR(status, "CMSDecoderSetDetachedContent") { return false }

        var numSigners: size_t = 0
        status = CMSDecoderGetNumSigners(decoder, &numSigners)
        if RETURN_IF_OERROR(status, "CMSDecoderGetNumSigners") { return false }

        if numSigners != 1 {
            NSLog("Invalid number of signers: \(numSigners)")
            return false
        }

        let policy = SecPolicyCreateBasicX509()
        var signerStatus = CMSSignerStatus.unsigned
        status = CMSDecoderCopySignerStatus(decoder, 0, policy, true, &signerStatus, nil, nil)
        if RETURN_IF_OERROR(status, "CMSDecoderCopySignerStatus") { return false }

        let isValid = signerStatus == CMSSignerStatus.valid

        var signerCert: SecCertificate?
        status = CMSDecoderCopySignerCert(decoder, 0, &signerCert)
        if RETURN_IF_OERROR(status, "CMSDecoderCopySignerCert") { return false }
        guard let signerCert else { return false }

        let signerCertData = SecCertificateCopyData(signerCert) as Data
        let isSameCert = (cert == signerCertData)

        NSLog("Signature is \(isValid) and cert is equal \(isSameCert)")
        return isValid && isSameCert
    }
}
