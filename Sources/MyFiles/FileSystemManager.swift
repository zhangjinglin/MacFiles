import Foundation

struct Volume: Hashable, Identifiable {
    let url: URL
    let name: String
    let kind: Kind

    var id: URL { url }

    enum Kind: Int, Hashable, CaseIterable {
        case local = 0
        case external = 1
        case network = 2

        var label: String {
            switch self {
            case .local: "本机磁盘"
            case .external: "外接磁盘"
            case .network: "网络磁盘"
            }
        }

        var symbolName: String {
            switch self {
            case .local: "internaldrive"
            case .external: "externaldrive"
            case .network: "network"
            }
        }
    }
}

enum FileSystemManager {
    static func loadVolumes() async -> [Volume] {
        await Task.detached(priority: .userInitiated) {
            let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsLocalKey, .volumeIsInternalKey]
            guard let urls = FileManager.default.mountedVolumeURLs(
                includingResourceValuesForKeys: keys,
                options: [.skipHiddenVolumes]
            ) else { return [] }

            let volumes: [Volume] = urls.compactMap { url in
                guard let values = try? url.resourceValues(forKeys: Set(keys)),
                      let name = values.volumeName else { return nil }

                let kind: Volume.Kind
                if values.volumeIsLocal == false {
                    kind = .network
                } else if values.volumeIsInternal == true {
                    kind = .local
                } else {
                    kind = .external
                }
                return Volume(url: url, name: name, kind: kind)
            }

            return volumes.sorted {
                if $0.kind != $1.kind { return $0.kind.rawValue < $1.kind.rawValue }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        }.value
    }

    static func items(in directory: URL) async -> (items: [FileItem], errorMessage: String?) {
        await Task.detached(priority: .userInitiated) {
            let keys: Set<URLResourceKey> = [.isDirectoryKey]
            do {
                let urls = try FileManager.default.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: Array(keys),
                    options: [.skipsHiddenFiles]
                )
                let items = urls.map { url -> FileItem in
                    let isDirectory = (try? url.resourceValues(forKeys: keys).isDirectory) ?? false
                    return FileItem(url: url, name: url.lastPathComponent, isDirectory: isDirectory)
                }.sorted {
                    $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                return (items, nil)
            } catch {
                return ([], error.localizedDescription)
            }
        }.value
    }

    static func subdirectories(of directory: URL) async -> [URL] {
        await Task.detached(priority: .userInitiated) {
            let keys: Set<URLResourceKey> = [.isDirectoryKey]
            let urls = (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles]
            )) ?? []
            let directories = urls.filter { url in
                (try? url.resourceValues(forKeys: keys).isDirectory) == true
            }
            return directories.sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            }
        }.value
    }
}
