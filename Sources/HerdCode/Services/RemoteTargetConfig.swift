import Foundation

struct RemoteTargetConfig {
    private struct RemoteEntry: Decodable {
        let label: String
        let remote: String
        let session: String
        let herdrPath: String?
    }

    private let fileManager: FileManager
    private let configPath: String

    init(
        fileManager: FileManager = .default,
        configPath: String = "~/.config/herdcode/remotes.json"
    ) {
        self.fileManager = fileManager
        self.configPath = configPath
    }

    func loadTargets() -> [HerdrTarget] {
        let expandedPath = NSString(string: configPath).expandingTildeInPath
        guard fileManager.fileExists(atPath: expandedPath) else {
            return []
        }

        let fileURL = URL(fileURLWithPath: expandedPath)

        guard
            let data = try? Data(contentsOf: fileURL),
            let entries = try? JSONDecoder().decode([RemoteEntry].self, from: data)
        else {
            return []
        }

        return entries.map {
            HerdrTarget(label: $0.label, isLocal: false, remote: $0.remote, session: $0.session, herdrPath: $0.herdrPath)
        }
    }
}
