import CoreGraphics
import Foundation
import Testing
@testable import TenbarCore

@Suite struct StableOrderTests {
    @Test func appendsNewIDsAndKeepsExistingPositions() {
        var order = StableOrder<Int>()
        #expect(order.update(with: [1, 2, 3]) == [1, 2, 3])
        #expect(order.update(with: [3, 4, 1, 2]) == [1, 2, 3, 4])
    }

    @Test func dropsVanishedIDs() {
        var order = StableOrder([1, 2, 3])
        #expect(order.update(with: [3, 1]) == [1, 3])
    }

    @Test func ignoresDuplicatesInInput() {
        var order = StableOrder<Int>()
        #expect(order.update(with: [1, 1, 2]) == [1, 2])
    }

    @Test func movesBeforeTarget() {
        var order = StableOrder([1, 2, 3, 4])
        order.move(4, before: 2)
        #expect(order.ids == [1, 4, 2, 3])
        order.move(1, before: 3)
        #expect(order.ids == [4, 2, 1, 3])
        order.move(9, before: 1)
        #expect(order.ids == [4, 2, 1, 3])
    }
}

@Suite struct PinListTests {
    @Test func removesDuplicatesOnInit() {
        #expect(PinList(["a", "b", "a"]).ids == ["a", "b"])
    }

    @Test func toggleAddsAndRemoves() {
        var pins = PinList(["a"])
        pins.toggle("b")
        #expect(pins.ids == ["a", "b"])
        pins.toggle("a")
        #expect(pins.ids == ["b"])
        pins.pin("b")
        #expect(pins.ids == ["b"])
    }

    @Test func defaultsPreferInstalledPreferredApps() {
        let pins = PinList.defaults(available: ["x", "safari", "mail"], preferred: ["finder", "safari", "mail"])
        #expect(pins.ids == ["safari", "mail"])
    }

    @Test func defaultsFallBackToFirstApps() {
        let pins = PinList.defaults(available: ["a", "b", "c"], preferred: ["z"], fallbackCount: 2)
        #expect(pins.ids == ["a", "b"])
    }
}

@Suite struct PreferencesTests {
    @Test func startLayoutPerDisplayRoundTrip() throws {
        let suite = "TenbarTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults)

        #expect(preferences.startLayoutPerDisplay)
        preferences.startLayoutPerDisplay = false
        #expect(!preferences.startLayoutPerDisplay)

        #expect(preferences.startLayout(forDisplay: "A") == nil)
        let layout = StartLayout(pins: PinList(["x", "y"]))
        preferences.setStartLayout(layout, forDisplay: "A")
        #expect(preferences.startLayout(forDisplay: "A") == layout)
        #expect(preferences.startLayout(forDisplay: "B") == nil)
        preferences.setStartLayout(nil, forDisplay: "A")
        #expect(preferences.startLayout(forDisplay: "A") == nil)
    }

    @Test func pinsRoundTripAndDistinguishUninitialized() throws {
        let suite = "TenbarTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults)

        #expect(preferences.pins(.taskbar) == nil)
        preferences.setPins(PinList(), .taskbar)
        #expect(preferences.pins(.taskbar) == PinList())
        preferences.setPins(PinList(["a", "b"]), .taskbar)
        #expect(preferences.pins(.taskbar)?.ids == ["a", "b"])
    }

    @Test func taskbarAndStartPinsAreIndependent() throws {
        let suite = "TenbarTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults)

        preferences.setPins(PinList(["finder"]), .taskbar)
        #expect(preferences.pins(.start) == nil)
        preferences.setPins(PinList(["mail", "notes"]), .start)
        #expect(preferences.pins(.taskbar)?.ids == ["finder"])
        #expect(preferences.pins(.start)?.ids == ["mail", "notes"])
    }

    @Test func taskbarPinsArePerDisplay() throws {
        let suite = "TenbarTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults)

        preferences.setPins(PinList(["finder"]), .taskbar)
        #expect(preferences.taskbarPins(forDisplay: "A") == nil)
        preferences.setTaskbarPins(PinList(["mail"]), forDisplay: "A")
        preferences.setTaskbarPins(PinList(), forDisplay: "B")
        #expect(preferences.taskbarPins(forDisplay: "A")?.ids == ["mail"])
        #expect(preferences.taskbarPins(forDisplay: "B") == PinList())
        #expect(preferences.pins(.taskbar)?.ids == ["finder"])
        preferences.setTaskbarPins(nil, forDisplay: "A")
        #expect(preferences.taskbarPins(forDisplay: "A") == nil)
    }

    @Test func keepsExistingTaskbarPinsFromEarlierVersion() throws {
        let suite = "TenbarTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["safari"], forKey: "PinnedAppIDs")
        defaults.set(true, forKey: "PinsInitialized")

        let preferences = Preferences(defaults: defaults)
        #expect(preferences.pins(.taskbar)?.ids == ["safari"])
        #expect(preferences.pins(.start) == nil)
    }
}

@Suite struct ScreenGeometryTests {
    let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let right = CGRect(x: 1440, y: 0, width: 1920, height: 1080)

    @Test func convertsAccessibilityToCocoa() {
        let ax = CGRect(x: 100, y: 50, width: 400, height: 300)
        let cocoa = ScreenGeometry.cocoaRect(fromAccessibility: ax, primaryScreenHeight: 900)
        #expect(cocoa == CGRect(x: 100, y: 550, width: 400, height: 300))
    }

    @Test func picksScreenWithLargestOverlap() {
        let mostlyRight = CGRect(x: 1300, y: 100, width: 800, height: 400)
        #expect(ScreenGeometry.bestScreenIndex(for: mostlyRight, screens: [primary, right]) == 1)
        let mostlyLeft = CGRect(x: 1000, y: 100, width: 600, height: 400)
        #expect(ScreenGeometry.bestScreenIndex(for: mostlyLeft, screens: [primary, right]) == 0)
    }

    @Test func returnsNilOffscreen() {
        let offscreen = CGRect(x: -5000, y: -5000, width: 100, height: 100)
        #expect(ScreenGeometry.bestScreenIndex(for: offscreen, screens: [primary, right]) == nil)
    }
}

@Suite struct AppScannerTests {
    @Test func findsAppsSortedAndSkipsNestedBundles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TenbarScan-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("Zeta.app/Contents/Helpers/Inner.app"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("Utilities/alpha.app"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("NotAnApp"), withIntermediateDirectories: true)

        let names = AppScanner.scan(roots: [root], extras: []).map(\.name)
        #expect(names == ["alpha", "Zeta"])
    }

    @Test func findsSafariInCryptex() throws {
        try #require(FileManager.default.fileExists(atPath: "/System/Cryptexes/App/System/Applications/Safari.app"))
        #expect(AppScanner.scan().contains { $0.id == "com.apple.Safari" })
    }
}

@Suite struct TaskbarLayoutTests {
    let windows: [(id: Int, appKey: String)] = [(1, "mail"), (2, "safari"), (3, "mail"), (4, "notes")]

    @Test func alwaysMergesPinnedAppsWithTheirWindows() {
        let items = TaskbarLayout.items(pinnedAppKeys: ["finder", "safari"], windows: windows, mode: .always)
        #expect(items.map(\.appKey) == ["finder", "safari", "mail", "notes"])
        #expect(items.map(\.windowIDs) == [[], [2], [1, 3], [4]])
        #expect(items.map(\.isPinned) == [true, true, false, false])
        #expect(items.allSatisfy { $0.representsApp })
    }

    @Test func neverShowsOneItemPerWindowAtThePinnedPosition() {
        let items = TaskbarLayout.items(pinnedAppKeys: ["finder", "mail"], windows: windows, mode: .never)
        #expect(items.map(\.appKey) == ["finder", "mail", "mail", "safari", "notes"])
        #expect(items.map(\.windowIDs) == [[], [1], [3], [2], [4]])
        #expect(items.map(\.representsApp) == [true, false, false, false, false])
    }

    @Test func closedPinsComeBeforeRunningApps() {
        for mode in CombineMode.allCases {
            let items = TaskbarLayout.items(pinnedAppKeys: ["notes", "finder", "safari", "music"], windows: windows, mode: mode)
            #expect(items.map(\.appKey) == ["finder", "music", "notes", "safari", "mail"].flatMap { key in
                mode == .never && key == "mail" ? [key, key] : [key]
            })
        }
    }

    @Test func itemIDsAreUnique() {
        for mode in CombineMode.allCases {
            let items = TaskbarLayout.items(pinnedAppKeys: ["mail"], windows: windows, mode: mode)
            #expect(Set(items.map(\.id)).count == items.count)
        }
    }

    @Test func combineModePersists() throws {
        let suite = "TenbarTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults)
        #expect(preferences.combineMode == .always)
        preferences.combineMode = .never
        #expect(Preferences(defaults: defaults).combineMode == .never)
        #expect(preferences.showLabels)
        preferences.showLabels = false
        #expect(Preferences(defaults: defaults).showLabels == false)
    }
}

@Suite struct TaskbarDropTests {
    let pins = PinList(["finder", "safari", "mail"])

    func drop(_ source: String, on target: String?, visible: [String] = ["notes", "music"], order: [String] = []) -> TaskbarDrop.Result {
        TaskbarDrop.apply(source: source, target: target, pins: pins, visibleUnpinned: visible, unpinnedOrder: order)
    }

    @Test func reordersPinnedApps() {
        #expect(drop("mail", on: "finder") == .pins(PinList(["mail", "finder", "safari"])))
        #expect(drop("finder", on: nil) == .pins(PinList(["safari", "mail", "finder"])))
    }

    @Test func pinnedDroppedOnUnpinnedMovesToEndOfPins() {
        #expect(drop("finder", on: "notes") == .pins(PinList(["safari", "mail", "finder"])))
        #expect(drop("mail", on: "notes") == TaskbarDrop.Result.none)
    }

    @Test func reordersUnpinnedAppsAndKeepsHiddenOnes() {
        #expect(drop("music", on: "notes", order: ["photos"]) == .unpinnedOrder(["music", "notes", "photos"]))
        #expect(drop("notes", on: nil) == .unpinnedOrder(["music", "notes"]))
    }

    @Test func unpinnedCannotMoveIntoPinnedArea() {
        #expect(drop("notes", on: "safari") == TaskbarDrop.Result.none)
    }

    @Test func externalAppGetsPinnedAtDropPosition() {
        #expect(drop("calendar", on: "safari") == .pins(PinList(["finder", "calendar", "safari", "mail"])))
        #expect(drop("calendar", on: nil) == .pins(PinList(["finder", "safari", "mail", "calendar"])))
        #expect(drop("calendar", on: "notes") == .pins(PinList(["finder", "safari", "mail", "calendar"])))
    }

    @Test func droppingOnItselfDoesNothing() {
        #expect(drop("safari", on: "safari") == TaskbarDrop.Result.none)
    }

    @Test func layoutHonorsUnpinnedOrder() {
        let windows: [(id: Int, appKey: String)] = [(1, "notes"), (2, "music"), (3, "photos")]
        let items = TaskbarLayout.items(pinnedAppKeys: [], windows: windows, mode: .always, unpinnedOrder: ["music", "notes"])
        #expect(items.map(\.appKey) == ["music", "notes", "photos"])
    }
}

@Suite struct StartMenuSizeTests {
    let base = StartMenuSize.standard

    @Test func cornerDragChangesPinnedWidthAndHeight() {
        let size = base.resized(width: 100, height: 50, maxTotalWidth: 2000, maxHeight: 1000)
        #expect(size == StartMenuSize(allAppsWidth: 240, pinnedWidth: 360, height: 530))
    }

    @Test func cornerDragIsClampedToScreen() {
        let size = base.resized(width: 5000, height: 5000, maxTotalWidth: 1000, maxHeight: 700)
        #expect(size.totalWidth == 1000)
        #expect(size.height == 700)
        let small = base.resized(width: -5000, height: -5000, maxTotalWidth: 1000, maxHeight: 700)
        #expect(small.pinnedWidth == StartMenuSize.minPinnedWidth)
        #expect(small.height == StartMenuSize.minHeight(scale: StartMenuScale.standard))
    }

    @Test func minHeightGrowsWithScale() {
        let small = StartMenuSize.minHeight(scale: StartMenuScale.range.lowerBound)
        let large = StartMenuSize.minHeight(scale: StartMenuScale.range.upperBound)
        #expect(small >= StartMenuSize.minHeight)
        #expect(large > small)
        let low = StartMenuSize(allAppsWidth: 240, pinnedWidth: 260, height: 100)
        #expect(low.clamped(maxTotalWidth: 2000, maxHeight: 1000, scale: 1.8).height == large)
        #expect(StartMenuSize.minHeight(scale: 1, showsGroupHeader: false) < StartMenuSize.minHeight(scale: 1))
    }

    @Test func splitKeepsTotalWidth() {
        let size = base.splitMoved(by: 60)
        #expect(size.allAppsWidth == 300)
        #expect(size.totalWidth == base.totalWidth)
        #expect(base.splitMoved(by: -500).allAppsWidth == StartMenuSize.allAppsRange.lowerBound)
        #expect(base.splitMoved(by: 500).pinnedWidth == StartMenuSize.minPinnedWidth)
    }

    @Test func sizesArePersistedPerDisplay() {
        let suite = "TenbarTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = Preferences(defaults: defaults)
        let big = StartMenuSize(allAppsWidth: 300, pinnedWidth: 600, height: 800)
        prefs.setStartMenuSize(big, forDisplay: "A")
        #expect(prefs.startMenuSize(forDisplay: "A") == big)
        #expect(prefs.startMenuSize(forDisplay: "B") == nil)
        prefs.setStartMenuSize(nil, forDisplay: "A")
        #expect(prefs.startMenuSize(forDisplay: "A") == nil)
    }

    @Test func hidingAllAppsDropsItsWidth() {
        #expect(base.width(showsAllApps: false) == StartMenuSize.railWidth + base.pinnedWidth)
        #expect(base.totalWidth == StartMenuSize.railWidth + base.allAppsWidth + base.pinnedWidth)
        let wide = StartMenuSize(allAppsWidth: 240, pinnedWidth: 2000, height: 480)
        #expect(wide.clamped(maxTotalWidth: 1000, maxHeight: 1000, showsAllApps: false).pinnedWidth == 1000 - StartMenuSize.railWidth)
    }

    @Test func allAppsVisibilityIsPersistedPerDisplay() {
        let defaults = UserDefaults(suiteName: "TenbarTests-\(UUID())")!
        let prefs = Preferences(defaults: defaults)
        #expect(prefs.startShowsAllApps(forDisplay: "A"))
        prefs.setStartShowsAllApps(false, forDisplay: "A")
        #expect(!prefs.startShowsAllApps(forDisplay: "A"))
        #expect(prefs.startShowsAllApps(forDisplay: "B"))
        prefs.setStartShowsAllApps(true, forDisplay: "A")
        #expect(prefs.startShowsAllApps(forDisplay: "A"))
    }

    @Test func scaleIsPersistedPerDisplayAndClamped() {
        let defaults = UserDefaults(suiteName: "TenbarTests-\(UUID())")!
        let prefs = Preferences(defaults: defaults)
        #expect(prefs.startMenuScale(forDisplay: "A") == StartMenuScale.standard)
        prefs.setStartMenuScale(1.4, forDisplay: "A")
        #expect(prefs.startMenuScale(forDisplay: "A") == 1.4)
        #expect(prefs.startMenuScale(forDisplay: "B") == StartMenuScale.standard)
        prefs.setStartMenuScale(9, forDisplay: "B")
        #expect(prefs.startMenuScale(forDisplay: "B") == StartMenuScale.range.upperBound)
        prefs.setStartMenuScale(nil, forDisplay: "A")
        #expect(prefs.startMenuScale(forDisplay: "A") == StartMenuScale.standard)
    }

    @Test func onlySessionEndingActionsSkipReopen() {
        #expect(PowerAction.allCases.filter(\.endsSession) == [.logOut, .restart, .shutDown])
    }
}

@Suite struct AppSearchTests {
    let names = ["App Store", "Mail", "Microsoft Word", "Système", "Photo Booth", "Photos", "Wordle"]

    func search(_ query: String) -> [String] {
        AppSearch.filter(names, query: query, name: { $0 })
    }

    @Test func emptyQueryKeepsEverything() {
        #expect(search("  ") == names)
    }

    @Test func ranksPrefixThenWordThenContains() {
        #expect(search("word") == ["Wordle", "Microsoft Word"])
        #expect(search("photo") == ["Photo Booth", "Photos"])
        #expect(search("ai") == ["Mail"])
    }

    @Test func ignoresCaseAndDiacritics() {
        #expect(search("SYSTEME") == ["Système"])
        #expect(search("mAIL") == ["Mail"])
    }

    @Test func matchesBundleIdentifierLast() {
        let apps = [AppRecord(id: "com.apple.iCal", name: "Calendar", path: ""),
                    AppRecord(id: "x.ical", name: "iCal Tools", path: "")]
        let result = AppSearch.filter(apps, query: "ical", name: \.name, id: \.id)
        #expect(result.map(\.name) == ["iCal Tools", "Calendar"])
    }

    @Test func noMatchReturnsEmpty() {
        #expect(search("zzz").isEmpty)
    }
}

@Suite struct StartLayoutTests {
    func layout() -> StartLayout {
        StartLayout(groups: [
            StartGroup(id: "work", name: "Arbeit", apps: ["mail", "calendar", "notes"]),
            StartGroup(id: "fun", name: "Freizeit", apps: ["music", "photos"]),
        ])
    }

    func apps(_ layout: StartLayout) -> [[String]] { layout.groups.map(\.apps) }

    @Test func migratesFlatPinsIntoOneGroup() {
        let migrated = StartLayout(pins: PinList(["a", "b"]), groupID: "g")
        #expect(migrated.groups == [StartGroup(id: "g", name: "", apps: ["a", "b"])])
        #expect(StartLayout(pins: PinList()).groups.isEmpty)
    }

    @Test func initDropsDuplicatesAndEmptyGroups() {
        let layout = StartLayout(groups: [StartGroup(id: "a", apps: ["x", "y"]), StartGroup(id: "b", apps: ["x"]), StartGroup(id: "c")])
        #expect(apps(layout) == [["x", "y"]])
    }

    @Test func pinAppendsToLastGroupOrCreatesOne() {
        var layout = layout()
        layout.pin("maps")
        layout.pin("mail")
        #expect(apps(layout) == [["mail", "calendar", "notes"], ["music", "photos", "maps"]])
        var empty = StartLayout()
        empty.pin("maps", newGroupID: "n")
        #expect(empty.groups == [StartGroup(id: "n", apps: ["maps"])])
    }

    @Test func unpinRemovesEmptyGroups() {
        var layout = layout()
        layout.unpin("music")
        layout.unpin("photos")
        #expect(layout.groups.map(\.id) == ["work"])
    }

    @Test func movesAppsBetweenGroups() {
        var layout = layout()
        layout.move("notes", toGroup: "fun", before: "photos")
        #expect(apps(layout) == [["mail", "calendar"], ["music", "notes", "photos"]])
        layout.move("mail", toGroup: "work", before: nil)
        #expect(apps(layout) == [["calendar", "mail"], ["music", "notes", "photos"]])
        layout.move("maps", toGroup: "work", before: "calendar")
        #expect(apps(layout) == [["maps", "calendar", "mail"], ["music", "notes", "photos"]])
    }

    @Test func movingLastAppOutRemovesGroup() {
        var layout = StartLayout(groups: [StartGroup(id: "a", apps: ["x"]), StartGroup(id: "b", apps: ["y"])])
        layout.move("x", toGroup: "b")
        #expect(layout.groups.map(\.id) == ["b"])
        layout.moveToNewGroup("y", groupID: "c")
        #expect(layout.groups == [StartGroup(id: "b", apps: ["x"]), StartGroup(id: "c", apps: ["y"])])
        var single = StartLayout(groups: [StartGroup(id: "a", apps: ["x"])])
        single.moveToNewGroup("x", groupID: "z")
        #expect(single.groups == [StartGroup(id: "z", apps: ["x"])])
    }

    @Test func newGroupAtEnd() {
        var layout = layout()
        layout.moveToNewGroup("calendar", groupID: "new")
        #expect(layout.groups.map(\.id) == ["work", "fun", "new"])
        #expect(layout.groupID(of: "calendar") == "new")
    }

    @Test func renamesAndMovesGroups() {
        var layout = layout()
        layout.rename("fun", to: "  Medien ")
        #expect(layout.groups[1].name == "Medien")
        layout.moveGroup("fun", before: "work")
        #expect(layout.groups.map(\.id) == ["fun", "work"])
        layout.moveGroup("fun", before: nil)
        #expect(layout.groups.map(\.id) == ["work", "fun"])
    }

    @Test func removeGroupUnpinsItsApps() {
        var layout = layout()
        layout.removeGroup("work")
        #expect(!layout.contains("mail"))
        #expect(layout.allApps == ["music", "photos"])
    }

    @Test func persistsThroughPreferences() throws {
        let suite = "TenbarTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults)
        #expect(preferences.startLayout == nil)
        preferences.startLayout = layout()
        #expect(preferences.startLayout == layout())
    }
}

@Suite struct TileDropTests {
    // Two rows of 72x72 tiles with 6pt spacing below a 30pt header: a b c / d e
    let tiles: [(id: String, frame: CGRect)] = [
        ("a", CGRect(x: 0, y: 30, width: 72, height: 72)),
        ("b", CGRect(x: 78, y: 30, width: 72, height: 72)),
        ("c", CGRect(x: 156, y: 30, width: 72, height: 72)),
        ("d", CGRect(x: 0, y: 108, width: 72, height: 72)),
        ("e", CGRect(x: 78, y: 108, width: 72, height: 72)),
    ]

    func target(_ x: CGFloat, _ y: CGFloat) -> String? {
        TileDrop.target(location: CGPoint(x: x, y: y), tiles: tiles, headerMaxY: 30)
    }

    @Test func headerGoesToFront() { #expect(target(100, 10) == "a") }

    @Test func leftHalfOfTileInsertsBeforeIt() {
        #expect(target(80, 50) == "b")
        #expect(target(10, 120) == "d")
    }

    @Test func rightHalfInsertsAfter() {
        #expect(target(140, 50) == "c")
        #expect(target(220, 50) == "d") // end of first row → before first tile of next row
        #expect(target(140, 120) == nil) // end of last row → append
    }

    @Test func freeSpaceRightOfRowAndBelowAll() {
        #expect(target(300, 120) == nil)
        #expect(target(10, 300) == nil)
        #expect(target(10, 105) == "d") // gap between rows
    }

    @Test func emptyGroupAppends() {
        #expect(TileDrop.target(location: .zero, tiles: [], headerMaxY: 30) == nil)
    }
}

@Suite struct NewCommandsTests {
    @Test func finderFileMenuPutsCommandNFirst() {
        let items = [
            MenuItemInfo(title: "Neuer Ordner", key: "N", modifiers: 1),
            MenuItemInfo(title: "Neues Finder-Fenster", key: "N"),
            MenuItemInfo(title: "Neuer Tab", key: "T"),
            MenuItemInfo(title: "Öffnen", key: "O"),
            MenuItemInfo(title: "Neues Dokument", enabled: false),
        ]
        let commands = NewCommands.select(menuTitle: "Ablage", items: items)
        #expect(commands.map(\.title) == ["Neues Finder-Fenster", "Neuer Ordner", "Neuer Tab"])
        #expect(commands[0].path == ["Ablage", "Neues Finder-Fenster"])
        #expect(commands[1].shortcut == "⇧⌘N")
    }

    @Test func keepsSubmenuItemsAndMatchesCommandNWithoutPrefix() {
        let items = [
            MenuItemInfo(title: "Neues Fenster", children: [
                MenuItemInfo(title: "Basic", key: "N"),
                MenuItemInfo(title: "Pro"),
                MenuItemInfo(title: "", enabled: true),
            ]),
            MenuItemInfo(title: "Project…", key: "N"),
            MenuItemInfo(title: "New", children: [MenuItemInfo(title: "File", enabled: false)]),
        ]
        let commands = NewCommands.select(menuTitle: "File", items: items)
        #expect(commands.map(\.title) == ["Project…", "Neues Fenster"])
        #expect(commands[1].children.map(\.path) == [["File", "Neues Fenster", "Basic"], ["File", "Neues Fenster", "Pro"]])
    }

    @Test func shortcutText() {
        #expect(NewCommands.shortcutText(key: "n", modifiers: 0) == "⌘N")
        #expect(NewCommands.shortcutText(key: "N", modifiers: 3) == "⌥⇧⌘N")
        #expect(NewCommands.shortcutText(key: "N", modifiers: 8) == "N")
        #expect(NewCommands.shortcutText(key: nil, modifiers: 0) == nil)
    }
}

@Suite struct WindowPlacementTests {
    @Test func keepsRelativePosition() {
        let source = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let target = CGRect(x: 2000, y: 100, width: 2000, height: 1000)
        let moved = WindowPlacement.frame(CGRect(x: 250, y: 200, width: 500, height: 400), from: source, to: target)
        #expect(moved == CGRect(x: 2750, y: 400, width: 500, height: 400))
    }

    @Test func shrinksTooLargeWindows() {
        let moved = WindowPlacement.frame(CGRect(x: 0, y: 0, width: 3000, height: 1800),
                                          from: CGRect(x: 0, y: 0, width: 3360, height: 1890),
                                          to: CGRect(x: -1800, y: 0, width: 1800, height: 1100))
        #expect(moved == CGRect(x: -1800, y: 0, width: 1800, height: 1100))
    }

    @Test func usableAreaExcludesTaskbar() {
        let area = WindowPlacement.usableArea(screen: CGRect(x: 0, y: 0, width: 100, height: 100),
                                              visible: CGRect(x: 0, y: 0, width: 100, height: 95), barHeight: 40)
        #expect(area == CGRect(x: 0, y: 40, width: 100, height: 55))
    }

    @Test func fitAboveBarShrinksMaximizedWindow() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let usable = CGRect(x: 0, y: 46, width: 1000, height: 729)
        let fitted = WindowPlacement.fitAboveBar(CGRect(x: 0, y: 0, width: 1000, height: 775), screen: screen, usable: usable)
        #expect(fitted == usable)
    }

    @Test func fitAboveBarLeavesWindowDraggedDown() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let usable = CGRect(x: 0, y: 46, width: 1000, height: 729)
        #expect(WindowPlacement.fitAboveBar(CGRect(x: 100, y: 20, width: 400, height: 300), screen: screen, usable: usable) == nil)
        #expect(WindowPlacement.fitAboveBar(CGRect(x: 0, y: -100, width: 1000, height: 850), screen: screen, usable: usable) == nil)
    }

    @Test func fitAboveBarShrinksFullHeightWindowKeepingWidth() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let usable = CGRect(x: 0, y: 46, width: 1000, height: 729)
        let fitted = WindowPlacement.fitAboveBar(CGRect(x: 200, y: 0, width: 500, height: 775), screen: screen, usable: usable)
        #expect(fitted == CGRect(x: 200, y: 46, width: 500, height: 729))
    }

    @Test func fitAboveBarLeavesFittingAndFullScreenWindows() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let usable = CGRect(x: 0, y: 46, width: 1000, height: 729)
        #expect(WindowPlacement.fitAboveBar(CGRect(x: 0, y: 46, width: 500, height: 500), screen: screen, usable: usable) == nil)
        #expect(WindowPlacement.fitAboveBar(CGRect(x: 0, y: 45.5, width: 500, height: 500), screen: screen, usable: usable) == nil)
        #expect(WindowPlacement.fitAboveBar(screen, screen: screen, usable: usable) == nil)
    }

    @Test func movesOnlyNewWindowsOfTheApp() {
        var requests = PlacementRequests<Int, String>()
        let start = Date()
        requests.expect(appKey: "finder", on: "B", knownWindows: [1], now: start)
        #expect(requests.place(windows: [(1, "finder", "A"), (7, "mail", "A")], now: start).isEmpty)

        let moves = requests.place(windows: [(1, "finder", "A"), (2, "finder", "A")], now: start.addingTimeInterval(3))
        #expect(moves.map(\.id) == [2] && moves.map(\.display) == ["B"])
        // A restored second window shortly after is moved too, but not twice.
        let more = requests.place(windows: [(2, "finder", "A"), (3, "finder", "A")], now: start.addingTimeInterval(4))
        #expect(more.map(\.id) == [3])
        // After the follow-up time, new windows stay where they open.
        #expect(requests.place(windows: [(4, "finder", "A")], now: start.addingTimeInterval(10)).isEmpty)
        #expect(requests.isEmpty)
    }

    @Test func windowAlreadyOnTargetIsNotMovedAndRequestsExpire() {
        var requests = PlacementRequests<Int, String>()
        let start = Date()
        requests.expect(appKey: "x", on: "A", knownWindows: [], now: start)
        #expect(requests.place(windows: [(1, "x", "A")], now: start).isEmpty)
        requests.expect(appKey: "y", on: "A", knownWindows: [], now: start)
        #expect(requests.place(windows: [(5, "y", "B")], now: start.addingTimeInterval(30)).isEmpty)
    }
}

@Suite struct FullScreenDetectionTests {
    let screens = [CGRect(x: 0, y: 0, width: 1920, height: 1080), CGRect(x: 1920, y: 0, width: 2560, height: 1440)]

    @Test func detectsTopWindowCoveringScreen() {
        let windows = [CGRect(x: 1920, y: 0, width: 2560, height: 1440), CGRect(x: 100, y: 100, width: 800, height: 600)]
        #expect(ScreenGeometry.fullScreenIndices(screens: screens, windows: windows) == [1])
    }

    @Test func ignoresCoveringWindowBehindSmallerOne() {
        let windows = [CGRect(x: 100, y: 100, width: 800, height: 600), CGRect(x: 0, y: 0, width: 1920, height: 1080)]
        #expect(ScreenGeometry.fullScreenIndices(screens: screens, windows: windows).isEmpty)
    }

    @Test func maximizedWindowBelowMenuBarIsNotFullScreen() {
        let windows = [CGRect(x: 0, y: 25, width: 1920, height: 1055)]
        #expect(ScreenGeometry.fullScreenIndices(screens: screens, windows: windows).isEmpty)
    }
}
