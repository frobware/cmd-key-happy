import XCTest

@testable import cmd_key_happy

final class ConfigFileWatcherTests: XCTestCase {
    private var root: URL!
    private var watcher: ConfigFileWatcher?

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
          .resolvingSymlinksInPath()
          .appendingPathComponent("ckh-watcher-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        watcher?.stop()
        watcher = nil
        try? FileManager.default.removeItem(at: root)
    }

    private func makeConfig(_ contents: String = "Alacritty\n") throws -> URL {
        let config = root.appendingPathComponent("config")
        try contents.write(to: config, atomically: false, encoding: .utf8)
        return config
    }

    /// Start watching and return an expectation the watcher's callback
    /// fulfils. Fulfilment is capped so a burst of events cannot fail
    /// the test by over-fulfilling.
    private func watch(_ config: URL) throws -> XCTestExpectation {
        let changed = expectation(description: "watcher reported a change to \(config.path)")
        changed.assertForOverFulfill = false
        let watcher = ConfigFileWatcher(path: config.path) { changed.fulfill() }
        try watcher.start()
        self.watcher = watcher
        return changed
    }

    /// Append in place, the way a shell redirection or a sed -i -less
    /// edit does: same inode, new contents.
    private func editInPlace(_ config: URL, adding line: String) throws {
        let handle = try FileHandle(forWritingTo: config)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(line.utf8))
        try handle.close()
    }

    /// Write a sibling and rename it over the config, which is what an
    /// atomic save is. The path keeps its name and gains a new inode.
    private func replaceAtomically(_ config: URL, with contents: String) throws {
        let staging = root.appendingPathComponent("config.tmp")
        try contents.write(to: staging, atomically: false, encoding: .utf8)
        XCTAssertEqual(rename(staging.path, config.path), 0,
                       "rename failed: \(String(cString: strerror(errno)))")
    }

    /// The case that does work, kept as the control: if this fails the
    /// other two prove nothing.
    func testInPlaceEditIsReported() throws {
        let config = try makeConfig()
        let changed = try watch(config)
        try editInPlace(config, adding: "Ghostty\n")
        wait(for: [changed], timeout: 2)
    }

    func testAtomicReplacementIsReported() throws {
        let config = try makeConfig()
        let changed = try watch(config)
        try replaceAtomically(config, with: "Ghostty\n")
        wait(for: [changed], timeout: 2)
    }

    /// The shape of an emacs first save: the original is renamed aside
    /// for the backup and the new file is written a moment later, so
    /// for that moment the path has nothing at it. Both halves have to
    /// be reported -- the second is the one carrying the new config.
    func testAFileRenamedAwayAndWrittenAgainIsReported() throws {
        let config = try makeConfig()
        let gone = expectation(description: "the rename away is reported")
        gone.assertForOverFulfill = false
        let back = expectation(description: "the file written in its place is reported")
        back.assertForOverFulfill = false

        var seenGone = false
        let watcher = ConfigFileWatcher(path: config.path) {
            if seenGone {
                back.fulfill()
            } else {
                seenGone = true
                gone.fulfill()
            }
        }
        try watcher.start()
        self.watcher = watcher

        XCTAssertEqual(rename(config.path, root.appendingPathComponent("config~").path), 0,
                       "rename failed: \(String(cString: strerror(errno)))")
        wait(for: [gone], timeout: 2)

        try "Ghostty\n".write(to: config, atomically: false, encoding: .utf8)
        wait(for: [back], timeout: 2)
    }

    /// Removing the config is a change like any other: the daemon
    /// answers it by carrying on with an empty configuration, which it
    /// cannot do if it never hears about it.
    func testDeletionIsReported() throws {
        let config = try makeConfig()
        let changed = try watch(config)
        try FileManager.default.removeItem(at: config)
        wait(for: [changed], timeout: 2)
    }

    /// Recreate the file from inside the deletion callback, which runs
    /// after the directory watch is armed and possibly before it is
    /// registered. A later in-place edit then has to be reported, which
    /// it only is if the watch came back to the file.
    ///
    /// This pins the recovery, not the registration window: it passes
    /// against a watcher that rechecks the path immediately rather than
    /// on registration.
    func testRecreationDuringDeletionCallbackRecoversFileWatch() throws {
        let config = try makeConfig()
        let recovered = expectation(description: "the recreated file is reported")
        recovered.assertForOverFulfill = false
        let edited = expectation(description: "a later in-place edit is reported")
        edited.assertForOverFulfill = false
        var recreated = false
        var editing = false

        let watcher = ConfigFileWatcher(path: config.path) {
            if !recreated {
                recreated = true
                do {
                    try "Ghostty\n".write(to: config, atomically: false, encoding: .utf8)
                } catch {
                    XCTFail("Could not recreate config: \(error)")
                }
            } else if editing {
                edited.fulfill()
            } else {
                recovered.fulfill()
            }
        }
        try watcher.start()
        self.watcher = watcher

        try FileManager.default.removeItem(at: config)
        wait(for: [recovered], timeout: 2)

        editing = true
        try editInPlace(config, adding: "kitty\n")
        wait(for: [edited], timeout: 2)
    }

    /// A config kept in a dotfiles checkout and linked into place, the
    /// shape ConfigFileLoaderTests already covers for reading. The
    /// editing happens over there, in the directory holding the
    /// target, and that is where a watch has to go while the file is
    /// briefly absent -- not the directory holding the link, where
    /// nothing will ever happen again.
    func testAReplacedSymlinkTargetIsReported() throws {
        let store = root.appendingPathComponent("dotfiles")
        try FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
        let target = store.appendingPathComponent("ckh-config")
        try "Alacritty\n".write(to: target, atomically: false, encoding: .utf8)

        let link = root.appendingPathComponent("config")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let gone = expectation(description: "the rename away is reported")
        gone.assertForOverFulfill = false
        let back = expectation(description: "the file written in its place is reported")
        back.assertForOverFulfill = false

        var seenGone = false
        let watcher = ConfigFileWatcher(path: link.path) {
            if seenGone { back.fulfill() } else { seenGone = true; gone.fulfill() }
        }
        try watcher.start()
        self.watcher = watcher

        // Renamed aside, and only rewritten once the watcher has had to
        // decide where to look while the path has nothing at it.
        XCTAssertEqual(rename(target.path, store.appendingPathComponent("ckh-config~").path), 0,
                       "rename failed: \(String(cString: strerror(errno)))")
        wait(for: [gone], timeout: 2)

        try "Ghostty\n".write(to: target, atomically: false, encoding: .utf8)
        wait(for: [back], timeout: 2)
    }

    /// The damage is not one missed reload    /// The damage is not one missed reload: once the path has been
    /// replaced the watcher is holding an inode nothing will ever write
    /// to again, so every later edit is missed too.
    func testEditsAfterAnAtomicReplacementAreStillReported() throws {
        let config = try makeConfig()
        let changed = try watch(config)
        try replaceAtomically(config, with: "Ghostty\n")
        try editInPlace(config, adding: "kitty\n")
        wait(for: [changed], timeout: 2)
    }
}
