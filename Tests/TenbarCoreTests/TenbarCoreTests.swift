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
        #expect(small.height == StartMenuSize.minHeight)
    }

    @Test func splitKeepsTotalWidth() {
        let size = base.splitMoved(by: 60)
        #expect(size.allAppsWidth == 300)
        #expect(size.totalWidth == base.totalWidth)
        #expect(base.splitMoved(by: -500).allAppsWidth == StartMenuSize.allAppsRange.lowerBound)
        #expect(base.splitMoved(by: 500).pinnedWidth == StartMenuSize.minPinnedWidth)
    }

    @Test func sizesArePersistedPerDisplay() {
        let defaults = UserDefaults(suiteName: "tenbar.test.\(UUID().uuidString)")!
        let prefs = Preferences(defaults: defaults)
        let big = StartMenuSize(allAppsWidth: 300, pinnedWidth: 600, height: 800)
        prefs.setStartMenuSize(big, forDisplay: "A")
        #expect(prefs.startMenuSize(forDisplay: "A") == big)
        #expect(prefs.startMenuSize(forDisplay: "B") == nil)
        prefs.setStartMenuSize(nil, forDisplay: "A")
        #expect(prefs.startMenuSize(forDisplay: "A") == nil)
    }
}
