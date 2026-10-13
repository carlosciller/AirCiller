import Foundation

struct SeasonFolderScan: Sendable {
    let movies: [URL]
    let unreadablePaths: [String]
    let inspectedFiles: Int
}

/// On-demand enumeration only; symbolic-link directories are not traversed.
enum SeasonFolderImporter {
    static func scan(
        _ directory: URL,
        progress: @Sendable (Int) -> Void = { _ in }
    ) throws -> SeasonFolderScan {
        try Task.checkCancellation()
        let manager = FileManager.default
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        let root = try directory.resourceValues(forKeys: keys)
        guard root.isDirectory == true else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        var movies: [URL] = []
        var unreadable: [String] = []
        var inspected = 0
        func visit(_ folder: URL) throws {
            try Task.checkCancellation()
            let children: [URL]
            do {
                children = try manager.contentsOfDirectory(
                    at: folder, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
            } catch {
                unreadable.append(folder.path)
                return
            }
            for child in children {
                try Task.checkCancellation()
                inspected += 1
                if inspected % 64 == 0 { progress(inspected) }
                do {
                    let values = try child.resourceValues(forKeys: keys)
                    if values.isDirectory == true {
                        if values.isSymbolicLink != true { try visit(child) }
                    } else if values.isRegularFile == true,
                        MediaFileTypes.accepts(child)
                    {
                        if manager.isReadableFile(atPath: child.path) {
                            movies.append(child.standardizedFileURL)
                        } else {
                            unreadable.append(child.path)
                        }
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    unreadable.append(child.path)
                }
            }
        }
        try visit(directory)
        try Task.checkCancellation()
        movies.sort {
            let comparison = $0.path.localizedStandardCompare($1.path)
            return comparison == .orderedSame ? $0.path < $1.path : comparison == .orderedAscending
        }
        progress(inspected)
        return SeasonFolderScan(movies: movies, unreadablePaths: unreadable, inspectedFiles: inspected)
    }
}
