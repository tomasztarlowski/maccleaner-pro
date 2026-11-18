import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case polish
    case english

    var id: String { rawValue }
    var locale: Locale { Locale(identifier: self == .polish ? "pl_PL" : "en_US") }

    var label: String {
        switch self {
        case .polish: return "Polski"
        case .english: return "English"
        }
    }
}

enum ScanProfile: String, CaseIterable, Identifiable {
    case cautious
    case standard
    case aggressive

    var id: String { rawValue }

    func label(_ language: AppLanguage) -> String {
        switch (self, language) {
        case (.cautious, .polish): return "Ostrożny"
        case (.cautious, .english): return "Cautious"
        case (.standard, .polish): return "Standard"
        case (.standard, .english): return "Standard"
        case (.aggressive, .polish): return "Agresywny"
        case (.aggressive, .english): return "Aggressive"
        }
    }

    var largeFileThresholdMB: Int {
        switch self {
        case .cautious: return 1500
        case .standard: return 800
        case .aggressive: return 400
        }
    }
}

struct FileItem: Identifiable, Hashable {
    let id = UUID()
    let path: String
    let size: Int64
    var url: URL { URL(fileURLWithPath: path) }
}

struct DuplicateGroup: Identifiable {
    let id = UUID()
    let hash: String
    let files: [FileItem]
    var totalWaste: Int64 {
        guard files.count > 1 else { return 0 }
        return Int64(files.count - 1) * files[0].size
    }
}

struct LeftoverGroup: Identifiable {
    let id = UUID()
    let appName: String
    let files: [FileItem]
    var totalSize: Int64 { files.reduce(0) { $0 + $1.size } }
}

struct DevJunkGroup: Identifiable {
    let id = UUID()
    let category: String
    let files: [FileItem]
    var totalSize: Int64 { files.reduce(0) { $0 + $1.size } }
}

struct ScanSnapshot: Identifiable, Codable {
    let id: UUID
    let date: Date
    let largeFilesCount: Int
    let duplicateGroupsCount: Int
    let leftoversCount: Int
    let devJunkGroupsCount: Int
    let largeFilesSize: Int64
    let duplicateWaste: Int64
    let leftoversSize: Int64
    let devJunkSize: Int64

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        largeFilesCount: Int,
        duplicateGroupsCount: Int,
        leftoversCount: Int,
        devJunkGroupsCount: Int,
        largeFilesSize: Int64,
        duplicateWaste: Int64,
        leftoversSize: Int64,
        devJunkSize: Int64
    ) {
        self.id = id
        self.date = date
        self.largeFilesCount = largeFilesCount
        self.duplicateGroupsCount = duplicateGroupsCount
        self.leftoversCount = leftoversCount
        self.devJunkGroupsCount = devJunkGroupsCount
        self.largeFilesSize = largeFilesSize
        self.duplicateWaste = duplicateWaste
        self.leftoversSize = leftoversSize
        self.devJunkSize = devJunkSize
    }

    var totalPotentialRecovery: Int64 {
        duplicateWaste + leftoversSize + devJunkSize
    }
}

enum ScanCountUnit {
    case file, group, category, copy

    func label(_ count: Int, language: AppLanguage) -> String {
        let english: (String, String)
        let polish: (String, String, String)
        switch self {
        case .file: (english, polish) = (("file", "files"), ("plik", "pliki", "plików"))
        case .group: (english, polish) = (("group", "groups"), ("grupa", "grupy", "grup"))
        case .category: (english, polish) = (("category", "categories"), ("kategoria", "kategorie", "kategorii"))
        case .copy: (english, polish) = (("copy", "copies"), ("kopia", "kopie", "kopii"))
        }

        let unit: String
        switch language {
        case .english:
            unit = count == 1 ? english.0 : english.1
        case .polish:
            switch (count, count % 10, count % 100) {
            case (1, _, _): unit = polish.0
            case (_, 2...4, 12...14): unit = polish.2
            case (_, 2...4, _): unit = polish.1
            default: unit = polish.2
            }
        }
        return "\(count) \(unit)"
    }
}

extension Int64 {
    func formattedSize(_ language: AppLanguage) -> String {
        if self == 0 { return "0 B" }
        return formatted(.byteCount(style: .file).locale(language.locale))
    }
}
