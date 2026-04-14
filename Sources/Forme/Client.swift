import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Configuration for a `FormeClient`.
public struct FormeConfiguration: Sendable {
    public let apiKey: String
    public let baseURL: URL
    public let defaultLocale: String?
    public let timeoutSeconds: TimeInterval
    public let urlSession: URLSession
    public let extraHeaders: [String: String]

    public init(
        apiKey: String,
        baseURL: URL,
        defaultLocale: String? = nil,
        timeoutSeconds: TimeInterval = 30,
        urlSession: URLSession = .shared,
        extraHeaders: [String: String] = [:]
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.defaultLocale = defaultLocale
        self.timeoutSeconds = timeoutSeconds
        self.urlSession = urlSession
        self.extraHeaders = extraHeaders
    }
}

/// The entry point for the Forme Swift SDK.
///
/// ```swift
/// let client = FormeClient(
///     apiKey: "ce_secret_...",
///     baseURL: URL(string: "https://management.forme.sh")!
/// )
/// let entries = try await client.entries.list(contentModelId: "BlogPost")
/// for entry in entries.items {
///     let title = entry.fields["title"]?.stringValue ?? "Untitled"
///     print(title)
/// }
/// ```
///
/// The client is safe to share across tasks and actors — it holds only
/// immutable configuration and a `URLSession`.
///
/// Read Keys (`ce_read_...`) work only against the Delivery API and should
/// be used for list/get operations on published content. Secret Keys
/// (`ce_secret_...`) unlock the Management API for all CRUD operations.
/// The SDK does not runtime-check the key type — calls that require a
/// specific key type surface any mismatch as a `FormeError.unauthorized`
/// from the server.
public final class FormeClient: Sendable {
    public let configuration: FormeConfiguration
    let executor: RequestExecutor

    public init(configuration: FormeConfiguration, transport: HTTPTransport? = nil) {
        self.configuration = configuration
        self.executor = RequestExecutor(
            baseURL: configuration.baseURL,
            apiKey: configuration.apiKey,
            transport: transport ?? URLSessionTransport(session: configuration.urlSession),
            extraHeaders: configuration.extraHeaders
        )
    }

    /// Convenience initializer for the common case.
    public convenience init(
        apiKey: String,
        baseURL: URL,
        defaultLocale: String? = nil
    ) {
        self.init(
            configuration: FormeConfiguration(
                apiKey: apiKey,
                baseURL: baseURL,
                defaultLocale: defaultLocale
            )
        )
    }

    // MARK: - Namespaces

    public var entries: EntryNamespace { EntryNamespace(client: self) }
    public var contentModels: ContentModelNamespace { ContentModelNamespace(client: self) }
    public var assets: AssetNamespace { AssetNamespace(client: self) }
    public var environments: EnvironmentNamespace { EnvironmentNamespace(client: self) }
    public var locales: LocaleNamespace { LocaleNamespace(client: self) }
    public var workspace: WorkspaceNamespace { WorkspaceNamespace(client: self) }
    public var apiKeys: APIKeyNamespace { APIKeyNamespace(client: self) }
}
