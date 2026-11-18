import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum ScanSection: String, CaseIterable, Identifiable {
    case overview, largeFiles, duplicates, leftovers, developer, history

    var id: Self { self }

    func title(_ language: AppLanguage) -> String {
        switch (self, language) {
        case (.overview, .polish): "Przegląd"
        case (.overview, .english): "Overview"
        case (.largeFiles, .polish): "Duże pliki"
        case (.largeFiles, .english): "Large files"
        case (.duplicates, .polish): "Duplikaty"
        case (.duplicates, .english): "Duplicates"
        case (.leftovers, .polish): "Pozostałości"
        case (.leftovers, .english): "App leftovers"
        case (.developer, .polish): "Dane deweloperskie"
        case (.developer, .english): "Developer data"
        case (.history, .polish): "Historia"
        case (.history, .english): "History"
        }
    }

    var icon: String {
        switch self {
        case .overview: "internaldrive"
        case .largeFiles: "doc"
        case .duplicates: "square.on.square"
        case .leftovers: "shippingbox"
        case .developer: "hammer"
        case .history: "clock.arrow.circlepath"
        }
    }
}

struct ContentView: View {
    @StateObject private var model = AppViewModel()
    @State private var section: ScanSection? = .overview
    @State private var search = ""
    @State private var scanOptionsOpen = false
    @State private var confirmsTrash = false
    @State private var exportError: String?

    private var currentSection: ScanSection { section ?? .overview }

    var body: some View {
        NavigationSplitView {
            List(ScanSection.allCases, selection: $section) { destination in
                Label(destination.title(model.language), systemImage: destination.icon)
                    .tag(destination)
            }
            .listStyle(.sidebar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Picker(tr("Język", "Language"), selection: $model.language) {
                    ForEach(AppLanguage.allCases) { language in Text(language.label).tag(language) }
                }
                .padding(14)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 215, max: 255)
        } detail: {
            VStack(spacing: 0) {
                workspaceHeader
                Divider()
                switch currentSection {
                case .overview: overview
                case .largeFiles: largeFiles
                case .duplicates: duplicates
                case .leftovers: leftovers
                case .developer: developerData
                case .history: history
                }
                Divider()
                selectionBar
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 850, minHeight: 570)
        .onChange(of: section) { _ in search = "" }
        .alert(tr("Przenieść zaznaczone pliki do Kosza?", "Move selected files to Trash?"), isPresented: $confirmsTrash) {
            Button(tr("Anuluj", "Cancel"), role: .cancel) {}
            Button(tr("Przenieś do Kosza", "Move to Trash"), role: .destructive) {
                model.moveSelectedToTrash()
            }
        } message: {
            Text("\(model.selectedPaths.count) • \(model.totalSelectedSize.formattedSize(model.language))")
        }
        .alert(tr("Nie udało się wyeksportować raportu", "Could not export the report"), isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
    }

    private var workspaceHeader: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(currentSection.title(model.language))
                        .font(.system(size: 27, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text(sectionDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { exportReport() } label: {
                    Label(tr("Eksportuj raport", "Export report"), systemImage: "square.and.arrow.up")
                        .labelStyle(.iconOnly)
                        .frame(width: 24)
                }
                .help(tr("Zapisz raport tekstowy", "Save a text report"))
                .disabled(!model.hasScanResults || model.isScanning)

                Button { model.runFullScan() } label: {
                    Label(tr("Skanuj", "Scan"), systemImage: "magnifyingglass")
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.isScanning)
            }

            HStack(spacing: 9) {
                Image(systemName: "folder").foregroundStyle(.secondary)
                TextField(tr("Folder skanowania", "Scan folder"), text: $model.scanPath)
                    .textFieldStyle(.plain)
                    .font(.system(.callout, design: .monospaced))
                    .accessibilityLabel(tr("Folder skanowania", "Scan folder"))
                    .onSubmit { model.runFullScan() }
                Button(tr("Wybierz…", "Choose…"), action: chooseFolder)
                Divider().frame(height: 17).padding(.horizontal, 2)
                Button { scanOptionsOpen.toggle() } label: {
                    Label(tr("Opcje", "Options"), systemImage: "slider.horizontal.3")
                }
                .popover(isPresented: $scanOptionsOpen, arrowEdge: .bottom) { scanOptions }
            }
            .disabled(model.isScanning)
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.quaternary))
        }
        .padding(.horizontal, 23)
        .padding(.vertical, 18)
    }

    private var scanOptions: some View {
        VStack(alignment: .leading, spacing: 13) {
            Picker(tr("Profil", "Profile"), selection: $model.scanProfile) {
                ForEach(ScanProfile.allCases) { profile in
                    Text(profile.label(model.language)).tag(profile)
                }
            }
            Text(tr("Duże pliki od \(model.minLargeFileMB) MB", "Large files from \(model.minLargeFileMB) MB"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
            Toggle(ScanSection.largeFiles.title(model.language), isOn: $model.scanLargeFilesEnabled)
            Toggle(ScanSection.duplicates.title(model.language), isOn: $model.scanDuplicatesEnabled)
            Toggle(ScanSection.leftovers.title(model.language), isOn: $model.scanLeftoversEnabled)
            Toggle(ScanSection.developer.title(model.language), isOn: $model.scanDevJunkEnabled)
            Text(tr("Pozostałości i dane deweloperskie są sprawdzane w katalogu domowym.", "App leftovers and developer data are scanned in your home folder."))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 287)
    }

    private var sectionDescription: String {
        switch currentSection {
        case .overview: tr("Sprawdź, co zajmuje miejsce na dysku.", "See what is taking up disk space.")
        case .largeFiles: tr("Pliki powyżej progu wybranego do skanowania.", "Files above the chosen scan threshold.")
        case .duplicates: tr("Pliki o identycznej zawartości.", "Files with identical contents.")
        case .leftovers: tr("Możliwe pozostałości. Sprawdź każdy plik przed usunięciem.", "Possible leftovers. Review each file before removing it.")
        case .developer: tr("Pamięci podręczne, dane Docker i pliki symulatorów.", "Caches, Docker data, and simulator files.")
        case .history: tr("Podsumowania ostatnich 30 skanów.", "Summaries of the last 30 scans.")
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                summary(.largeFiles, size: model.largeFiles.reduce(0) { $0 + $1.size }, count: model.largeFiles.count, unit: .file)
                Divider().frame(height: 54)
                summary(.duplicates, size: model.duplicateGroups.reduce(0) { $0 + $1.totalWaste }, count: model.duplicateGroups.count, unit: .group)
                Divider().frame(height: 54)
                summary(.leftovers, size: model.leftoverGroups.reduce(0) { $0 + $1.totalSize }, count: model.leftoverGroups.count, unit: .group)
                Divider().frame(height: 54)
                summary(.developer, size: model.devJunkGroups.reduce(0) { $0 + $1.totalSize }, count: model.devJunkGroups.count, unit: .category)
            }
            .padding(.vertical, 17)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
            .padding(.horizontal, 23)
            .padding(.top, 22)
            .padding(.bottom, 15)

            if model.largeFiles.isEmpty {
                emptyState(
                    symbol: "internaldrive",
                    title: model.hasScanResults ? tr("Brak dużych plików", "No large files") : tr("Rozpocznij od skanu", "Start with a scan"),
                    message: model.hasScanResults
                        ? tr("Pozostałe wyniki znajdziesz w kategoriach powyżej.", "Use the categories above to review other results.")
                        : tr("Wybierz folder i zakres skanowania.", "Choose a folder and what to scan.")
                )
            } else {
                Text(tr("Największe pliki", "Largest files"))
                    .font(.headline)
                    .padding(.horizontal, 23)
                    .padding(.vertical, 12)
                List(Array(model.largeFiles.prefix(12)), id: \.path) { file in fileRow(file) }
                    .listStyle(.inset)
            }
        }
    }

    private func summary(_ destination: ScanSection, size: Int64, count: Int, unit: ScanCountUnit) -> some View {
        Button { section = destination } label: {
            VStack(alignment: .leading, spacing: 7) {
                Label(destination.title(model.language), systemImage: destination.icon)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(model.hasScanResults || count > 0 ? size.formattedSize(model.language) : "—")
                    .font(.title2.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                Text(unit.label(count, language: model.language))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var largeFiles: some View {
        let files = model.largeFiles.filter { matches($0) }
        return searchableResults(isEmpty: files.isEmpty) {
            List(files, id: \.path) { file in fileRow(file) }
        }
    }

    private var duplicates: some View {
        let groups = model.duplicateGroups.filter { group in group.files.contains { matches($0) } }
        return searchableResults(isEmpty: groups.isEmpty) {
            List {
                ForEach(groups) { group in
                    Section {
                        ForEach(group.files.filter { matches($0) }, id: \.path) { file in fileRow(file) }
                    } header: {
                        let copies = ScanCountUnit.copy.label(group.files.count, language: model.language)
                        Text(tr("\(copies) · \(group.totalWaste.formattedSize(model.language)) do odzyskania", "\(copies) · \(group.totalWaste.formattedSize(model.language)) recoverable"))
                    }
                }
            }
        }
    }

    private var leftovers: some View {
        let groups = model.leftoverGroups.filter { group in group.files.contains { matches($0, group: group.appName) } }
        return searchableResults(isEmpty: groups.isEmpty) {
            List {
                ForEach(groups) { group in
                    let files = group.files.filter { matches($0, group: group.appName) }
                    Section {
                        ForEach(files, id: \.path) { file in fileRow(file) }
                    } header: {
                        HStack {
                            Text(group.appName)
                            Spacer()
                            Button(tr("Zaznacz widoczne", "Select visible")) {
                                model.selectedPaths.formUnion(files.map(\.path))
                            }
                            .buttonStyle(.borderless)
                            .disabled(model.isScanning)
                        }
                    }
                }
            }
        }
    }

    private var developerData: some View {
        let groups = model.devJunkGroups.filter { group in group.files.contains { matches($0, group: group.category) } }
        return searchableResults(isEmpty: groups.isEmpty) {
            List {
                ForEach(groups) { group in
                    Section("\(group.category) · \(group.totalSize.formattedSize(model.language))") {
                        ForEach(group.files.filter { matches($0, group: group.category) }, id: \.path) { file in fileRow(file) }
                    }
                }
            }
        }
    }

    private var history: some View {
        Group {
            if model.history.isEmpty {
                emptyState(symbol: "clock", title: tr("Brak skanów w historii", "No scan history"), message: nil)
            } else {
                List(model.history) { scan in
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(scan.date.formatted(.dateTime.day().month(.abbreviated).year().hour().minute().locale(model.language.locale))).font(.headline)
                            let groups = ScanCountUnit.group.label(scan.duplicateGroupsCount, language: model.language)
                            Text(tr("Duże pliki: \(scan.largeFilesCount)  ·  Duplikaty: \(groups)", "Large files: \(scan.largeFilesCount)  ·  Duplicates: \(groups)"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(scan.duplicateWaste.formattedSize(model.language))
                            .font(.callout.monospacedDigit())
                            .help(tr("Rozmiar kopii duplikatów", "Size of extra duplicate copies"))
                    }
                    .padding(.vertical, 6)
                }
                .listStyle(.inset)
            }
        }
    }

    private func searchableResults<Results: View>(isEmpty: Bool, @ViewBuilder results: () -> Results) -> some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(tr("Filtruj według ścieżki", "Filter by path"), text: $search)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 23)
            .padding(.vertical, 11)
            Divider()

            if isEmpty {
                emptyState(
                    symbol: currentSection.icon,
                    title: tr("Brak wyników", "No results"),
                    message: search.isEmpty ? nil : tr("Zmień frazę wyszukiwania.", "Try a different filter.")
                )
            } else {
                results().listStyle(.inset)
            }
        }
    }

    private func fileRow(_ file: FileItem) -> some View {
        HStack(spacing: 11) {
            Toggle(isOn: Binding(
                get: { model.selectedPaths.contains(file.path) },
                set: { _ in model.toggle(file.path) }
            )) { Text(file.url.lastPathComponent) }
                .labelsHidden()
                .toggleStyle(.checkbox)
                .disabled(model.isScanning)

            Image(systemName: "doc").foregroundStyle(.secondary).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(file.url.lastPathComponent).font(.callout.weight(.medium)).lineLimit(1)
                Text(file.url.deletingLastPathComponent().path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(file.size.formattedSize(model.language)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .help(file.path)
        .contextMenu {
            Button(tr("Pokaż w Finderze", "Show in Finder")) {
                NSWorkspace.shared.activateFileViewerSelecting([file.url])
            }
            Button(tr("Kopiuj ścieżkę", "Copy path")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(file.path, forType: .string)
            }
        }
    }

    private func emptyState(symbol: String, title: String, message: String?) -> some View {
        VStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 25, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title).font(.headline)
            if let message {
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var selectionBar: some View {
        HStack(spacing: 9) {
            if model.isScanning { ProgressView().controlSize(.small) }
            VStack(alignment: .leading, spacing: 3) {
                Text("\(tr("Zaznaczone", "Selected")): \(model.selectedPaths.count) · \(model.totalSelectedSize.formattedSize(model.language))")
                    .font(.callout.weight(.medium).monospacedDigit())
                Text(model.status).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(tr("Wyczyść", "Clear")) { model.clearSelection() }
                .disabled(model.selectedPaths.isEmpty || model.isScanning)
            if currentSection == .duplicates {
                Button(tr("Zaznacz kopie", "Select extra copies")) { model.selectRecommended() }
                    .disabled(model.isScanning || model.duplicateGroups.isEmpty)
            }
            Button { confirmsTrash = true } label: {
                Label(tr("Do Kosza…", "Move to Trash…"), systemImage: "trash")
            }
            .disabled(model.selectedPaths.isEmpty || model.isScanning)
        }
        .padding(.horizontal, 23)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func matches(_ file: FileItem, group: String = "") -> Bool {
        search.isEmpty || file.path.localizedCaseInsensitiveContains(search) || group.localizedCaseInsensitiveContains(search)
    }

    private func tr(_ polish: String, _ english: String) -> String {
        model.language == .polish ? polish : english
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.directoryURL = URL(fileURLWithPath: model.scanPath)
        panel.prompt = tr("Wybierz", "Choose")
        panel.begin { response in
            if response == .OK, let folder = panel.url { model.scanPath = folder.path }
        }
    }

    private func exportReport() {
        let panel = NSSavePanel()
        panel.title = tr("Zapisz raport skanowania", "Save scan report")
        panel.nameFieldStringValue = "MacCleanerPro.txt"
        panel.allowedContentTypes = [.plainText]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try model.saveReport(to: url)
            } catch {
                exportError = error.localizedDescription
            }
        }
    }
}
