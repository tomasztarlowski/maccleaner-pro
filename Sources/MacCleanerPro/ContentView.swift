import SwiftUI
import AppKit

enum AppSection: CaseIterable, Identifiable {
    case overview
    case largeFiles
    case duplicates
    case leftovers
    case developer
    case history

    var id: String { String(describing: self) }

    func title(_ lang: AppLanguage) -> String {
        switch (self, lang) {
        case (.overview, .polish): return "Przegląd"
        case (.overview, .english): return "Overview"
        case (.largeFiles, .polish): return "Duże pliki"
        case (.largeFiles, .english): return "Large files"
        case (.duplicates, .polish): return "Duplikaty"
        case (.duplicates, .english): return "Duplicates"
        case (.leftovers, .polish): return "Pozostałości"
        case (.leftovers, .english): return "App leftovers"
        case (.developer, .polish): return "Developer"
        case (.developer, .english): return "Developer"
        case (.history, .polish): return "Historia"
        case (.history, .english): return "History"
        }
    }

    var icon: String {
        switch self {
        case .overview: return "speedometer"
        case .largeFiles: return "externaldrive.badge.exclamationmark"
        case .duplicates: return "doc.on.doc"
        case .leftovers: return "trash"
        case .developer: return "hammer"
        case .history: return "chart.xyaxis.line"
        }
    }
}

struct ContentView: View {
    @StateObject private var vm = AppViewModel()
    @State private var section: AppSection = .overview
    @State private var searchQuery = ""

    private func tr(_ pl: String, _ en: String) -> String {
        vm.language == .polish ? pl : en
    }

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $section) { s in
                Label(s.title(vm.language), systemImage: s.icon).tag(s)
            }
            .navigationTitle("MacCleaner Pro")
        } detail: {
            ZStack {
                LinearGradient(colors: [Color.blue.opacity(0.08), Color.purple.opacity(0.05), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()

                VStack(spacing: 14) {
                    topBar
                    controlBar

                    switch section {
                    case .overview: overviewSection
                    case .largeFiles: largeFilesSection
                    case .duplicates: duplicatesSection
                    case .leftovers: leftoversSection
                    case .developer: developerSection
                    case .history: historySection
                    }

                    footerBar
                }
                .padding(18)
            }
        }
        .frame(minWidth: 1240, minHeight: 790)
    }

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("MacCleaner Pro")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text(tr("Skaner dużych plików, duplikatów, pozostałości i dev-junk", "Large file, duplicate, leftovers and dev-junk scanner"))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                Text("\(tr("Wskaźnik zdrowia", "Health score")): \(vm.cleanupHealthScore)/100")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(vm.cleanupHealthScore > 75 ? .green : vm.cleanupHealthScore > 45 ? .orange : .red)
                statusPill
            }
        }
    }

    private var statusPill: some View {
        HStack(spacing: 8) {
            Circle().fill(vm.isScanning ? Color.orange : Color.green).frame(width: 10, height: 10)
            Text(vm.status).font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }

    private var controlBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(tr("Język", "Language")).font(.caption).foregroundStyle(.secondary)
                    Picker("Language", selection: $vm.language) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.label).tag(lang)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 130, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(tr("Profil czyszczenia", "Cleanup profile")).font(.caption).foregroundStyle(.secondary)
                    Picker("Profil", selection: $vm.scanProfile) {
                        ForEach(ScanProfile.allCases) { profile in
                            Text(profile.label(vm.language)).tag(profile)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 360)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(tr("Folder skanowania", "Scan folder")).font(.caption).foregroundStyle(.secondary)
                    TextField("/Users/...", text: $vm.scanPath)
                        .textFieldStyle(.roundedBorder)
                }

                Spacer()

                Button(vm.isScanning ? tr("Skanowanie…", "Scanning…") : tr("Skanuj teraz", "Scan now")) { vm.runFullScan() }
                    .disabled(vm.isScanning)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }

            HStack(spacing: 12) {
                Toggle("Duże pliki", isOn: $vm.scanLargeFilesEnabled)
                Toggle(tr("Duplikaty", "Duplicates"), isOn: $vm.scanDuplicatesEnabled)
                Toggle("Pozostałości", isOn: $vm.scanLeftoversEnabled)
                Toggle("Developer junk", isOn: $vm.scanDevJunkEnabled)
                Spacer()
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Szukaj po ścieżce...", text: $searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 320)
            }
        }
        .padding(14)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var overviewSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                metricCard(title: "Duże pliki", value: "\(filteredLargeFiles.count)", subtitle: filteredLargeFiles.reduce(0) { $0 + $1.size }.humanSize, icon: "externaldrive.badge.exclamationmark", tint: .blue)
                metricCard(title: "Duplikaty", value: "\(filteredDuplicateGroups.count)", subtitle: filteredDuplicateGroups.reduce(0) { $0 + $1.totalWaste }.humanSize + " do odzyskania", icon: "doc.on.doc", tint: .orange)
                metricCard(title: "Pozostałości", value: "\(filteredLeftoverGroups.count)", subtitle: filteredLeftoverGroups.reduce(0) { $0 + $1.totalSize }.humanSize, icon: "trash", tint: .purple)
                metricCard(title: "Dev Junk", value: "\(filteredDevJunkGroups.count)", subtitle: filteredDevJunkGroups.reduce(0) { $0 + $1.totalSize }.humanSize, icon: "hammer", tint: .pink)
            }

            cardContainer(title: "Rekomendowany odzysk", subtitle: "Na podstawie profilu i rozmiaru") {
                Text(vm.totalPotentialRecovery().humanSize)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
            }

            cardContainer(title: "Największe pliki", subtitle: "Top 12") {
                List(filteredLargeFiles.prefix(12), id: \.path) { row(file: $0) }
                    .listStyle(.inset)
            }
        }
    }

    private var largeFilesSection: some View {
        cardContainer(title: "Duże pliki", subtitle: "Pliki od \(vm.minLargeFileMB) MB") {
            List(filteredLargeFiles, id: \.path) { row(file: $0) }.listStyle(.inset)
        }
    }

    private var duplicatesSection: some View {
        cardContainer(title: "Duplikaty", subtitle: "Identyczne pliki po hashu") {
            List {
                ForEach(filteredDuplicateGroups) { group in
                    Section("Hash: \(group.hash) • odzysk: \(group.totalWaste.humanSize)") {
                        ForEach(group.files, id: \.path) { row(file: $0) }
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private var leftoversSection: some View {
        cardContainer(title: "Pozostałości po aplikacjach", subtitle: "Szybkie pełne usuwanie po grupie") {
            List {
                ForEach(filteredLeftoverGroups) { group in
                    Section {
                        ForEach(group.files, id: \.path) { row(file: $0) }
                    } header: {
                        HStack {
                            Text("\(group.appName) • \(group.totalSize.humanSize)")
                            Spacer()
                            Button("Usuń grupę") { vm.removeLeftoverGroup(group) }
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private var developerSection: some View {
        cardContainer(title: "Developer junk", subtitle: "Docker, Xcode, simulator, cache menedżerów pakietów") {
            List {
                ForEach(filteredDevJunkGroups) { group in
                    Section("\(group.category) • \(group.totalSize.humanSize)") {
                        ForEach(group.files.prefix(80), id: \.path) { row(file: $0) }
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private var historySection: some View {
        cardContainer(title: "Historia skanów", subtitle: "Ostatnie 30 uruchomień") {
            if vm.history.isEmpty {
                Text("Brak historii — uruchom pierwszy skan.")
                    .foregroundStyle(.secondary)
            } else {
                List(vm.history) { s in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(s.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.headline)
                        Text("Potencjalny odzysk: \(s.totalPotentialRecovery.humanSize) • Duże: \(s.largeFilesSize.humanSize) • Dev: \(s.devJunkSize.humanSize)")
                            .foregroundStyle(.secondary)
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var footerBar: some View {
        HStack {
            Text("\(tr("Zaznaczone", "Selected")): \(vm.selectedPaths.count) • \(vm.totalSelectedSize.humanSize)")
                .font(.subheadline.weight(.medium))
            Text("•")
                .foregroundStyle(.secondary)
            Text(tr("Twórca: Tomek + Jarvis", "Created by: Tomek + Jarvis"))
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Eksportuj raport") { exportReport() }
            Button("Wyczyść") { vm.clearSelection() }
            Button(tr("Zaznacz rekomendowane", "Select recommended")) { vm.selectRecommended() }
            Button("Przenieś do Kosza") { vm.moveSelectedToTrash() }
                .disabled(vm.selectedPaths.isEmpty || vm.isScanning)
                .buttonStyle(.borderedProminent)
        }
        .padding(14)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func row(file: FileItem) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { vm.selectedPaths.contains(file.path) },
                set: { _ in vm.toggle(file.path) }
            ))
            .toggleStyle(.checkbox)
            .frame(width: 24)

            Text(file.size.humanSize)
                .font(.system(.body, design: .monospaced))
                .frame(width: 100, alignment: .leading)

            Text(file.path).lineLimit(1).truncationMode(.middle)
            Spacer()
        }
        .contextMenu {
            Button("Pokaż w Finder") { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
            Button("Kopiuj ścieżkę") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(file.path, forType: .string)
            }
        }
    }

    private func metricCard(title: String, value: String, subtitle: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.headline).foregroundStyle(tint)
            Text(value).font(.system(size: 34, weight: .bold, design: .rounded))
            Text(subtitle).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func cardContainer<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.bold())
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            content()
        }
        .padding(14)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var filteredLargeFiles: [FileItem] {
        guard !searchQuery.isEmpty else { return vm.largeFiles }
        return vm.largeFiles.filter { $0.path.localizedCaseInsensitiveContains(searchQuery) }
    }

    private var filteredDuplicateGroups: [DuplicateGroup] {
        guard !searchQuery.isEmpty else { return vm.duplicateGroups }
        return vm.duplicateGroups.compactMap { g in
            let matched = g.files.filter { $0.path.localizedCaseInsensitiveContains(searchQuery) }
            return matched.isEmpty ? nil : DuplicateGroup(hash: g.hash, files: matched)
        }
    }

    private var filteredLeftoverGroups: [LeftoverGroup] {
        guard !searchQuery.isEmpty else { return vm.leftoverGroups }
        return vm.leftoverGroups.compactMap { g in
            let matched = g.files.filter { $0.path.localizedCaseInsensitiveContains(searchQuery) || g.appName.localizedCaseInsensitiveContains(searchQuery) }
            return matched.isEmpty ? nil : LeftoverGroup(appName: g.appName, files: matched)
        }
    }

    private var filteredDevJunkGroups: [DevJunkGroup] {
        guard !searchQuery.isEmpty else { return vm.devJunkGroups }
        return vm.devJunkGroups.compactMap { g in
            let matched = g.files.filter { $0.path.localizedCaseInsensitiveContains(searchQuery) || g.category.localizedCaseInsensitiveContains(searchQuery) }
            return matched.isEmpty ? nil : DevJunkGroup(category: g.category, files: matched)
        }
    }

    private func exportReport() {
        let panel = NSSavePanel()
        panel.title = "Zapisz raport skanowania"
        panel.nameFieldStringValue = "MacCleanerPro-raport.txt"
        panel.allowedContentTypes = [.plainText]

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try vm.saveReport(to: url)
                vm.status = "Raport zapisany ✅"
            } catch {
                vm.status = "Błąd zapisu raportu: \(error.localizedDescription)"
            }
        }
    }
}
