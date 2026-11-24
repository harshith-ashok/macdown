import XCTest
@testable import MacDown

final class AppConfigStoreTests: XCTestCase {
    private var file: URL!

    override func setUpWithError() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cfgstore-\(UUID().uuidString)")
        file = dir.appendingPathComponent("config.yaml")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
    }

    func testCreatesFileAndFolder() throws {
        try AppConfigStore.set(true, at: ["lint", "enabled"], file: file)
        let config = AppConfig.load(from: file).config
        XCTAssertTrue(config.lint.enabled)
    }

    func testKeepsOtherKeys() throws {
        try "theme: Dracula\nfonts:\n  code: JetBrains Mono\neditor:\n  ligatures: true\n"
            .write(to: try makeFile(), atomically: true, encoding: .utf8)
        try AppConfigStore.set(false, at: ["editor", "ligatures"], file: file)
        let config = AppConfig.load(from: file).config
        XCTAssertEqual(config.theme, "Dracula")
        XCTAssertEqual(config.fonts.code, "JetBrains Mono")
        XCTAssertFalse(config.editor.ligatures)
    }

    func testRemovingTheLastKeyDropsTheSection() throws {
        try AppConfigStore.set("Nord", at: ["theme"], file: file)
        try AppConfigStore.set(nil, at: ["theme"], file: file)
        XCTAssertNil(AppConfig.load(from: file).config.theme)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "")
    }

    func testRefusesToOverwriteAFileThatIsNotAMapping() throws {
        try "- just\n- a list\n".write(to: try makeFile(), atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try AppConfigStore.set(true, at: ["git", "enabled"], file: file))
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "- just\n- a list\n")
    }

    private func makeFile() throws -> URL {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        return file
    }
}
