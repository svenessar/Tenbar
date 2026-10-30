import AppKit
import SwiftUI
import TenbarCore

struct StartMenuView: View {
    @EnvironmentObject private var catalog: AppCatalog
    @EnvironmentObject private var menu: StartMenuController
    @State private var dragStart: (mouse: NSPoint, size: StartMenuSize)?
    @State private var selection = 0
    @FocusState private var searchFocused: Bool
    @State private var dropIndicator: TileDropIndicator?
    @State private var draggedGroup: String?
    @State private var tileFrames: [String: CGRect] = [:]
    @State private var headerMaxY: [String: CGFloat] = [:]
    @State private var dropOnNewGroup = false
    @State private var editingGroup: String?
    @State private var draftName = ""
    @FocusState private var renameFocused: Bool

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

    private var searchResults: [InstalledApp] {
        AppSearch.filter(catalog.apps, query: menu.searchText, name: \.name, id: \.id)
    }

    private var isSearching: Bool { !menu.searchText.trimmingCharacters(in: .whitespaces).isEmpty }

    private var allApps: some View {
        let results = searchResults
        return VStack(alignment: .leading, spacing: 0) {
            searchField(results)
            sectionTitle(isSearching ? "Suchergebnisse" : "Alle Apps")
            if catalog.apps.isEmpty {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if results.isEmpty {
                Text("Keine App für „\(menu.searchText)“ gefunden")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, app in
                                appRow(app, highlighted: isSearching && index == selection).id(app.id)
                            }
                        }
                        .padding(.bottom, 8)
                    }
                    .onChange(of: selection) { _, index in
                        if results.indices.contains(index) { proxy.scrollTo(results[index].id) }
                    }
                    .onChange(of: menu.searchText) { _, _ in
                        if let first = results.first { proxy.scrollTo(first.id, anchor: .top) }
                    }
                }
            }
        }
        .onChange(of: menu.searchText) { _, _ in selection = 0 }
        .onChange(of: menu.openCount) { _, _ in draggedGroup = nil; dropIndicator = nil; focusSearch() }
        .onAppear { focusSearch() }
    }

    private func searchField(_ results: [InstalledApp]) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(.secondary)
            TextField("Apps durchsuchen", text: $menu.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
                .onSubmit {
                    if results.indices.contains(selection) { launch(results[selection]) }
                }
                .onKeyPress(.downArrow) {
                    selection = min(selection + 1, max(results.count - 1, 0))
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    selection = max(selection - 1, 0)
                    return .handled
                }
            if !menu.searchText.isEmpty {
                Button { menu.searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Suche leeren")
            }
        }
        .padding(.horizontal, 10).frame(height: 30)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(searchFocused ? Color.accentColor.opacity(0.8) : .clear, lineWidth: 1)
        }
        .padding(.horizontal, 12).padding(.top, 12)
    }

    private func focusSearch() {
        // Wait until the panel is key, otherwise the focus request is dropped.
        DispatchQueue.main.async { searchFocused = true }
    }

    private var pinned: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("Angeheftet")
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(catalog.startLayout(display: displayKey).groups) { group in groupView(group) }
                    newGroupZone
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            .dropDestination(for: String.self) { keys, _ in
                guard let source = keys.first else { return false }
                draggedGroup = nil
                catalog.dropOnStart(source, display: displayKey, group: nil)
                return true
            }
            if !catalog.statusMessage.isEmpty {
                Text(catalog.statusMessage).font(.system(size: 10)).foregroundStyle(.secondary)
                    .lineLimit(4).padding(12)
            }
        }
        .background(Color.white.opacity(0.03))
    }

    private func groupView(_ group: StartGroup) -> some View {
        let apps = catalog.apps(in: group)
        let space = "group-\(group.id)"
        return VStack(alignment: .leading, spacing: 6) {
            groupHeader(group)
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(space)).maxY } action: { headerMaxY[group.id] = $0 }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 6)], spacing: 6) {
                ForEach(apps) { app in
                    tile(app, group: group)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(space)) } action: { tileFrames[app.id] = $0 }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                // "Append" marker after the last tile.
                if let indicator = dropIndicator, indicator.group == group.id, indicator.before == nil, !indicator.isGroup {
                    Capsule().fill(Color.accentColor).frame(height: 3).offset(y: 6)
                }
            }
        }
        .overlay(alignment: .top) {
            if let indicator = dropIndicator, indicator.group == group.id, indicator.isGroup {
                Capsule().fill(Color.accentColor).frame(height: 3).offset(y: -8)
            }
        }
        .contentShape(Rectangle())
        .coordinateSpace(.named(space))
        // One drop target per group: the insertion point comes from the mouse position, because
        // views that are themselves draggable don't receive drops reliably.
        .onDrop(of: [.text], delegate: GroupDropDelegate(
            groupID: group.id,
            tiles: apps.compactMap { app in tileFrames[app.id].map { (id: app.id, frame: $0) } },
            headerMaxY: headerMaxY[group.id] ?? 0,
            isGroupDrag: draggedGroup != nil,
            indicator: $dropIndicator
        ) { [catalog] source, before in
            draggedGroup = nil
            catalog.dropOnStart(source, display: displayKey, group: group.id, before: before)
        })
    }

    @ViewBuilder
    private func groupHeader(_ group: StartGroup) -> some View {
        if editingGroup == group.id {
            TextField("Gruppe benennen", text: $draftName)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .focused($renameFocused)
                .onSubmit { finishRename() }
                .onChange(of: renameFocused) { _, focused in if !focused { finishRename() } }
                .padding(.horizontal, 4).frame(height: 24)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 3))
        } else {
            HoverButton(action: { startRename(group) }) {
                HStack(spacing: 6) {
                    Text(group.name.isEmpty ? "Gruppe benennen" : group.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(group.name.isEmpty ? .white.opacity(0.4) : .white.opacity(0.94))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "line.3.horizontal").font(.system(size: 10)).foregroundStyle(.white.opacity(0.35))
                }
                .padding(.horizontal, 4).frame(height: 24)
            }
            .help("Klicken zum Umbenennen, ziehen zum Verschieben der Gruppe")
            .onDrag {
                draggedGroup = group.id
                return NSItemProvider(object: (StartLayout.groupPayloadPrefix + group.id) as NSString)
            } preview: {
                Text(group.name.isEmpty ? "Gruppe" : group.name).font(.system(size: 12, weight: .semibold))
                    .padding(6).background(Theme.startMenuBackground)
            }
            .contextMenu {
                Button("Gruppe umbenennen") { startRename(group) }
                Button("Gruppe vom Start lösen") { catalog.removeStartGroup(group.id, display: displayKey) }
            }
        }
    }

    private var newGroupZone: some View {
        RoundedRectangle(cornerRadius: 4)
            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .foregroundStyle(.white.opacity(dropOnNewGroup ? 0.6 : 0.15))
            .background(dropOnNewGroup ? Theme.hover : .clear, in: RoundedRectangle(cornerRadius: 4))
            .frame(height: 44)
            .overlay {
                Text("Hierher ziehen für eine neue Gruppe")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
            }
            .dropDestination(for: String.self) { keys, _ in
                guard let source = keys.first else { return false }
                draggedGroup = nil
                catalog.dropOnStart(source, display: displayKey, group: nil)
                return true
            } isTargeted: { dropOnNewGroup = $0 }
    }

    private func startRename(_ group: StartGroup) {
        draftName = group.name
        editingGroup = group.id
        DispatchQueue.main.async { renameFocused = true }
    }

    private func finishRename() {
        guard let groupID = editingGroup else { return }
        editingGroup = nil
        catalog.renameStartGroup(groupID, to: draftName, display: displayKey)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 8)
    }

    private func appRow(_ app: InstalledApp, highlighted: Bool = false) -> some View {
        HoverButton(action: { launch(app) }, idleBackground: highlighted ? Theme.active : .clear) {
            HStack(spacing: 10) {
                Image(nsImage: catalog.icon(for: app)).resizable().frame(width: 24, height: 24)
                Text(app.name).font(.system(size: 12)).lineLimit(1)
                Spacer(minLength: 0)
                if catalog.isPinned(app.id, to: .start(display: displayKey)) {
                    Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(.horizontal, 12).frame(height: 34)
        }
        .draggable(app.id) { dragPreview(app) }
        .contextMenu { pinMenu(app) }
    }

    private func tile(_ app: InstalledApp, group: StartGroup) -> some View {
        HoverButton(action: { launch(app) }, idleBackground: Color.white.opacity(0.07)) {
            VStack(spacing: 6) {
                Image(nsImage: catalog.icon(for: app)).resizable().frame(width: 32, height: 32)
                Text(app.name).font(.system(size: 10)).lineLimit(1).padding(.horizontal, 4)
            }
            .frame(maxWidth: .infinity, minHeight: 72)
        }
        .hoverTooltip(app.name)
        .overlay(alignment: .leading) {
            if let indicator = dropIndicator, !indicator.isGroup, indicator.before == app.id { DropMarker().offset(x: -4) }
        }
        .draggable(app.id) { dragPreview(app) }
        .contextMenu { pinMenu(app) }
    }

    private func dragPreview(_ app: InstalledApp) -> some View {
        Image(nsImage: catalog.icon(for: app)).resizable().frame(width: 32, height: 32)
    }

    @ViewBuilder
    private func pinMenu(_ app: InstalledApp) -> some View {
        Button(catalog.isPinned(app.id, to: .start(display: displayKey)) ? "Von Start lösen" : "An Start anheften") {
            catalog.togglePin(app.id, .start(display: displayKey))
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

struct TileDropIndicator: Equatable {
    var group: String
    var before: String?
    var isGroup: Bool
}

/// Drop target for a whole start group; tracks the insertion point while dragging.
struct GroupDropDelegate: DropDelegate {
    let groupID: String
    let tiles: [(id: String, frame: CGRect)]
    let headerMaxY: CGFloat
    let isGroupDrag: Bool
    @Binding var indicator: TileDropIndicator?
    let perform: @MainActor (String, String?) -> Void

    private func target(_ info: DropInfo) -> String? {
        TileDrop.target(location: info.location, tiles: tiles, headerMaxY: headerMaxY)
    }

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.text]) }

    func dropEntered(info: DropInfo) { update(info) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        update(info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if indicator?.group == groupID { indicator = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        let before = target(info)
        indicator = nil
        guard let provider = info.itemProviders(for: [.text]).first else { return false }
        let perform = perform
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let source = object as? NSString else { return }
            let sourceString = source as String
            Task { @MainActor in perform(sourceString, before) }
        }
        return true
    }

    private func update(_ info: DropInfo) {
        let next = TileDropIndicator(group: groupID, before: isGroupDrag ? nil : target(info), isGroup: isGroupDrag)
        if indicator != next { indicator = next }
    }
}

/// Clickable row/tile with hover background. Uses a tap gesture instead of `Button`,
/// because a Button swallows the mouse drag and `.draggable` never starts.
struct HoverButton<Label: View>: View {
    var action: () -> Void
    var idleBackground: Color = .clear
    @ViewBuilder var label: () -> Label
    @State private var hovering = false

    var body: some View {
        label()
            .contentShape(Rectangle())
            .background(hovering ? Theme.hover : idleBackground, in: RoundedRectangle(cornerRadius: 3))
            .onHover { hovering = $0 }
            .onTapGesture(perform: action)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
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
