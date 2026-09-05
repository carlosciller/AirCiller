import Foundation

struct OpenSubtitlesFileIdentity: Equatable, Sendable {
    let hash: String
    let size: UInt64
}

enum OpenSubtitlesFileHasher {
    static let chunkSize = 64 * 1_024
    static let minimumFileSize = chunkSize * 2

    static func identity(for url: URL) throws -> OpenSubtitlesFileIdentity {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let fileSize = try handle.seekToEnd()
        guard fileSize >= UInt64(minimumFileSize) else {
            throw OpenSubtitlesError.fileTooSmall
        }

        try handle.seek(toOffset: 0)
        guard let first = try handle.read(upToCount: chunkSize), first.count == chunkSize else {
            throw OpenSubtitlesError.couldNotReadFile
        }
        try handle.seek(toOffset: fileSize - UInt64(chunkSize))
        guard let last = try handle.read(upToCount: chunkSize), last.count == chunkSize else {
            throw OpenSubtitlesError.couldNotReadFile
        }

        var hash = fileSize
        for data in [first, last] {
            for offset in stride(from: 0, to: data.count, by: 8) {
                var word: UInt64 = 0
                for index in 0..<8 {
                    word |= UInt64(data[offset + index]) << UInt64(index * 8)
                }
                hash &+= word
            }
        }
        return OpenSubtitlesFileIdentity(
            hash: String(format: "%016llx", hash),
            size: fileSize
        )
    }
}

struct OpenSubtitlesSearchResult: Identifiable, Equatable, Sendable {
    let subtitleID: String
    let fileID: Int
    let fileName: String
    let language: String
    let title: String
    let year: Int?
    let release: String
    let downloadCount: Int
    let rating: Double
    let isTrusted: Bool
    let isHearingImpaired: Bool
    let isForced: Bool
    let isMachineTranslated: Bool
    let isAITranslated: Bool
    let isExactFileMatch: Bool

    var id: String { "\(subtitleID)-\(fileID)" }

    var format: String {
        let value = URL(fileURLWithPath: fileName).pathExtension.uppercased()
        return ["SRT", "ASS", "VTT"].contains(value) ? value : "SRT"
    }
}

struct OpenSubtitlesSearchOutcome: Equatable, Sendable {
    let results: [OpenSubtitlesSearchResult]
    let usedExactFileMatch: Bool
}

enum OpenSubtitlesError: LocalizedError, Sendable {
    case notConfigured
    case incompleteAccount
    case fileTooSmall
    case couldNotReadFile
    case invalidResponse
    case unsafeDownloadLink
    case emptySubtitle
    case subtitleTooLarge
    case http(status: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return L10n.text("Configura OpenSubtitles en Ajustes antes de buscar.")
        case .incompleteAccount:
            return L10n.text("Escribe tanto el usuario como la contraseña, o deja ambos vacíos.")
        case .fileTooSmall:
            return L10n.text("El archivo es demasiado pequeño para calcular su huella de OpenSubtitles.")
        case .couldNotReadFile:
            return L10n.text("AirCiller no pudo leer el archivo para buscar subtítulos.")
        case .invalidResponse:
            return L10n.text("OpenSubtitles devolvió una respuesta que AirCiller no pudo interpretar.")
        case .unsafeDownloadLink:
            return L10n.text("OpenSubtitles devolvió un enlace de descarga no seguro.")
        case .emptySubtitle:
            return L10n.text("El subtítulo descargado está vacío o no es válido.")
        case .subtitleTooLarge:
            return L10n.text("El subtítulo supera el límite de seguridad de 10 MB.")
        case .http(let status, let message):
            if status == 401 {
                return L10n.text("OpenSubtitles rechazó la clave o la cuenta.")
            }
            if status == 403 {
                return L10n.text("OpenSubtitles no permite usar esta clave de API.")
            }
            if status == 406 {
                return L10n.text("Se ha alcanzado el límite de descargas o el subtítulo ya no está disponible.")
            }
            if status == 429 {
                return L10n.text("OpenSubtitles está limitando temporalmente las peticiones. Inténtalo más tarde.")
            }
            if status == 503 {
                return L10n.text("OpenSubtitles no está disponible en este momento.")
            }
            if let message, !message.isEmpty {
                return L10n.format("OpenSubtitles devolvió HTTP %lld: %@", Int64(status), message)
            }
            return L10n.format("OpenSubtitles devolvió HTTP %lld.", Int64(status))
        }
    }
}

actor OpenSubtitlesService {
    static let shared = OpenSubtitlesService()

    private static let initialBaseURL = URL(string: "https://api.opensubtitles.com/api/v1")!
    private static let maximumResponseBytes = 2 * 1_024 * 1_024
    private static let maximumSubtitleBytes = 10 * 1_024 * 1_024

    private let credentialStore: OpenSubtitlesCredentialStore
    private let session: URLSession
    private var authorization: Authorization?

    init(
        credentialStore: OpenSubtitlesCredentialStore = OpenSubtitlesCredentialStore(),
        session: URLSession? = nil
    ) {
        self.credentialStore = credentialStore
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 25
            configuration.timeoutIntervalForResource = 60
            configuration.waitsForConnectivity = false
            self.session = URLSession(configuration: configuration)
        }
    }

    func credentials() async throws -> OpenSubtitlesCredentials? {
        try await credentialStore.credentials()
    }

    func saveCredentials(_ credentials: OpenSubtitlesCredentials) async throws {
        let normalized = credentials.normalized
        guard normalized.isConfigured else { throw OpenSubtitlesError.notConfigured }
        guard normalized.username.isEmpty == normalized.password.isEmpty else {
            throw OpenSubtitlesError.incompleteAccount
        }
        try await credentialStore.storeCredentials(normalized)
        authorization = nil
    }

    func removeCredentials() async throws {
        try await credentialStore.removeCredentials()
        authorization = nil
    }

    func testConnection() async throws -> Int? {
        let credentials = try await requiredCredentials()
        let context = try await authorizationContext(for: credentials)
        var request = Self.baseRequest(
            url: context.baseURL.appendingPathComponent("infos/languages"),
            apiKey: credentials.apiKey,
            token: context.token
        )
        request.httpMethod = "GET"
        let response: LanguagesResponse = try await perform(request)
        guard !response.data.isEmpty else { throw OpenSubtitlesError.invalidResponse }
        return context.allowedDownloads
    }

    func search(
        videoURL: URL,
        query: String,
        preferredLanguage: String
    ) async throws -> OpenSubtitlesSearchOutcome {
        let credentials = try await requiredCredentials()
        let context = try await authorizationContext(for: credentials)
        try Task.checkCancellation()
        let identity = try OpenSubtitlesFileHasher.identity(for: videoURL)
        let language = Self.apiLanguageCode(preferredLanguage)
        var exactParameters = [
            "moviebytesize": String(identity.size),
            "moviehash": identity.hash,
            "order_by": "download_count",
            "order_direction": "desc",
        ]
        if !language.isEmpty { exactParameters["languages"] = language }
        let exactResponse = try await search(
            parameters: exactParameters,
            credentials: credentials,
            context: context
        )
        let exactResults = Self.flatten(exactResponse, exactFileMatch: true)
        if !exactResults.isEmpty {
            return OpenSubtitlesSearchOutcome(results: exactResults, usedExactFileMatch: true)
        }

        try Task.checkCancellation()
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQuery.isEmpty else {
            return OpenSubtitlesSearchOutcome(results: [], usedExactFileMatch: false)
        }
        var nameParameters = [
            "order_by": "download_count",
            "order_direction": "desc",
            "query": cleanQuery,
        ]
        if !language.isEmpty { nameParameters["languages"] = language }
        let nameResponse = try await search(
            parameters: nameParameters,
            credentials: credentials,
            context: context
        )
        return OpenSubtitlesSearchOutcome(
            results: Self.flatten(nameResponse, exactFileMatch: false),
            usedExactFileMatch: false
        )
    }

    func searchByName(
        query: String,
        preferredLanguage: String
    ) async throws -> OpenSubtitlesSearchOutcome {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQuery.isEmpty else {
            return OpenSubtitlesSearchOutcome(results: [], usedExactFileMatch: false)
        }
        let credentials = try await requiredCredentials()
        let context = try await authorizationContext(for: credentials)
        let language = Self.apiLanguageCode(preferredLanguage)
        var parameters = [
            "order_by": "download_count",
            "order_direction": "desc",
            "query": cleanQuery,
        ]
        if !language.isEmpty { parameters["languages"] = language }
        let response = try await search(
            parameters: parameters,
            credentials: credentials,
            context: context
        )
        return OpenSubtitlesSearchOutcome(
            results: Self.flatten(response, exactFileMatch: false),
            usedExactFileMatch: false
        )
    }

    func download(_ result: OpenSubtitlesSearchResult) async throws -> URL {
        let credentials = try await requiredCredentials()
        let context = try await authorizationContext(for: credentials)
        let requestedFormat = Self.supportedFormat(for: result.fileName)
        let request = try Self.downloadRequest(
            baseURL: context.baseURL,
            apiKey: credentials.apiKey,
            token: context.token,
            fileID: result.fileID,
            format: requestedFormat
        )
        let response: DownloadResponse = try await perform(request)
        guard Self.isTrustedDownloadURL(response.link) else {
            throw OpenSubtitlesError.unsafeDownloadLink
        }

        var contentRequest = URLRequest(url: response.link)
        contentRequest.httpMethod = "GET"
        contentRequest.timeoutInterval = 60
        contentRequest.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let data: Data
        do {
            let (content, urlResponse) = try await BoundedHTTPResponse.data(
                for: contentRequest, using: session, maximumBytes: Self.maximumSubtitleBytes
            )
            try Self.validate(urlResponse)
            guard let finalURL = urlResponse.url, Self.isTrustedDownloadURL(finalURL) else {
                throw OpenSubtitlesError.unsafeDownloadLink
            }
            data = content
        } catch BoundedHTTPResponse.Failure.tooLarge {
            throw OpenSubtitlesError.subtitleTooLarge
        }
        guard !data.isEmpty, !Self.looksLikeHTML(data) else {
            throw OpenSubtitlesError.emptySubtitle
        }

        let directory = try AirCillerStorage.subtitleCacheDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileName = Self.cachedFileName(
            responseName: response.fileName,
            fallbackName: result.fileName,
            fileID: result.fileID,
            language: result.language,
            requestedFormat: requestedFormat
        )
        let destination = directory.appendingPathComponent(fileName, isDirectory: false)
        try Task.checkCancellation()
        try data.write(to: destination, options: .atomic)
        AirCillerStorage.touchCachedSubtitle(destination)
        _ = try? AirCillerStorage.pruneSubtitleCache()
        return destination
    }

    static func searchRequest(
        baseURL: URL = initialBaseURL,
        apiKey: String,
        token: String? = nil,
        parameters: [String: String]
    ) throws -> URLRequest {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("subtitles"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = parameters.sorted(by: { $0.key < $1.key }).map {
            URLQueryItem(name: $0.key, value: $0.value)
        }
        if let percentEncodedQuery = components?.percentEncodedQuery {
            components?.percentEncodedQuery = percentEncodedQuery.replacingOccurrences(of: "%20", with: "+")
        }
        guard let url = components?.url else { throw OpenSubtitlesError.invalidResponse }
        var request = baseRequest(url: url, apiKey: apiKey, token: token)
        request.httpMethod = "GET"
        return request
    }

    static func downloadRequest(
        baseURL: URL = initialBaseURL,
        apiKey: String,
        token: String? = nil,
        fileID: Int,
        format: String
    ) throws -> URLRequest {
        var request = baseRequest(
            url: baseURL.appendingPathComponent("download"),
            apiKey: apiKey,
            token: token
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["file_id": fileID, "sub_format": format]
        )
        return request
    }

    static func decodeSearchResults(
        from data: Data,
        exactFileMatch: Bool
    ) throws -> [OpenSubtitlesSearchResult] {
        do {
            let response = try JSONDecoder().decode(SearchResponse.self, from: data)
            return flatten(response, exactFileMatch: exactFileMatch)
        } catch {
            throw OpenSubtitlesError.invalidResponse
        }
    }

    private func search(
        parameters: [String: String],
        credentials: OpenSubtitlesCredentials,
        context: AuthorizationContext
    ) async throws -> SearchResponse {
        let request = try Self.searchRequest(
            baseURL: context.baseURL,
            apiKey: credentials.apiKey,
            token: context.token,
            parameters: parameters
        )
        return try await perform(request)
    }

    private func requiredCredentials() async throws -> OpenSubtitlesCredentials {
        guard let credentials = try await credentialStore.credentials()?.normalized,
            credentials.isConfigured
        else {
            throw OpenSubtitlesError.notConfigured
        }
        guard credentials.username.isEmpty == credentials.password.isEmpty else {
            throw OpenSubtitlesError.incompleteAccount
        }
        return credentials
    }

    private func authorizationContext(
        for credentials: OpenSubtitlesCredentials
    ) async throws -> AuthorizationContext {
        guard credentials.hasAccount else {
            return AuthorizationContext(
                baseURL: Self.initialBaseURL,
                token: nil,
                allowedDownloads: nil
            )
        }
        if let authorization,
            authorization.apiKey == credentials.apiKey,
            authorization.username == credentials.username,
            authorization.expiresAt > Date()
        {
            return authorization.context
        }

        let request = try Self.loginRequest(credentials: credentials)
        let response: LoginResponse = try await perform(request)
        let baseURL = Self.validatedAPIBaseURL(response.baseURL) ?? Self.initialBaseURL
        let newAuthorization = Authorization(
            apiKey: credentials.apiKey,
            username: credentials.username,
            token: response.token,
            baseURL: baseURL,
            allowedDownloads: response.user.allowedDownloads,
            expiresAt: Date().addingTimeInterval(11 * 60 * 60)
        )
        authorization = newAuthorization
        return newAuthorization.context
    }

    private func perform<Response: Decodable & Sendable>(
        _ request: URLRequest
    ) async throws -> Response {
        try Task.checkCancellation()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await BoundedHTTPResponse.data(
                for: request, using: session, maximumBytes: Self.maximumResponseBytes
            )
        } catch BoundedHTTPResponse.Failure.tooLarge {
            throw OpenSubtitlesError.invalidResponse
        }
        try Self.validate(response, data: data)
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw OpenSubtitlesError.invalidResponse
        }
    }

    private static func validate(_ response: URLResponse, data: Data? = nil) throws {
        guard let http = response as? HTTPURLResponse else {
            throw OpenSubtitlesError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = data.flatMap { try? JSONDecoder().decode(ErrorResponse.self, from: $0).message }
            throw OpenSubtitlesError.http(status: http.statusCode, message: message)
        }
    }

    private static func baseRequest(url: URL, apiKey: String, token: String?) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "Api-Key")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private static func loginRequest(credentials: OpenSubtitlesCredentials) throws -> URLRequest {
        var request = baseRequest(
            url: initialBaseURL.appendingPathComponent("login"),
            apiKey: credentials.apiKey,
            token: nil
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: [
                "username": credentials.username,
                "password": credentials.password,
            ]
        )
        return request
    }

    private static func flatten(
        _ response: SearchResponse,
        exactFileMatch: Bool
    ) -> [OpenSubtitlesSearchResult] {
        let values = response.data.flatMap { subtitle -> [OpenSubtitlesSearchResult] in
            let attributes = subtitle.attributes
            return (attributes.files ?? []).map { file in
                OpenSubtitlesSearchResult(
                    subtitleID: subtitle.id,
                    fileID: file.fileID,
                    fileName: file.fileName,
                    language: attributes.language ?? "",
                    title: attributes.featureDetails?.title ?? "",
                    year: attributes.featureDetails?.year,
                    release: attributes.release ?? "",
                    downloadCount: attributes.downloadCount ?? 0,
                    rating: attributes.ratings ?? 0,
                    isTrusted: attributes.fromTrusted ?? false,
                    isHearingImpaired: attributes.hearingImpaired ?? false,
                    isForced: attributes.foreignPartsOnly ?? false,
                    isMachineTranslated: attributes.machineTranslated ?? false,
                    isAITranslated: attributes.aiTranslated ?? false,
                    isExactFileMatch: exactFileMatch
                )
            }
        }
        var seen = Set<String>()
        return values.filter { seen.insert($0.id).inserted }.sorted { left, right in
            let leftScore = resultScore(left)
            let rightScore = resultScore(right)
            if leftScore == rightScore {
                return left.fileName.localizedStandardCompare(right.fileName) == .orderedAscending
            }
            return leftScore > rightScore
        }
    }

    private static func resultScore(_ result: OpenSubtitlesSearchResult) -> Int {
        var score = result.isExactFileMatch ? 1_000_000 : 0
        score += result.isTrusted ? 100_000 : 0
        score += result.isMachineTranslated || result.isAITranslated ? -50_000 : 0
        score += min(40_000, max(0, result.downloadCount))
        let rating = result.rating.isFinite ? min(10, max(0, result.rating)) : 0
        score += Int(rating * 100)
        return score
    }

    private static func apiLanguageCode(_ code: String) -> String {
        let base = code.lowercased().split(separator: "-").first.map(String.init) ?? code.lowercased()
        let mapping = [
            "spa": "es", "eng": "en", "cat": "ca", "fra": "fr", "fre": "fr",
            "deu": "de", "ger": "de", "ita": "it", "por": "pt", "jpn": "ja",
            "kor": "ko", "rus": "ru", "nld": "nl", "dut": "nl", "pol": "pl",
            "tur": "tr", "zho": "zh-cn", "chi": "zh-cn",
        ]
        return mapping[base] ?? base
    }

    private static func supportedFormat(for fileName: String) -> String {
        let value = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        return ["srt", "ass", "vtt"].contains(value) ? value : "srt"
    }

    private static func cachedFileName(
        responseName: String,
        fallbackName: String,
        fileID: Int,
        language: String,
        requestedFormat: String
    ) -> String {
        let source = responseName.isEmpty ? fallbackName : responseName
        var base = URL(fileURLWithPath: source).deletingPathExtension().lastPathComponent
        let disallowed = CharacterSet(charactersIn: "/:\u{0}").union(.newlines).union(.controlCharacters)
        base = base.components(separatedBy: disallowed).joined(separator: "-")
        base = String(base.prefix(120)).trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty { base = "subtitle" }
        let languageCode = apiLanguageCode(language)
        let cleanLanguage = (languageCode.isEmpty ? "und" : languageCode)
            .replacingOccurrences(of: "-", with: "_")
        return "online-\(fileID)-\(base).\(cleanLanguage).\(requestedFormat)"
    }

    private static func looksLikeHTML(_ data: Data) -> Bool {
        let prefix = String(decoding: data.prefix(512), as: UTF8.self).lowercased()
        return prefix.contains("<!doctype html") || prefix.contains("<html")
    }

    private static func isTrustedDownloadURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else {
            return false
        }
        return host == "opensubtitles.com" || host.hasSuffix(".opensubtitles.com")
    }

    private static func validatedAPIBaseURL(_ value: String?) -> URL? {
        guard var value, !value.isEmpty else { return nil }
        if !value.hasPrefix("https://") { value = "https://\(value)" }
        guard var components = URLComponents(string: value),
            components.scheme == "https",
            let host = components.host?.lowercased(),
            host == "opensubtitles.com" || host.hasSuffix(".opensubtitles.com")
        else { return nil }
        components.path = "/api/v1"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private static var userAgent: String {
        let version =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0.12"
        return "AirCiller v\(version)"
    }

    private struct Authorization {
        let apiKey: String
        let username: String
        let token: String
        let baseURL: URL
        let allowedDownloads: Int?
        let expiresAt: Date

        var context: AuthorizationContext {
            AuthorizationContext(
                baseURL: baseURL,
                token: token,
                allowedDownloads: allowedDownloads
            )
        }
    }

    private struct AuthorizationContext {
        let baseURL: URL
        let token: String?
        let allowedDownloads: Int?
    }

    private struct SearchResponse: Decodable, Sendable {
        let data: [SubtitleResponse]
    }

    private struct SubtitleResponse: Decodable, Sendable {
        let id: String
        let attributes: SubtitleAttributes
    }

    private struct SubtitleAttributes: Decodable, Sendable {
        let language: String?
        let downloadCount: Int?
        let hearingImpaired: Bool?
        let ratings: Double?
        let fromTrusted: Bool?
        let foreignPartsOnly: Bool?
        let aiTranslated: Bool?
        let machineTranslated: Bool?
        let release: String?
        let featureDetails: FeatureDetails?
        let files: [SubtitleFile]?

        enum CodingKeys: String, CodingKey {
            case language
            case ratings
            case release
            case files
            case downloadCount = "download_count"
            case hearingImpaired = "hearing_impaired"
            case fromTrusted = "from_trusted"
            case foreignPartsOnly = "foreign_parts_only"
            case aiTranslated = "ai_translated"
            case machineTranslated = "machine_translated"
            case featureDetails = "feature_details"
        }
    }

    private struct FeatureDetails: Decodable, Sendable {
        let title: String?
        let year: Int?
    }

    private struct SubtitleFile: Decodable, Sendable {
        let fileID: Int
        let fileName: String

        enum CodingKeys: String, CodingKey {
            case fileID = "file_id"
            case fileName = "file_name"
        }
    }

    private struct LoginResponse: Decodable, Sendable {
        let user: LoginUser
        let baseURL: String?
        let token: String

        enum CodingKeys: String, CodingKey {
            case user
            case token
            case baseURL = "base_url"
        }
    }

    private struct LoginUser: Decodable, Sendable {
        let allowedDownloads: Int?

        enum CodingKeys: String, CodingKey {
            case allowedDownloads = "allowed_downloads"
        }
    }

    private struct DownloadResponse: Decodable, Sendable {
        let link: URL
        let fileName: String

        enum CodingKeys: String, CodingKey {
            case link
            case fileName = "file_name"
        }
    }

    private struct LanguagesResponse: Decodable, Sendable {
        let data: [Language]
    }

    private struct Language: Decodable, Sendable {}

    private struct ErrorResponse: Decodable, Sendable {
        let message: String?
    }
}
