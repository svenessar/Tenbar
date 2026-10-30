import AppKit
import SwiftUI
import TenbarCore

struct StartMenuView: View {
    @EnvironmentObject private var catalog: AppCatalog
    @EnvironmentObject private var menu: StartMenuController
    @State private var dropTargetTile: String?
    @State private var dragStart: (mouse: NSPoint, size: StartMenuSize)?

    var body: some View {
        let size = menu.size
        HStack(spacing: 0) {
            rail
            allApps.frame(width: size.allAppsWidth)
            pinned.frame(width: size.pinnedWidth)
                .overlay(alignment: .leading) { splitHandle }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .topTrailing) { cornerHandle }
        .background(Theme.startMenuBackground)
        .overlay { Rectangle().strokeBorder(Color.white.opacity(0.08), lineWidth: 1) }
        .foregroundStyle(.white.opacity(0.94))
        .environment(\.colorScheme, .dark)
        .transaction { $0.animation = nil }
    }

    // MARK: Size

    private var displayKey: String { menu.displayKey ?? "" }

    /// Tracks the drag in screen coordinates, so it stays exact while the window resizes.
    private func resizeGesture(_ apply: @escaping (_ start: StartMenuSize, _ dx: Double, _ dy: Double) -> StartMenuSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { _ in
                let mouse = NSEvent.mouseLocation
                if dragStart == nil { dragStart = (mouse, menu.size) }
                guard let start = dragStart else { return }
                menu.resize(to: apply(start.size, mouse.x - start.mouse.x, mouse.y - start.mouse.y))
            }
            .onEnded { _ in
                dragStart = nil
                menu.saveSize()
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
                // The controller clamps to the screen.
                start.resized(width: dx, height: dy, maxTotalWidth: .infinity, maxHeight: .infinity)
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
        VStack(spacing: 2) {
            Spacer()
            railButton("person.crop.circle", help: NSFullUserName()) {}
            railButton("power", help: "Ein/Aus") { showPowerMenu() }
        }
        .padding(.vertical, 6)
        .frame(width: StartMenuSize.railWidth)
        .frame(maxHeight: .infinity)
        .background(Color.black.opacity(0.18))
    }

    private func railButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        HoverButton(action: action) {
            Image(systemName: symbol).font(.system(size: 16))
                .frame(width: StartMenuSize.railWidth, height: 40)
        }
        .help(help)
    }

    /// AppKit menu at the mouse position: SwiftUI's Menu adds its own insets and misaligns the icon.
    private func showPowerMenu() {
        let powerMenu = NSMenu()
        for action in PowerAction.allCases {
            let item = ClosureMenuItem(title: action.title) { run(action) }
            item.image = NSImage(systemSymbolName: action.symbol, accessibilityDescription: nil)
            powerMenu.addItem(item)
        }
        powerMenu.addItem(.separator())
        powerMenu.addItem(ClosureMenuItem(title: "Tenbar beenden") { NSApp.terminate(nil) })
        powerMenu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
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
        menu.close()
        catalog.launch(app)
    }

    private func run(_ action: PowerAction) {
        menu.close()
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

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func fire() { handler() }
}
