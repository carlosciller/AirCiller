import Foundation

@main
struct OpenSubtitlesServiceSmokeTest {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AirCiller-OpenSubtitles-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let movie = root.appendingPathComponent("Movie.mkv")
        var data = Data(capacity: OpenSubtitlesFileHasher.minimumFileSize)
        let word = Data([1, 0, 0, 0, 0, 0, 0, 0])
        for _ in 0..<(OpenSubtitlesFileHasher.minimumFileSize / word.count) {
            data.append(word)
        }
        try data.write(to: movie)
        let identity = try OpenSubtitlesFileHasher.identity(for: movie)
        guard
            identity
                == OpenSubtitlesFileIdentity(
                    hash: "0000000000024000",
                    size: UInt64(OpenSubtitlesFileHasher.minimumFileSize)
                )
        else {
            throw NSError(domain: "OpenSubtitlesServiceSmokeTest.Hash", code: 1)
        }

        let search = try OpenSubtitlesService.searchRequest(
            apiKey: "test-key",
            token: "test-token",
            parameters: [
                "query": "My Movie",
                "languages": "es",
                "moviehash": identity.hash,
            ]
        )
        guard
            search.httpMethod == "GET",
            search.value(forHTTPHeaderField: "Api-Key") == "test-key",
            search.value(forHTTPHeaderField: "Authorization") == "Bearer test-token",
            search.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("AirCiller v") == true,
            search.url?.absoluteString.contains("languages=es") == true,
            search.url?.absoluteString.contains("moviehash=0000000000024000") == true,
            search.url?.absoluteString.contains("query=My+Movie") == true
        else {
            throw NSError(domain: "OpenSubtitlesServiceSmokeTest.SearchRequest", code: 2)
        }

        let download = try OpenSubtitlesService.downloadRequest(
            apiKey: "test-key",
            fileID: 123,
            format: "ass"
        )
        let body = try JSONSerialization.jsonObject(with: download.httpBody ?? Data()) as? [String: Any]
        guard
            download.httpMethod == "POST",
            download.value(forHTTPHeaderField: "Content-Type") == "application/json",
            body?["file_id"] as? Int == 123,
            body?["sub_format"] as? String == "ass"
        else {
            throw NSError(domain: "OpenSubtitlesServiceSmokeTest.DownloadRequest", code: 3)
        }

        let response = Data(
            """
            {
              "data": [
                {
                  "id": "456",
                  "attributes": {
                    "language": "es",
                    "download_count": 900,
                    "hearing_impaired": true,
                    "ratings": 8.5,
                    "from_trusted": true,
                    "foreign_parts_only": false,
                    "ai_translated": null,
                    "machine_translated": false,
                    "release": "Example.WEB-DL",
                    "feature_details": { "title": "Example", "year": 2026 },
                    "files": [
                      { "file_id": 789, "file_name": "Example.es.ass" }
                    ]
                  }
                }
              ]
            }
            """.utf8
        )
        let decoded = try OpenSubtitlesService.decodeSearchResults(
            from: response,
            exactFileMatch: true
        )
        guard
            decoded.count == 1,
            decoded[0].fileID == 789,
            decoded[0].format == "ASS",
            decoded[0].isExactFileMatch,
            decoded[0].isTrusted,
            decoded[0].isHearingImpaired,
            decoded[0].release == "Example.WEB-DL"
        else {
            throw NSError(domain: "OpenSubtitlesServiceSmokeTest.Decode", code: 4)
        }

        let missingSubtitleExtension = OpenSubtitlesSearchResult(
            subtitleID: "456",
            fileID: 790,
            fileName: "Example.1080p.BluRay.x264",
            language: "en",
            title: "Example",
            year: 2026,
            release: "Example.1080p.BluRay.x264",
            downloadCount: 1,
            rating: 0,
            isTrusted: false,
            isHearingImpaired: false,
            isForced: false,
            isMachineTranslated: false,
            isAITranslated: false,
            isExactFileMatch: false
        )
        guard missingSubtitleExtension.format == "SRT" else {
            throw NSError(domain: "OpenSubtitlesServiceSmokeTest.UnknownExtension", code: 5)
        }

        print("OpenSubtitles file hash, REST requests, and result decoding: OK")
    }
}
