import AppKit
import SwiftUI
import TenbarCore

enum Theme {
    static let barHeight: CGFloat = 46
    static let windowButtonWidth: CGFloat = 168
    static let barBackground = Color(white: 0.07).opacity(0.88)
    static let hover = Color.white.opacity(0.10)
    static let active = Color.white.opacity(0.18)
    static let startMenuBackground = Color(red: 0.12, green: 0.13, blue: 0.15)
}

struct TaskbarView: View {
    let displayID: CGDirectDisplayID
    let isPrimary: Bool
    @EnvironmentObject private var tracker: WindowTracker
    @EnvironmentObject private var catalog: AppCatalog
    @EnvironmentObject private var startMenu: StartMenuController
    @State private var dropAtEnd = false

    private var displayKey: String { stableDisplayKey(displayID) }

    var body: some View {
        let windows = windowsOnDisplay
        let windowsByID = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0) })
        let items = items(for: windows)
        let visibleUnpinned = unpinnedKeys(in: items)
        HStack(spacing: 2) {
            startButton
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(items) { item in
                        TaskbarItemButton(item: item, windows: item.windowIDs.compactMap { windowsByID[$0] }, displayKey: displayKey) { source in
                            catalog.dropOnTaskbar(source, before: item.appKey, display: displayKey, visibleUnpinned: visibleUnpinned)
                        }
                    }
                }
                .overlay(alignment: .trailing) {
                    if dropAtEnd { DropMarker().offset(x: 2) }
                }
            }
            .dropDestination(for: String.self) { keys, _ in
                guard let source = keys.first else { return false }
                catalog.dropOnTaskbar(source, before: nil, display: displayKey, visibleUnpinned: visibleUnpinned)
                return true
            } isTargeted: { dropAtEnd = $0 }
            if !tracker.hasPermission { permissionButton }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .background(Theme.barBackground)
        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.12)).frame(height: 0.5) }
        .environment(\.colorScheme, .dark)
        .animation(.snappy(duration: 0.15), value: items.map(\.id))
    }

    private var windowsOnDisplay: [TaskWindow] {
        tracker.windows.filter { $0.displayID == displayID || ($0.displayID == nil && isPrimary) }
    }

    private func items(for windows: [TaskWindow]) -> [TaskbarItem<UUID>] {
        let running = Set(windows.map(\.appKey))
        // Hide pins whose app is neither installed (catalog not scanned yet / app removed) nor running.
        let pinned = catalog.taskbarPins(display: displayKey).ids.filter { running.contains($0) || catalog.app(id: $0) != nil }
        return TaskbarLayout.items(
            pinnedAppKeys: pinned,
            windows: windows.map { (id: $0.id, appKey: $0.appKey) },
            mode: catalog.combineMode,
            unpinnedOrder: catalog.unpinnedOrder
        )
    }

    private func unpinnedKeys(in items: [TaskbarItem<UUID>]) -> [String] {
        var seen = Set<String>()
        return items.filter { !$0.isPinned && seen.insert($0.appKey).inserted }.map(\.appKey)
    }

    private var startButton: some View {
        BarButton(isActive: startMenu.openDisplayID == displayID, help: "Start") {
            startMenu.toggle(on: displayID)
        } label: {
            Image(systemName: "square.grid.2x2.fill").font(.system(size: 17)).frame(width: 46)
        }
        .contextMenu {
            Picker("Taskleisten-Schaltflächen", selection: $catalog.combineMode) {
                ForEach(CombineMode.allCases) { Text($0.title).tag($0) }
            }
            Toggle("Beschriftungen anzeigen", isOn: $catalog.showLabels)
            Button("Startmenü-Größe zurücksetzen") {
                startMenu.resetSize(forDisplay: displayID)
            }
            Divider()
            Button("Tenbar beenden") { NSApp.terminate(nil) }
        }
    }

    private var permissionButton: some View {
        BarButton(isActive: false, help: "Bedienungshilfen-Zugriff erlauben, damit Tenbar Fenster anzeigen kann") {
            tracker.requestPermission()
        } label: {
            Label("Fensterzugriff erlauben", systemImage: "hand.raised.fill")
                .font(.system(size: 11, weight: .medium)).padding(.horizontal, 10)
        }
    }
}

/// Insertion marker shown while dragging an app over the taskbar or start tiles.
struct DropMarker: View {
    var body: some View {
        Capsule().fill(Color.accentColor).frame(width: 3).padding(.vertical, 6)
    }
}

/// Flat taskbar button with hover/active background and an optional accent underline.
struct BarButton<Label: View>: View {
    var isActive: Bool
    var indicator: Indicator = .none
    var help: String
    var action: () -> Void
    @ViewBuilder var label: () -> Label
    @State private var hovering = false

    enum Indicator { case none, running, focused }

    var body: some View {
        Button(action: action) {
            label()
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .background(isActive ? Theme.active : (hovering ? Theme.hover : .clear))
                .overlay(alignment: .bottom) {
                    switch indicator {
                    case .none: EmptyView()
                    case .running: Rectangle().fill(Color.accentColor.opacity(0.8)).frame(width: 18, height: 2)
                    case .focused: Rectangle().fill(Color.accentColor).frame(height: 2)
                    }
                }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .onHover { hovering = $0 }
        .help(help)
    }
}

