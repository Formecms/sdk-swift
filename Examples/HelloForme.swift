//
// HelloForme.swift
//
// A minimal SwiftUI example demonstrating the Forme SDK. Copy this file into
// an Xcode project, add the Forme package (https://github.com/Formecms/sdk-swift),
// fill in your API key and base URL, and run.
//
// For production apps: NEVER embed a Secret Key in a published binary. Use
// a Read Key for Delivery API access, or proxy Management API calls through
// your own backend.
//

import Forme
import SwiftUI

@main
struct HelloFormeApp: App {
    var body: some Scene {
        WindowGroup {
            BlogListView()
        }
    }
}

// MARK: - Shared client

enum FormeEnv {
    // Replace with your own values.
    static let readKey = "ce_read_REPLACE_ME"
    static let deliveryURL = URL(string: "https://delivery.forme.sh")!

    static let client = FormeClient(
        apiKey: readKey,
        baseURL: deliveryURL,
        defaultLocale: "en-US"
    )
}

// MARK: - Blog list

struct BlogListView: View {
    @State private var entries: [Entry] = []
    @State private var loadState: LoadState = .loading
    @State private var errorMessage: String?

    enum LoadState {
        case loading, loaded, failed
    }

    var body: some View {
        NavigationStack {
            Group {
                switch loadState {
                case .loading:
                    ProgressView("Loading posts…")
                case .loaded where entries.isEmpty:
                    ContentUnavailableView("No posts yet", systemImage: "tray")
                case .loaded:
                    List(entries, id: \.id) { entry in
                        NavigationLink {
                            BlogDetailView(entry: entry)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(title(of: entry))
                                    .font(.headline)
                                if let slug = entry.fields["slug"]?.stringValue {
                                    Text(slug)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                case .failed:
                    ContentUnavailableView(
                        "Failed to load",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage ?? "Unknown error")
                    )
                }
            }
            .navigationTitle("Blog")
            .task { await load() }
        }
    }

    private func load() async {
        do {
            let result = try await FormeEnv.client.entries.listDelivery(
                contentModelId: "blogPost",
                limit: 20
            )
            entries = result.items
            loadState = .loaded
        } catch {
            errorMessage = error.localizedDescription
            loadState = .failed
        }
    }

    private func title(of entry: Entry) -> String {
        // Title may be a flat string (when ?locale=X was passed) or a locale map.
        if let s = entry.fields["title"]?.stringValue {
            return s
        }
        if let map = entry.fields["title"]?.objectValue,
           let first = map["en-US"]?.stringValue ?? map.values.first?.stringValue {
            return first
        }
        return "Untitled"
    }
}

// MARK: - Blog detail

struct BlogDetailView: View {
    let entry: Entry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let title = entry.fields["title"]?.stringValue
                    ?? entry.fields["title"]?.objectValue?["en-US"]?.stringValue
                {
                    Text(title).font(.largeTitle).fontWeight(.bold)
                }
                if let body = entry.fields["body"]?.stringValue
                    ?? entry.fields["body"]?.objectValue?["en-US"]?.stringValue
                {
                    Text(body)
                }
            }
            .padding()
        }
    }
}
