import AppKit
import SwiftUI
import TenbarCore

/// One taskbar entry: a pinned/running app icon (grouped) or a single labeled window.
struct TaskbarItemButton: View {
    let item: TaskbarItem<UUID>
    let windows: [TaskWindow]
    /// Called with the dragged app key when something is dropped onto this item.
    let onDrop: (String) -> Void
    @EnvironmentObject private var tracker: WindowTracker
    @EnvironmentObject private var catalog: AppCatalog
    @State private var showWindowList = false
    @State private var isDropTarget = false

    var body: some View {
        let focused = windows.contains { tracker.isFrontmost($0) }
        BarButton(
            isActive: focused || showWindowList,
            indicator: windows.isEmpty ? .none : (focused ? .focused : .running),
            help: windows.count == 1 ? windows[0].title : appName,
            action: click
        ) {
            if windows.isEmpty || !catalog.showLabels { iconOnlyLabel } else { namedLabel }
        }
        .overlay(alignment: .leading) {
            if isDropTarget { DropMarker().offset(x: -2) }
        }
        .draggable(item.appKey) { iconImage(size: 28) }
        .dropDestination(for: String.self) { keys, _ in
            guard let source = keys.first, source != item.appKey else { return false }
            onDrop(source)
            return true
        } isTargeted: { isDropTarget = $0 }
        .contextMenu { menu }
        .popover(isPresented: $showWindowList, arrowEdge: .top) {
            WindowListView(appName: appName, windows: windows) { showWindowList = false }
                .environmentObject(tracker)
        }
    }

    private var appName: String {
        windows.first?.appName ?? catalog.app(id: item.appKey)?.name ?? item.appKey
    }

    private var icon: NSImage? {
        if let window = windows.first, let icon = tracker.icon(for: window.pid) { return icon }
        return catalog.app(id: item.appKey).map(catalog.icon(for:))
    }

    /// Single window: its title. Several windows: the app name (count shown as badge).
    private var labelText: String {
        windows.count == 1 ? windows[0].title : appName
    }

    private var iconWithBadge: some View {
        ZStack(alignment: .topTrailing) {
            iconImage(size: 24)
            if windows.count > 1 {
                Text("\(windows.count)")
                    .font(.system(size: 8, weight: .bold))
                    .padding(.horizontal, 3).frame(minWidth: 13, minHeight: 13)
                    .background(Color.accentColor, in: Capsule())
                    .offset(x: 7, y: -5)
            }
        }
    }

    private var iconOnlyLabel: some View {
        iconWithBadge
            .frame(width: 46)
            .opacity(allMinimized ? 0.6 : 1)
    }

    private var namedLabel: some View {
        HStack(spacing: 8) {
            iconWithBadge
            Text(labelText).font(.system(size: 11)).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(width: Theme.windowButtonWidth)
        .opacity(allMinimized ? 0.6 : 1)
    }

    private var allMinimized: Bool {
        !windows.isEmpty && windows.allSatisfy(\.isMinimized)
    }

    @ViewBuilder
    private func iconImage(size: CGFloat) -> some View {
        if let icon {
            Image(nsImage: icon).resizable().frame(width: size, height: size)
        } else {
            Image(systemName: "app.dashed").font(.system(size: size * 0.8)).frame(width: size, height: size)
        }
    }

    private func click() {
        switch windows.count {
        case 0:
            catalog.launch(appKey: item.appKey, fallbackName: appName)
        case 1:
            tracker.toggle(windows[0])
        default:
            NSApp.activate()
            showWindowList.toggle()
        }
    }

    @ViewBuilder
    private var menu: some View {
        Button("\(appName) öffnen") { catalog.launch(appKey: item.appKey, fallbackName: appName) }
        if !item.appKey.hasPrefix("pid-") {
            let pinned = catalog.isPinned(item.appKey, to: .taskbar)
            Button(pinned ? "Von Taskleiste lösen" : "An Taskleiste anheften") {
                catalog.togglePin(item.appKey, .taskbar)
            }
        }
        if let first = windows.first {
            Divider()
            if windows.count > 1 {
                Button("Alle Fenster schließen") { tracker.closeAll(windows) }
            } else {
                Button("Fenster schließen") { tracker.close(first) }
            }
            Button("\(appName) beenden") { tracker.quitApp(of: first) }
        }
    }
}

/// Popover listing the windows of a grouped app.
struct WindowListView: View {
    let appName: String
    let windows: [TaskWindow]
    let dismiss: () -> Void
    @EnvironmentObject private var tracker: WindowTracker

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(appName).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 4)
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(windows) { window in row(window) }
                }
            }
            .frame(maxHeight: 420)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 6)
        .frame(width: 300)
        .background(Theme.startMenuBackground)
        .foregroundStyle(.white.opacity(0.94))
        .environment(\.colorScheme, .dark)
    }

    private func row(_ window: TaskWindow) -> some View {
        let isFront = tracker.isFrontmost(window)
        return HStack(spacing: 0) {
            HoverButton(action: {
                dismiss()
                tracker.activate(window)
            }, idleBackground: isFront ? Theme.active : .clear) {
                HStack(spacing: 8) {
                    Image(systemName: window.isMinimized ? "minus.square" : "macwindow")
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).frame(width: 16)
                    Text(window.title).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10).frame(height: 32)
            }
            HoverButton(action: { tracker.close(window) }) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).frame(width: 30, height: 32)
            }
            .help("Fenster schließen")
        }
        .padding(.horizontal, 4)
    }
}
