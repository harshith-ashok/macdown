import AppKit

/// Per-document glue for the optional features: lint marks in the editor and
/// the git branch, both shown in the window subtitle ("main · 3 warnings").
///
/// Everything is off the main thread and cheap when a feature is switched off:
/// with lint and git both off, this class does nothing on a key press.
@objc(MPEditorStatusController)
final class EditorStatusController: NSObject {
    private weak var textView: NSTextView?
    private weak var document: NSDocument?
    private var lintGeneration = 0
    private var lintWork: DispatchWorkItem?
    private var markedRanges: [NSRange] = []
    private var warningCount: Int?
    private var branch: String?
    private let queue = DispatchQueue(label: "macdown.lint", qos: .utility)

    @objc init(textView: NSTextView, document: NSDocument) {
        self.textView = textView
        self.document = document
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(windowDidBecomeKey(_:)),
                                               name: NSWindow.didBecomeKeyNotification, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    // MARK: Events from the document

    /// Call on every text change. Cheap: it only schedules a run after the user stops typing.
    @objc func textDidChange() {
        guard FeatureSettings.lintEnabled else { return }
        scheduleLint(delay: 0.8)
    }

    /// Call when `config.yaml` changed or the document first appeared.
    @objc func configDidChange() {
        if FeatureSettings.lintEnabled {
            scheduleLint(delay: 0.1)
        } else {
            clearMarks()
            warningCount = nil
        }
        refreshGit()
        updateSubtitle()
    }

    @objc private func windowDidBecomeKey(_ note: Notification) {
        guard let window = note.object as? NSWindow, window === document?.windowControllers.first?.window else { return }
        refreshGit()
    }

    // MARK: Lint

    private func scheduleLint(delay: TimeInterval) {
        lintWork?.cancel()
        lintGeneration += 1
        let generation = lintGeneration
        let work = DispatchWorkItem { [weak self] in self?.runLint(generation: generation) }
        lintWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func runLint(generation: Int) {
        guard let textView = textView else { return }
        let text = textView.string
        let directory = document?.fileURL?.deletingLastPathComponent()
        let rules = LintRules.resolve(ThemeService.shared.currentConfig().lint.rules)
        queue.async { [weak self] in
            let found = Linter(enabledRules: rules, options: LintOptions(baseDirectory: directory)).lint(text)
            DispatchQueue.main.async {
                guard let self = self, generation == self.lintGeneration, FeatureSettings.lintEnabled else { return }
                self.show(found)
            }
        }
    }

    private func show(_ diagnostics: [LintDiagnostic]) {
        guard let textView = textView, let layout = textView.layoutManager else { return }
        clearMarks()
        let length = (textView.string as NSString).length
        for item in diagnostics {
            let range = NSIntersectionRange(item.range, NSRange(location: 0, length: length))
            guard range.length > 0 else { continue }
            layout.addTemporaryAttributes([
                .underlineStyle: NSUnderlineStyle.single.rawValue | NSUnderlineStyle.patternDot.rawValue,
                .underlineColor: NSColor.systemOrange,
                .toolTip: item.message,
            ], forCharacterRange: range)
            markedRanges.append(range)
        }
        warningCount = diagnostics.count
        updateSubtitle()
    }

    private func clearMarks() {
        guard let layout = textView?.layoutManager else { markedRanges = []; return }
        let length = textView.map { ($0.string as NSString).length } ?? 0
        for range in markedRanges {
            let clipped = NSIntersectionRange(range, NSRange(location: 0, length: length))
            guard clipped.length > 0 else { continue }
            layout.removeTemporaryAttribute(.underlineStyle, forCharacterRange: clipped)
            layout.removeTemporaryAttribute(.underlineColor, forCharacterRange: clipped)
            layout.removeTemporaryAttribute(.toolTip, forCharacterRange: clipped)
        }
        markedRanges = []
    }

    // MARK: Git

    private func refreshGit() {
        guard FeatureSettings.gitEnabled, let directory = document?.fileURL?.deletingLastPathComponent() else {
            branch = nil
            updateSubtitle()
            return
        }
        Task { [weak self] in
            let repo = await GitRepository.open(containing: directory)
            let status = try? await repo?.status()
            await MainActor.run {
                guard let self = self else { return }
                if repo == nil {
                    self.branch = nil
                } else {
                    self.branch = status?.branch ?? "detached HEAD"
                }
                self.updateSubtitle()
            }
        }
    }

    // MARK: Subtitle

    private func updateSubtitle() {
        guard let window = document?.windowControllers.first?.window else { return }
        var parts: [String] = []
        if let branch = branch { parts.append(branch) }
        if let count = warningCount {
            parts.append(count == 0 ? "No lint warnings" : count == 1 ? "1 lint warning" : "\(count) lint warnings")
        }
        window.subtitle = parts.joined(separator: " · ")
    }

    // MARK: Ligatures

    /// The editor font with ligatures and contextual alternates switched off,
    /// or the font itself when ligatures are on (the default).
    @objc static func applyLigatures(_ ligatures: Bool, to font: NSFont) -> NSFont {
        guard !ligatures else { return font }
        let off: [[NSFontDescriptor.FeatureKey: Int]] = [
            [.typeIdentifier: 1, .selectorIdentifier: 3],    // common ligatures off
            [.typeIdentifier: 36, .selectorIdentifier: 1],   // contextual alternates off (programming ligatures)
        ]
        let descriptor = font.fontDescriptor.addingAttributes([.featureSettings: off])
        return NSFont(descriptor: descriptor, size: font.pointSize) ?? font
    }
}
