import SwiftUI

struct PanelView: View {
  @ObservedObject var viewModel: HistoryViewModel
  @FocusState private var searchFocused: Bool
  @State private var showSettings = false

  var body: some View {
    VStack(spacing: 0) {
      searchField
      Divider()
      if viewModel.visible.isEmpty {
        emptyState
      } else {
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(Array(viewModel.visible.enumerated()), id: \.element.id) { index, item in
              HistoryRow(item: item, isSelected: index == viewModel.selectedIndex)
                .contentShape(Rectangle())
                .onTapGesture {
                  viewModel.selectedIndex = index
                  let wantsPaste = NSEvent.modifierFlags.contains(.option)
                  viewModel.copySelected(paste: wantsPaste)
                }
            }
          }
        }
      }
      Divider()
      footer
    }
    .frame(minWidth: 440, idealWidth: 460, minHeight: 420, idealHeight: 560)
    .onAppear {
      searchFocused = true
      viewModel.onDismiss = { PanelController.shared.closePanel() }
    }
    .sheet(isPresented: $showSettings) {
      SettingsView()
    }
  }

  private var searchField: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass").foregroundColor(.secondary)
      TextField("Suchen…", text: $viewModel.search)
        .textFieldStyle(.plain)
        .focused($searchFocused)
      if !viewModel.search.isEmpty {
        Button {
          viewModel.search = ""
        } label: {
          Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
      }
    }
    .padding(10)
  }

  private var emptyState: some View {
    VStack(spacing: 8) {
      Image(systemName: "tray")
        .font(.system(size: 34))
        .foregroundColor(.secondary)
      Text("Keine Einträge")
        .foregroundColor(.secondary)
      Text("Kopiere etwas – es erscheint hier (verschlüsselt).")
        .font(.caption)
        .foregroundColor(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var footer: some View {
    HStack(spacing: 12) {
      Text("⏎ Kopieren · ⌥⏎ Einfügen · ⌥P Pin · ⌘⌫ Löschen")
        .font(.caption)
        .foregroundColor(.secondary)
      Spacer()
      Button {
        viewModel.clearUnpinned()
      } label: {
        Image(systemName: "trash")
      }
      .buttonStyle(.plain)
      .help("Ungepinnte Einträge löschen")
      Button {
        showSettings = true
      } label: {
        Image(systemName: "gearshape")
      }
      .buttonStyle(.plain)
      .help("Einstellungen")
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
  }
}

struct HistoryRow: View {
  let item: DisplayItem
  let isSelected: Bool

  private static let formatter: RelativeDateTimeFormatter = {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .abbreviated
    return f
  }()

  private var kindIcon: String {
    switch item.kind {
    case .text: return "doc.text"
    case .richText: return "doc.richtext"
    case .image: return "photo"
    case .file: return "doc.badge.ellipsis"
    }
  }

  var body: some View {
    HStack(spacing: 10) {
      if item.pinned {
        Image(systemName: "pin.fill")
          .font(.caption)
          .foregroundColor(.orange)
      }
      Image(systemName: kindIcon)
        .foregroundColor(.secondary)
        .frame(width: 18)
      VStack(alignment: .leading, spacing: 2) {
        Text(item.preview)
          .lineLimit(2)
          .font(.system(size: 13))
        HStack(spacing: 8) {
          if let source = item.sourceApp {
            Text(source).foregroundColor(.secondary)
          }
          if item.copies > 1 {
            Text("×\(item.copies)").foregroundColor(.secondary)
          }
          Text(Self.formatter.localizedString(for: item.lastUsed, relativeTo: Date()))
            .foregroundColor(.secondary)
        }
        .font(.caption2)
      }
      Spacer()
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .background(isSelected ? Color.accentColor.opacity(0.25) : Color.clear)
    .contentShape(Rectangle())
  }
}

// MARK: - Einstellungen

struct SettingsView: View {
  @Environment(\.dismiss) private var dismiss

  @State private var historySize = AppSettings.historySize
  @State private var interval = AppSettings.checkInterval
  @State private var pasteByDefault = AppSettings.pasteByDefault
  @State private var clearOnQuit = AppSettings.clearOnQuit
  @State private var searchMode = AppSettings.searchMode

  @State private var ignoredApps = AppSettings.ignoredApps
  @State private var newApp = ""

  @State private var regexes = AppSettings.ignoreRegexes
  @State private var newRegex = ""
  @State private var regexError = ""

  @State private var accessibilityTrusted = PasteSupport.isTrusted()

  var body: some View {
    VStack(spacing: 0) {
      Form {
        Section("Historie") {
          Stepper(value: $historySize, in: 1...999) {
            Text("Maximale Einträge: \(historySize)")
          }
          .onChange(of: historySize) { AppSettings.setHistorySize($0) }
          Stepper(value: $interval, in: 0.2...5.0, step: 0.1) {
            Text("Abfrage-Intervall: \(interval, specifier: "%.1f") s")
          }
          .onChange(of: interval) { AppSettings.setCheckInterval($0) }
          Toggle("Beim Beenden löschen", isOn: $clearOnQuit)
            .onChange(of: clearOnQuit) { AppSettings.clearOnQuit = $0 }
        }

        Section("Verhalten") {
          Toggle("Nach Auswahl automatisch einfügen", isOn: $pasteByDefault)
            .onChange(of: pasteByDefault) { AppSettings.pasteByDefault = $0 }
          Picker("Suchmodus", selection: $searchMode) {
            ForEach(SearchMode.allCases, id: \.self) { Text($0.rawValue) }
          }
          .onChange(of: searchMode) { AppSettings.setSearchMode($0) }
        }

        Section("Ignorierte Apps (Bundle-IDs)") {
          ForEach(ignoredApps, id: \.self) { app in
            HStack {
              Text(app)
              Spacer()
              Button("Entfernen") {
                ignoredApps.removeAll { $0 == app }
                AppSettings.ignoredApps = ignoredApps
              }
            }
          }
          HStack {
            TextField("com.example.app", text: $newApp)
            Button("Hinzufügen") {
              let trimmed = newApp.trimmingCharacters(in: .whitespaces)
              guard !trimmed.isEmpty else { return }
              ignoredApps.append(trimmed)
              AppSettings.ignoredApps = ignoredApps
              newApp = ""
            }
          }
        }

        Section("Ignorierte Muster (Regex, validiert)") {
          ForEach(regexes, id: \.self) { pattern in
            HStack {
              Text(pattern).font(.system(size: 12, design: .monospaced))
              Spacer()
              Button("Entfernen") {
                regexes.removeAll { $0 == pattern }
                AppSettings.ignoreRegexes = regexes
              }
            }
          }
          HStack {
            TextField("z. B. ^\\d{16}$", text: $newRegex)
              .onSubmit(addRegex)
            Button("Hinzufügen", action: addRegex)
          }
          if !regexError.isEmpty {
            Text(regexError).font(.caption).foregroundColor(.red)
          }
        }

        Section("Sicherheit") {
          HStack {
            Label("Historie AES-256-GCM-verschlüsselt", systemImage: "lock.fill")
            Spacer()
            Text("aktiv").foregroundColor(.green)
          }
          HStack {
            Label("Bedienungshilfen für Einfügen", systemImage: "hand.raised")
            Spacer()
            if accessibilityTrusted {
              Text("erteilt").foregroundColor(.green)
            } else {
              Button("Freigeben…") {
                _ = PasteSupport.promptIfNotTrusted()
              }
            }
          }
          Button("Verlauf jetzt leeren (inkl. angepinnter)") {
            HistoryStore.shared.clearAll(keepPinned: false)
          }
          .foregroundColor(.red)
        }
      }
      .formStyle(.grouped)

      HStack {
        Spacer()
        Button("Fertig") { dismiss() }
          .keyboardShortcut(.defaultAction)
      }
      .padding(12)
    }
    .frame(width: 520, height: 620)
  }

  /// Fix für den Maccy-Settings-Bug: Hinzufügen nur mit gültigem,
  /// nicht-leerem Muster; ungültige werden abgelehnt und angezeigt.
  private func addRegex() {
    let pattern = newRegex.trimmingCharacters(in: .whitespaces)
    guard !pattern.isEmpty else {
      regexError = "Leeres Muster ist nicht erlaubt."
      return
    }
    guard AppSettings.validateRegex(pattern) else {
      regexError = "Ungültiger Regex – wurde nicht gespeichert."
      return
    }
    regexError = ""
    regexes.append(pattern)
    AppSettings.ignoreRegexes = regexes
    newRegex = ""
  }
}
