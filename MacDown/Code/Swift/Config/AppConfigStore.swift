import AppKit
import Foundation
import Yams

/// Writes single settings back to `config.yaml`.
///
/// The file is read as a YAML mapping, one key is changed, and the mapping is
/// written back. Other keys are kept; comments and key order are not (Yams does
/// not keep them), so the file is rewritten in a normal form.
enum AppConfigStore {
    /// Changes the value at `path` (for example `["lint", "enabled"]`). `nil` removes the key.
    static func set(_ value: Any?, at path: [String], file: URL = ConfigDirectory.configFile) throws {
        precondition(!path.isEmpty)
        var root: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: file.path) {
            let text = try String(contentsOf: file, encoding: .utf8)
            if let loaded = try Yams.load(yaml: text) {
                guard let mapping = loaded as? [String: Any] else { throw ConfigError.notAMapping }
                root = mapping
            }
        }
        root = updated(root, path: path[...], value: value)
        let yaml = root.isEmpty ? "" : try Yams.dump(object: root, sortKeys: true)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try yaml.write(to: file, atomically: true, encoding: .utf8)
    }

    private static func updated(_ dict: [String: Any], path: ArraySlice<String>, value: Any?) -> [String: Any] {
        var dict = dict
        let key = path.first!
        if path.count == 1 {
            dict[key] = value
        } else {
            let child = dict[key] as? [String: Any] ?? [:]
            let result = updated(child, path: path.dropFirst(), value: value)
            dict[key] = result.isEmpty ? nil : result
        }
        return dict
    }
}

/// The settings the Features pane edits, for Objective-C. Values come from
/// `config.yaml` through `ThemeService`; changes are written back and applied live.
@objc(MPFeatureSettings)
final class FeatureSettings: NSObject {
    @objc static var ligatures: Bool {
        get { ThemeService.shared.currentConfig().editor.ligatures }
        set { write(newValue, ["editor", "ligatures"]) }
    }
    @objc static var lintEnabled: Bool {
        get { ThemeService.shared.currentConfig().lint.enabled }
        set { write(newValue, ["lint", "enabled"]) }
    }
    @objc static var gitEnabled: Bool {
        get { ThemeService.shared.currentConfig().git.enabled }
        set { write(newValue, ["git", "enabled"]) }
    }
    @objc static var vegaLiteRemoteData: Bool {
        get { ThemeService.shared.currentConfig().charts.vegaLiteRemoteData }
        set { write(newValue, ["charts", "vega-lite-remote-data"]) }
    }
    /// Open documents as tabs of one window (the default) instead of separate windows.
    /// Kept in the user defaults: it is a per-Mac window preference, not content config.
    @objc static var openInTabs: Bool {
        get { UserDefaults.standard.object(forKey: "MPOpenInTabs") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "MPOpenInTabs") }
    }

    /// Set by File > New Tab: the next new document joins the workspace tab group.
    @objc static var joinNextDocumentToTabs = false
    @objc static let workspaceTabIdentifier = "MacDownWorkspace"

    /// Tabs exist only for the opened folder: windows of files inside it share one tab
    /// group; every other window stands alone, with no tab bar.
    @objc(applyTabbingToWindow:forFileURL:)
    static func applyTabbing(to window: NSWindow, for file: URL?) {
        var inWorkspace = SidebarController.isInsideWorkspace(file)
        if joinNextDocumentToTabs, file == nil {
            joinNextDocumentToTabs = false
            inWorkspace = SidebarController.workspaceRoot != nil
        }
        if openInTabs && inWorkspace {
            window.tabbingIdentifier = workspaceTabIdentifier
            window.tabbingMode = .preferred
        } else {
            // A unique identifier keeps the system from tabbing it with anything.
            if !window.tabbingIdentifier.hasPrefix("MacDownSolo-") {
                window.tabbingIdentifier = "MacDownSolo-\(UUID().uuidString)"
            }
            window.tabbingMode = .disallowed
        }
    }

    /// The theme named in `config.yaml`, or nil for "none".
    @objc static var themeName: String? {
        get { ThemeService.shared.currentConfig().theme }
        set { write(newValue, ["theme"]) }
    }
    /// Built-in and user theme names.
    @objc static func availableThemeNames() -> [String] {
        ThemeManager().availableThemes().map(\.name)
    }

    private static func write(_ value: Any?, _ path: [String]) {
        do {
            try AppConfigStore.set(value, at: path)
        } catch {
            NSLog("MacDown: could not write config.yaml: %@", error.localizedDescription)
            return
        }
        ThemeService.shared.reload()
        NotificationCenter.default.post(name: NSNotification.Name(ThemeService.didChangeNotificationName), object: nil)
    }
}
