// SPDX-FileCopyrightText: Estonian Information System Authority
// SPDX-License-Identifier: LGPL-2.1-or-later

import Foundation
import id_updater_lib

@main
class Updater: UpdateDelegate {
    private let path: String
    private let update: Update

    init?(path: String) {
        self.path = path
        guard let update = Update(delegate: nil) else {
            print("Failed to create update")
            return nil
        }
        self.update = update
        self.update.delegate = self
        print("Installed \(path): \(update.baseVersion ?? "")")
        update.makeRequest()
    }

    static func launch(_ path: String, arguments: [String]) -> Int32 {
        let task = Process()
        task.launchPath = path
        task.arguments = arguments
        task.launch()
        task.waitUntilExit()
        return task.terminationStatus
    }

    static func main() {
        let arguments = CommandLine.arguments
        guard arguments.count == 2 else { 
            print("Usage: \(arguments[0]) [-task | -remove | -daily | -weekly | -monthly]")
            exit(1)
        }

        let directoryPath = ("~/Library/LaunchAgents" as NSString).expandingTildeInPath
        let PATH = directoryPath + "/ee.ria.id-updater.plist"
        let components = Calendar.current.dateComponents([.hour, .minute, .weekday, .day], from: Date())
        let schedule: [String: Any]

        switch arguments[1] {
        case "-task":
            _ = Updater(path: NSString(string: "\(Bundle.main.executablePath ?? arguments[0])/../../..").standardizingPath)
            return RunLoop.main.run()
        case "-remove":
            let result = Updater.launch("/bin/launchctl", arguments: ["unload", "-w", PATH])
            try? FileManager.default.removeItem(atPath: PATH)
            exit(result)
        case "-daily":
            schedule = ["Hour": components.hour!, "Minute": components.minute!]
        case "-weekly":
            schedule = ["Hour": components.hour!, "Minute": components.minute!, "Weekday": components.weekday!]
        case "-monthly":
            schedule = ["Hour": components.hour!, "Minute": components.minute!, "Day": components.day!]
        default:
            print("Invalid argument: \(arguments[1])")
            exit(1)
        }

        let settings: [String: Any] = [
            "Label": "ee.ria.id-updater",
            "ProgramArguments": [arguments[0], "-task"],
            "StartCalendarInterval": schedule
        ]
        let plistData = try? PropertyListSerialization.data(fromPropertyList: settings, format: .xml, options: 0)
        try? FileManager.default.createDirectory(atPath: directoryPath, withIntermediateDirectories: true, attributes: nil)
        FileManager.default.createFile(atPath: PATH, contents: plistData, attributes: nil)
        exit(Updater.launch("/bin/launchctl", arguments: ["load", "-w", PATH]))
    }

    // MARK: - Update Delegate

    func didFinish(_ error: Error?) {
        if let error = error {
            print("Error: \(error.localizedDescription)")
        }
        exit(0)
    }

    func message(_ message: String) {
        print(message)
        _ = Updater.launch("/usr/bin/open", arguments: [path])
    }

    func updateAvailable(_ available: String, filename: URL) {
        print("Update available \(available) \(filename)")
        _ = Updater.launch("/usr/bin/open", arguments: [path])
    }
}
