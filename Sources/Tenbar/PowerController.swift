import AppKit
import TenbarCore

@MainActor
enum PowerController {
    /// Runs the action after optional confirmation. Returns an error message on failure.
    static func perform(_ action: PowerAction) -> String? {
        if action.needsConfirmation && !confirm(action) { return nil }
        if action.endsSession { disableReopenAtLogin() }
        var error: NSDictionary?
        NSAppleScript(source: action.appleScript)?.executeAndReturnError(&error)
        guard let error else { return nil }
        let detail = error[NSAppleScript.errorMessage] as? String ?? "Unbekannter Fehler"
        return "„\(action.title)“ fehlgeschlagen. Erlaube Tenbar die Steuerung von „System Events“ unter Datenschutz & Sicherheit → Automation. (\(detail))"
    }

    /// Unticks "Reopen windows when logging back in". loginwindow reads this host-specific setting
    /// when the session ends and otherwise relaunches every open app after the next start.
    private static func disableReopenAtLogin() {
        let domain = "com.apple.loginwindow" as CFString
        for key in ["TALLogoutSavesState", "LoginwindowLaunchesRelaunchApps"] {
            CFPreferencesSetValue(key as CFString, kCFBooleanFalse, domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        }
        CFPreferencesSetValue("TALAppsToRelaunchAtLogin" as CFString, nil, domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
    }

    private static func confirm(_ action: PowerAction) -> Bool {
        let alert = NSAlert()
        alert.messageText = "\(action.title)?"
        alert.informativeText = "Nicht gespeicherte Änderungen in geöffneten Apps können verloren gehen."
        alert.alertStyle = .warning
        alert.addButton(withTitle: action.title)
        alert.addButton(withTitle: "Abbrechen")
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }
}
