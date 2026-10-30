import AppKit

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    static func with(displayID: CGDirectDisplayID) -> NSScreen? {
        screens.first { $0.displayID == displayID }
    }
}

/// Display IDs can change between reboots or reconnects; the display UUID is stable per monitor.
func stableDisplayKey(_ displayID: CGDirectDisplayID) -> String {
    if let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
       let string = CFUUIDCreateString(nil, uuid) as String? {
        return string
    }
    return "display-\(displayID)"
}
