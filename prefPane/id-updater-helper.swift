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

@main
class Updater: Update, UpdateDelegate, @unchecked Sendable {
    private let path: String

    init(path: String) {
        self.path = path
        super.init()
        delegate = self
        print("Installed \(path): \(self.baseversion ?? "")")
        request()
    }

    static func launch(_ path: String, arguments: [String]) -> Int32 {
        let task = Process()
        task.launchPath = path
        task.arguments = arguments
        task.launch()
        task.waitUntilExit()
        return task.terminationStatus
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

    func updateAvailable(_ available: String, filename: String) {
        print("Update available \(available) \(filename)")
        _ = Updater.launch("/usr/bin/open", arguments: [path])
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
}
