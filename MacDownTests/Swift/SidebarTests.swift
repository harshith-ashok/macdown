import XCTest
@testable import MacDown

final class SidebarTests: XCTestCase {
    private var base: URL!
    private var savedRoot: Any?

    override func setUpWithError() throws {
        savedRoot = UserDefaults.standard.object(forKey: "MPWorkspaceRoot")
        UserDefaults.standard.removeObject(forKey: "MPWorkspaceRoot")
        base = FileManager.default.temporaryDirectory.appendingPathComponent("sidebar-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base.appendingPathComponent("vault/a"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: base.appendingPathComponent("loose"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: base)
        UserDefaults.standard.set(savedRoot, forKey: "MPWorkspaceRoot")
    }

    func testNoFolderOpenedMeansNothingIsInsideTheWorkspace() {
        XCTAssertNil(SidebarController.workspaceRoot)
        XCTAssertFalse(SidebarController.isInsideWorkspace(base.appendingPathComponent("vault/a/n.md")))
        XCTAssertFalse(SidebarController.isInsideWorkspace(nil))
    }

    func testFilesInsideTheOpenedFolderAreInTheWorkspace() {
        SidebarController.workspaceRoot = base.appendingPathComponent("vault")
        XCTAssertTrue(SidebarController.isInsideWorkspace(base.appendingPathComponent("vault/a/n.md")))
        XCTAssertFalse(SidebarController.isInsideWorkspace(base.appendingPathComponent("loose/n.md")))
        // A sibling whose name starts the same must not count as inside.
        XCTAssertFalse(SidebarController.isInsideWorkspace(base.appendingPathComponent("vault2/n.md")))
    }

    func testAMissingFolderIsNoWorkspace() {
        UserDefaults.standard.set(base.appendingPathComponent("gone").path, forKey: "MPWorkspaceRoot")
        XCTAssertNil(SidebarController.workspaceRoot)
    }

    func testTabsAreOnlyForTheWorkspace() {
        SidebarController.workspaceRoot = base.appendingPathComponent("vault")
        let inside = NSWindow(), outside = NSWindow()
        FeatureSettings.applyTabbing(to: inside, for: base.appendingPathComponent("vault/a/n.md"))
        FeatureSettings.applyTabbing(to: outside, for: base.appendingPathComponent("loose/n.md"))
        XCTAssertEqual(inside.tabbingMode, .preferred)
        XCTAssertEqual(inside.tabbingIdentifier, FeatureSettings.workspaceTabIdentifier)
        XCTAssertEqual(outside.tabbingMode, .disallowed)
        XCTAssertNotEqual(outside.tabbingIdentifier, FeatureSettings.workspaceTabIdentifier)
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
