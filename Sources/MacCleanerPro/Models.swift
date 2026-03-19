import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case polish
    case english

    var id: String { rawValue }

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

    var recommendationThresholdMB: Int {
        switch self {
        case .cautious: return 2500
        case .standard: return 1200
        case .aggressive: return 600
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

extension Int64 {
    var humanSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: self)
    }
}
