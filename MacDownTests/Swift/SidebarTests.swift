import XCTest
@testable import MacDown

final class SidebarTests: XCTestCase {
    private var base: URL!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("sidebar-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base.appendingPathComponent("vault/a/b"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: base.appendingPathComponent("loose"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: base) }

    func testRootIsTheVaultFolderWhenAnObsidianFolderIsAbove() throws {
        try FileManager.default.createDirectory(at: base.appendingPathComponent("vault/.obsidian"), withIntermediateDirectories: true)
        let root = SidebarController.defaultRoot(for: base.appendingPathComponent("vault/a/b/note.md"))
        XCTAssertEqual(root.lastPathComponent, "vault")   // compare names: /var may be /private/var
    }

    func testRootIsTheRepositoryFolderWhenAGitFolderIsAbove() throws {
        try FileManager.default.createDirectory(at: base.appendingPathComponent("vault/.git"), withIntermediateDirectories: true)
        let root = SidebarController.defaultRoot(for: base.appendingPathComponent("vault/a/note.md"))
        XCTAssertEqual(root.lastPathComponent, "vault")
    }

    func testRootIsTheFileFolderWithoutMarkers() {
        let root = SidebarController.defaultRoot(for: base.appendingPathComponent("loose/note.md"))
        XCTAssertEqual(root.lastPathComponent, "loose")
    }

    func testIconsAreSmallAndCached() {
        let folder = SidebarIcons.icon(isFolder: true, fileExtension: "")
        XCTAssertEqual(folder.size, NSSize(width: 16, height: 16))
        XCTAssertTrue(SidebarIcons.icon(isFolder: true, fileExtension: "") === folder)
        XCTAssertFalse(SidebarIcons.icon(isFolder: false, fileExtension: "md") === folder)
    }

    func testOpenInTabsDefaultsToOn() {
        let key = "MPOpenInTabs"
        let saved = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertTrue(FeatureSettings.openInTabs)
        FeatureSettings.openInTabs = false
        XCTAssertFalse(FeatureSettings.openInTabs)
    }
}
