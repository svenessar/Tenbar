import AppKit
import SwiftUI
import TenbarCore

/// One taskbar entry: a pinned/running app icon (grouped) or a single labeled window.
struct TaskbarItemButton: View {
    let item: TaskbarItem<UUID>
    let windows: [TaskWindow]
    @EnvironmentObject private var tracker: WindowTracker
    @EnvironmentObject private var catalog: AppCatalog
    @State private var showWindowList = false

    var body: some View {
        let focused = windows.contains { tracker.isFrontmost($0) }
        BarButton(
            isActive: focused || showWindowList,
            indicator: windows.isEmpty ? .none : (focused ? .focused : .running),
            help: item.representsApp ? appName : (windows.first?.title ?? appName),
            action: click
        ) {
            if item.representsApp { appIconLabel } else { windowLabel }
        }
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

    private var appIconLabel: some View {
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
        .frame(width: 46)
    }

    private var windowLabel: some View {
        HStack(spacing: 8) {
            iconImage(size: 22)
            Text(windows.first?.title ?? appName).font(.system(size: 11)).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(width: Theme.windowButtonWidth)
        .opacity(windows.first?.isMinimized == true ? 0.6 : 1)
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
            if catalog.pins.contains(item.appKey) {
                Button("Von Taskleiste lösen") { catalog.unpin(appID: item.appKey) }
            } else {
                Button("An Taskleiste anheften") { catalog.pin(appID: item.appKey) }
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
