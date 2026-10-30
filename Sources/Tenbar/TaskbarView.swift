import AppKit
import SwiftUI

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
    @State private var showStartMenu = false

    var body: some View {
        HStack(spacing: 2) {
            startButton
            if !catalog.pinnedApps.isEmpty {
                ForEach(catalog.pinnedApps) { app in
                    PinnedAppButton(app: app, displayID: displayID)
                }
                Rectangle().fill(Color.white.opacity(0.18)).frame(width: 1, height: 26).padding(.horizontal, 4)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(windowsOnDisplay) { window in
                        WindowButton(window: window)
                    }
                }
            }
            if !tracker.hasPermission { permissionButton }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .background(Theme.barBackground)
        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.12)).frame(height: 0.5) }
        .environment(\.colorScheme, .dark)
        .animation(.snappy(duration: 0.15), value: tracker.windows.map(\.id))
        .onChange(of: showStartMenu) { _, isShown in
            if isShown { catalog.rescan() }
        }
    }

    private var windowsOnDisplay: [TaskWindow] {
        tracker.windows.filter { $0.displayID == displayID || ($0.displayID == nil && isPrimary) }
    }

    private var startButton: some View {
        BarButton(isActive: showStartMenu, help: "Start") {
            NSApp.activate()
            showStartMenu.toggle()
        } label: {
            Image(systemName: "square.grid.2x2.fill").font(.system(size: 17)).frame(width: 46)
        }
        .contextMenu {
            Button("Tenbar beenden") { NSApp.terminate(nil) }
        }
        .popover(isPresented: $showStartMenu, arrowEdge: .top) {
            StartMenuView(isPresented: $showStartMenu)
                .environmentObject(catalog)
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

struct WindowButton: View {
    let window: TaskWindow
    @EnvironmentObject private var tracker: WindowTracker
    @EnvironmentObject private var catalog: AppCatalog

    var body: some View {
        let focused = tracker.isFrontmost(window)
        BarButton(isActive: focused, indicator: focused ? .focused : .running, help: window.title) {
            tracker.toggle(window)
        } label: {
            HStack(spacing: 8) {
                if let icon = tracker.icon(for: window.pid) {
                    Image(nsImage: icon).resizable().frame(width: 22, height: 22)
                }
                Text(window.title).font(.system(size: 11)).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(width: Theme.windowButtonWidth)
            .opacity(window.isMinimized ? 0.6 : 1)
        }
        .contextMenu {
            if let bundleID = window.bundleID {
                if catalog.pins.contains(bundleID) {
                    Button("Von Taskleiste lösen") { catalog.unpin(appID: bundleID) }
                } else {
                    Button("An Taskleiste anheften") { catalog.pin(appID: bundleID) }
                }
                Divider()
            }
            Button("Fenster schließen") { tracker.close(window) }
            Button("\(window.appName) beenden") { tracker.quitApp(of: window) }
        }
    }
}

struct PinnedAppButton: View {
    let app: InstalledApp
    let displayID: CGDirectDisplayID
    @EnvironmentObject private var tracker: WindowTracker
    @EnvironmentObject private var catalog: AppCatalog

    var body: some View {
        let windows = tracker.windows.filter { $0.bundleID == app.id }
        let isFocused = windows.contains { tracker.isFrontmost($0) }
        BarButton(isActive: false, indicator: windows.isEmpty ? .none : (isFocused ? .focused : .running), help: app.name) {
            open(windows)
        } label: {
            Image(nsImage: catalog.icon(for: app)).resizable().frame(width: 24, height: 24).frame(width: 44)
        }
        .contextMenu {
            Button("\(app.name) öffnen") { catalog.launch(app) }
            Button("Von Taskleiste lösen") { catalog.unpin(appID: app.id) }
        }
    }

    private func open(_ windows: [TaskWindow]) {
        let here = windows.filter { $0.displayID == displayID }
        let candidates = here.isEmpty ? windows : here
        if let target = candidates.first(where: { tracker.isFrontmost($0) }) ?? candidates.first {
            tracker.toggle(target)
        } else {
            catalog.launch(app)
        }
    }
}
