import FamilyControls
import Foundation

/// The app lists the person picked in Apple's FamilyActivityPicker. iOS only hands out
/// opaque tokens, so the lists are picked once and saved (PLAN.md section 2.1).
enum SelectionKind: String, CaseIterable, Codable {
    /// TikTok, Instagram, X, Reddit, Snapchat and anything else social.
    case social
    /// WhatsApp, Telegram, Messenger, Signal, Discord and so on.
    case messaging
    /// Instagram on its own, only for the "Hide" Instagram strategy (PLAN.md section 6).
    case instagram
}

protocol SelectionStoring: AnyObject {
    func load(_ kind: SelectionKind) -> FamilyActivitySelection
    func save(_ selection: FamilyActivitySelection, as kind: SelectionKind) throws
}

extension FamilyActivitySelection {
    /// True when nothing at all is selected.
    var isEmptySelection: Bool {
        applicationTokens.isEmpty && categoryTokens.isEmpty && webDomainTokens.isEmpty
    }

    /// "3 apps, 1 category, 2 websites"
    var summary: String {
        SelectionSummary.text(apps: applicationTokens.count,
                              categories: categoryTokens.count,
                              websites: webDomainTokens.count)
    }
}

enum SelectionSummary {
    /// iOS shields at most 50 individual apps per store.
    static let maximumApplications = 50

    static func text(apps: Int, categories: Int, websites: Int) -> String {
        func count(_ n: Int, _ singular: String, _ plural: String) -> String? {
            n == 0 ? nil : "\(n) \(n == 1 ? singular : plural)"
        }
        let parts = [count(apps, "app", "apps"),
                     count(categories, "category", "categories"),
                     count(websites, "website", "websites")].compactMap { $0 }
        return parts.isEmpty ? "Nothing selected" : parts.joined(separator: ", ")
    }
}

final class FileSelectionStore: SelectionStoring {
    let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    static func shared() throws -> FileSelectionStore {
        FileSelectionStore(directory: try SharedStorage.directory())
    }

    func fileURL(for kind: SelectionKind) -> URL {
        directory.appendingPathComponent("selection-\(kind.rawValue).json")
    }

    func load(_ kind: SelectionKind) -> FamilyActivitySelection {
        guard let data = try? Data(contentsOf: fileURL(for: kind)),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
            return FamilyActivitySelection()
        }
        return selection
    }

    func save(_ selection: FamilyActivitySelection, as kind: SelectionKind) throws {
        try SharedStorage.write(try JSONEncoder().encode(selection), to: fileURL(for: kind))
    }
}

final class InMemorySelectionStore: SelectionStoring {
    var selections: [SelectionKind: FamilyActivitySelection] = [:]

    func load(_ kind: SelectionKind) -> FamilyActivitySelection {
        selections[kind] ?? FamilyActivitySelection()
    }

    func save(_ selection: FamilyActivitySelection, as kind: SelectionKind) throws {
        selections[kind] = selection
    }
}
