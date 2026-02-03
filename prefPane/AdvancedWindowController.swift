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

import Cocoa
import SwiftUI

struct AdvancedWindowView: View {
    var closeAction: (() -> Void)?
    static let versions = [
        (label: "DigiDoc4", value: "ee.ria.qdigidoc4"),
        (label: "Open-EID", value: "ee.ria.open-eid"),
        (label: "ID-Updater", value: "ee.ria.ID-updater"),
        (label: String(localized: "Safari (Extensions) browser plugin"), value: "ee.ria.safari-token-signing"),
        (label: String(localized: "Safari (NPAPI) browser plugin"), value: "ee.ria.firefox-token-signing"),
        (label: String(localized: "Chrome/Firefox browser plugin"), value: "ee.ria.chrome-token-signing"),
        (label: String(localized: "Chrome browser plugin"), value: "ee.ria.token-signing-chrome"),
        (label: String(localized: "Chrome browser plugin policy"), value: "ee.ria.token-signing-chrome-policy"),
        (label: String(localized: "Firefox browser plugin"), value: "ee.ria.token-signing-firefox"),
        (label: String(localized: "Web-eID native component"), value: "eu.web-eid.web-eid"),
        (label: String(localized: "Safari browser extension (Web-eID)"), value: "eu.web-eid.web-eid-safari"),
        (label: String(localized: "Chrome browser extension (Web-eID)"), value: "eu.web-eid.web-eid-chrome"),
        (label: String(localized: "Chrome browser extension policy (Web-eID)"), value: "eu.web-eid.web-eid-chrome-policy"),
        (label: String(localized: "Firefox browser extension (Web-eID)"), value: "eu.web-eid.web-eid-firefox"),
        (label: String(localized: "PKCS11 loader"), value: "ee.ria.firefox-pkcs11-loader"),
        (label: String(localized: "IDEMIA PKCS11 loader"), value: "com.idemia.awp.xpi"),
        (label: "OpenSC", value: "org.opensc-project.mac"),
        (label: "IDEMIA PKCS11", value: "com.idemia.awp.pkcs11"),
        (label: "EstEID Tokend", value: "ee.ria.esteid-tokend"),
        (label: "EstEID CTK Tokend", value: "ee.ria.esteid-ctk-tokend"),
        (label: "IDEMIA Tokend", value: "com.idemia.awp.tokend"),
    ]
    let text = versions.compactMap { item in
        let list = NSDictionary(contentsOfFile: "/var/db/receipts/\(item.value).plist")
        if let ver = list?["PackageVersion"] as? String {
            return "\(item.label): \(ver)"
        } else {
            return nil
        }
    }.joined(separator: "\n")

    var body: some View {
        VStack {
            Text("Versions installed:")
            TextEditor(text: .constant(text))
                .padding(8)
                .background(Color(.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            HStack {
                Spacer()
                Button("OK") { closeAction?() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
    }
}

public class AdvancedWindowController: NSWindowController {
    @objc public init(parent: NSWindow? = nil) {
        super.init(window: nil)

        let rootView = AdvancedWindowView() { [weak self] in
            guard let window = self?.window,
                let parent = window.sheetParent else { return }
            parent.endSheet(window)
        }

        let popup = NSWindow(contentViewController: NSHostingController(rootView: rootView))
        popup.styleMask = .borderless
        popup.setContentSize(NSSize(width: 400, height: 250))
        self.window = popup

        parent?.beginSheet(popup)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

#Preview {
    AdvancedWindowView()
}
