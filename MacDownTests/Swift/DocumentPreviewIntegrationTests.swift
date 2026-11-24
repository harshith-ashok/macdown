import XCTest
@testable import MacDown

/// Loads a real document window from the nib and checks the new preview end to end.
final class DocumentPreviewIntegrationTests: XCTestCase {
    private func waitUntil(_ timeout: TimeInterval = 10, _ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
        let end = Date().addingTimeInterval(timeout)
        while !condition() && Date() < end { RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02)) }
        XCTAssertTrue(condition(), "Timed out", file: file, line: line)
    }

    private func evaluate(_ preview: PreviewController, _ script: String) -> Any? {
        var result: Any?
        var done = false
        preview.webView.evaluateJavaScript(script) { value, _ in result = value; done = true }
        waitUntil { done }
        return result
    }

    func testDocumentWindowLoadsRendersAndCleansUp() throws {
        let document = MPDocument()
        document.makeWindowControllers()
        _ = document.windowControllers.first?.window     // The nib (MPDocument.xib) loads on first access.
        defer { document.close() }

        let preview = try XCTUnwrap(document.value(forKey: "previewController") as? PreviewController,
                                    "The preview controller was not created from the nib")
        XCTAssertTrue(preview.webView.superview is NSSplitView, "The web view must sit in the split view")
        if let placeholder = document.value(forKey: "previewPlaceholder") as? NSView {
            XCTAssertNil(placeholder.superview, "The placeholder must be out of the view hierarchy")
        }

        document.markdown = "# Hello Preview\n\nSome *text* with `code`.\n\n```swift\nlet x = 1\n```\n"
        let renderer = try XCTUnwrap(document.value(forKey: "renderer") as? MPRenderer)
        renderer.parseAndRenderNow()

        waitUntil { (self.evaluate(preview, "document.querySelector('h1') ? document.querySelector('h1').textContent : ''") as? String) == "Hello Preview" }
        // Prism may add its own classes after the page loads, so check membership, not the exact string.
        XCTAssertEqual(evaluate(preview, "document.querySelector('pre code').classList.contains('language-swift')") as? Bool, true)
        XCTAssertEqual(evaluate(preview, "document.querySelector('em').textContent") as? String, "text")

        // The preview shows the new text after an edit.
        document.markdown = "# Changed\n"
        renderer.parseAndRenderNow()
        waitUntil { (self.evaluate(preview, "document.querySelector('h1') ? document.querySelector('h1').textContent : ''") as? String) == "Changed" }
    }

    func testBundledStyleAndScriptsLoadThroughTheScheme() throws {
        let document = MPDocument()
        document.makeWindowControllers()
        _ = document.windowControllers.first?.window
        defer { document.close() }
        let preview = try XCTUnwrap(document.value(forKey: "previewController") as? PreviewController)
        document.markdown = "# Styled\n\n- [ ] task\n"
        (document.value(forKey: "renderer") as? MPRenderer)?.parseAndRenderNow()
        waitUntil { (self.evaluate(preview, "!!document.querySelector('h1')") as? Bool) == true }
        // The base style (from the app bundle, via macdown-file://) must have been applied.
        waitUntil { (self.evaluate(preview, "getComputedStyle(document.querySelector('h1')).fontWeight") as? String).map { $0 != "400" } ?? false }
        let sheets = evaluate(preview, "document.styleSheets.length") as? Int ?? 0
        XCTAssertGreaterThan(sheets, 0)
    }

    /// Scrolling either pane moves the other one.
    func testScrollSyncWorksInBothDirections() throws {
        let document = MPDocument()
        let preferences = try XCTUnwrap(document.value(forKey: "preferences") as? NSObject)
        let savedSync = preferences.value(forKey: "editorSyncScrolling")
        preferences.setValue(true, forKey: "editorSyncScrolling")
        defer { preferences.setValue(savedSync, forKey: "editorSyncScrolling") }
        document.makeWindowControllers()
        let window = try XCTUnwrap(document.windowControllers.first?.window)
        window.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 700), display: true)
        window.layoutIfNeeded()
        defer { document.close() }

        let preview = try XCTUnwrap(document.value(forKey: "previewController") as? PreviewController)
        let editor = try XCTUnwrap(document.value(forKey: "editor") as? NSTextView)
        let scrollView = try XCTUnwrap(editor.enclosingScrollView)

        var markdown = ""
        for i in 1...40 {
            markdown += "## Section \(i)\n\n" + String(repeating: "Some filler text for the section. ", count: 30) + "\n\n"
        }
        document.markdown = markdown
        (document.value(forKey: "renderer") as? MPRenderer)?.parseAndRenderNow()
        // Both panes need to be tall enough to scroll, and the page must have reported its size.
        waitUntil(20) { preview.contentHeight > preview.visibleHeight * 3 && editor.string.count > 1000 && preview.headerLocations.count >= 30 }
        waitUntil { scrollView.documentView!.bounds.height > scrollView.contentView.bounds.height * 2 }
        // Let the page settle: scroll events right after a load are ignored on purpose.
        document.setValue(0.0, forKey: "ignorePreviewScrollUntil")
        RunLoop.current.run(until: Date().addingTimeInterval(1.3))

        // Editor -> preview.
        let editorTarget = scrollView.documentView!.bounds.height / 2
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: editorTarget))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        waitUntil { preview.scrollY > 100 }
        let previewAfterEditor = preview.scrollY

        // Preview -> editor. Wait out the echo window of the step above first.
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        let editorBefore = scrollView.contentView.bounds.origin.y
        let previewTarget = preview.contentHeight * 0.8
        _ = evaluate(preview, "window.scrollTo(0, \(previewTarget)); 1")
        waitUntil { scrollView.contentView.bounds.origin.y > editorBefore + 100 }
        XCTAssertGreaterThan(scrollView.contentView.bounds.origin.y, editorBefore)
        XCTAssertGreaterThan(previewTarget, previewAfterEditor)

        // The editor move must not bounce back and undo the preview position.
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        let settled = evaluate(preview, "window.scrollY") as? Double ?? 0
        XCTAssertEqual(settled, Double(previewTarget), accuracy: 40)
    }
}
