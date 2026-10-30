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

        #expect(preferences.pins == nil)
        preferences.pins = PinList()
        #expect(preferences.pins == PinList())
        preferences.pins = PinList(["a", "b"])
        #expect(preferences.pins?.ids == ["a", "b"])
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
    }
}
