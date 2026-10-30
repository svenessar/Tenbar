import AppKit
import SwiftUI
import TenbarCore

struct StartMenuView: View {
    @Binding var isPresented: Bool
    let displayID: CGDirectDisplayID
    @EnvironmentObject private var catalog: AppCatalog
    @State private var dropTargetTile: String?
    @State private var size: StartMenuSize?
    @State private var dragStart: (mouse: NSPoint, size: StartMenuSize)?

    var body: some View {
        let size = currentSize
        HStack(spacing: 0) {
            rail
            allApps.frame(width: size.allAppsWidth)
            pinned.frame(width: size.pinnedWidth)
                .overlay(alignment: .leading) { splitHandle }
        }
        .frame(height: size.height)
        .overlay(alignment: .topTrailing) { cornerHandle }
        .background(Theme.startMenuBackground)
        .foregroundStyle(.white.opacity(0.94))
        .environment(\.colorScheme, .dark)
        .transaction { $0.animation = nil }
    }

    // MARK: Size

    private var displayKey: String { stableDisplayKey(displayID) }

    private var screenLimits: (width: Double, height: Double) {
        guard let screen = NSScreen.with(displayID: displayID) else { return (1600, 1000) }
        return (screen.frame.width - 16, screen.frame.height - Theme.barHeight - 32)
    }

    private var currentSize: StartMenuSize {
        let limits = screenLimits
        return (size ?? catalog.startMenuSize(forDisplay: displayKey))
            .clamped(maxTotalWidth: limits.width, maxHeight: limits.height)
    }

    /// Tracks the drag in screen coordinates, because the popover window itself moves while resizing.
    private func resizeGesture(_ apply: @escaping (_ start: StartMenuSize, _ dx: Double, _ dy: Double) -> StartMenuSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { _ in
                let mouse = NSEvent.mouseLocation
                if dragStart == nil { dragStart = (mouse, currentSize) }
                guard let start = dragStart else { return }
                size = apply(start.size, mouse.x - start.mouse.x, mouse.y - start.mouse.y)
            }
            .onEnded { _ in
                dragStart = nil
                catalog.setStartMenuSize(currentSize, forDisplay: displayKey)
            }
    }

    private static var cornerCursor: NSCursor {
        if #available(macOS 15.0, *) { return .frameResize(position: .topRight, directions: .all) }
        return .crosshair
    }

    private var cornerHandle: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 9, weight: .semibold))
            .rotationEffect(.degrees(90))
            .foregroundStyle(.white.opacity(0.45))
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { Self.cornerCursor.push() } else { NSCursor.pop() }
            }
            .gesture(resizeGesture { start, dx, dy in
                let limits = screenLimits
                return start.resized(width: dx, height: dy, maxTotalWidth: limits.width, maxHeight: limits.height)
            })
            .help("Ziehen, um Höhe und Breite des Startmenüs zu ändern")
    }

    private var splitHandle: some View {
        Rectangle()
            .fill(Color.white.opacity(dragStart == nil ? 0.06 : 0.25))
            .frame(width: 1)
            .frame(width: 8)
            .contentShape(Rectangle())
            .offset(x: -4)
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(resizeGesture { start, dx, _ in start.splitMoved(by: dx) })
            .help("Ziehen, um die Breite von „Alle Apps“ und „Angeheftet“ zu verteilen")
    }

    private var rail: some View {
        VStack(spacing: 4) {
            Spacer()
            Image(systemName: "person.crop.circle").font(.system(size: 16)).frame(width: 40, height: 36)
                .help(NSFullUserName())
            Menu {
                ForEach(PowerAction.allCases) { action in
                    Button { run(action) } label: { Label(action.title, systemImage: action.symbol) }
                }
                Divider()
                Button("Tenbar beenden") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "power").font(.system(size: 16))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 40, height: 36)
            .help("Ein/Aus")
        }
        .padding(.vertical, 8)
        .frame(width: 48)
        .frame(maxHeight: .infinity)
        .background(Color.black.opacity(0.18))
    }

    private var allApps: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("Alle Apps")
            if catalog.apps.isEmpty {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(catalog.apps) { app in appRow(app) }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
    }

    private var pinned: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("Angeheftet")
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 6)], spacing: 6) {
                    ForEach(catalog.startPinnedApps) { app in tile(app) }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            .dropDestination(for: String.self) { keys, _ in
                guard let source = keys.first else { return false }
                catalog.dropOnStart(source, before: nil)
                return true
            }
            if !catalog.statusMessage.isEmpty {
                Text(catalog.statusMessage).font(.system(size: 10)).foregroundStyle(.secondary)
                    .lineLimit(4).padding(12)
            }
        }
        .background(Color.white.opacity(0.03))
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 8)
    }

    private func appRow(_ app: InstalledApp) -> some View {
        HoverButton(action: { launch(app) }) {
            HStack(spacing: 10) {
                Image(nsImage: catalog.icon(for: app)).resizable().frame(width: 24, height: 24)
                Text(app.name).font(.system(size: 12)).lineLimit(1)
                Spacer(minLength: 0)
                if catalog.isPinned(app.id, to: .start) {
                    Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(.horizontal, 12).frame(height: 34)
        }
        .draggable(app.id) { dragPreview(app) }
        .contextMenu { pinMenu(app) }
    }

    private func tile(_ app: InstalledApp) -> some View {
        HoverButton(action: { launch(app) }, idleBackground: Color.white.opacity(0.07)) {
            VStack(spacing: 6) {
                Image(nsImage: catalog.icon(for: app)).resizable().frame(width: 32, height: 32)
                Text(app.name).font(.system(size: 10)).lineLimit(1).padding(.horizontal, 4)
            }
            .frame(maxWidth: .infinity, minHeight: 72)
        }
        .overlay(alignment: .leading) {
            if dropTargetTile == app.id { DropMarker().offset(x: -4) }
        }
        .draggable(app.id) { dragPreview(app) }
        .dropDestination(for: String.self) { keys, _ in
            guard let source = keys.first else { return false }
            catalog.dropOnStart(source, before: app.id)
            return true
        } isTargeted: { targeted in
            if targeted { dropTargetTile = app.id } else if dropTargetTile == app.id { dropTargetTile = nil }
        }
        .contextMenu { pinMenu(app) }
    }

    private func dragPreview(_ app: InstalledApp) -> some View {
        Image(nsImage: catalog.icon(for: app)).resizable().frame(width: 32, height: 32)
    }

    @ViewBuilder
    private func pinMenu(_ app: InstalledApp) -> some View {
        Button(catalog.isPinned(app.id, to: .start) ? "Von Start lösen" : "An Start anheften") {
            catalog.togglePin(app.id, .start)
        }
        Button(catalog.isPinned(app.id, to: .taskbar(display: displayKey)) ? "Von Taskleiste lösen" : "An Taskleiste anheften") {
            catalog.togglePin(app.id, .taskbar(display: displayKey))
        }
    }

    private func launch(_ app: InstalledApp) {
        isPresented = false
        catalog.launch(app)
    }

    private func run(_ action: PowerAction) {
        isPresented = false
        if let error = PowerController.perform(action) { catalog.statusMessage = error }
    }
}

struct HoverButton<Label: View>: View {
    var action: () -> Void
    var idleBackground: Color = .clear
    @ViewBuilder var label: () -> Label
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            label()
                .contentShape(Rectangle())
                .background(hovering ? Theme.hover : idleBackground, in: RoundedRectangle(cornerRadius: 3))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
