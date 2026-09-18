import XCTest

@testable import cmd_key_happy

/// Path handling for the configuration file.
///
/// A symlink stores its target as written, so a relative target is
/// relative to the directory holding the link, not to the working
/// directory -- which under launchd is /. The relative cases below
/// therefore assert the resolved path, and run from an unrelated
/// directory.
final class ConfigFileLoaderTests: XCTestCase {
    private var root: String!
    private var savedWorkingDirectory: String!
    private let loader = ConfigFileLoader()

    override func setUpWithError() throws {
        savedWorkingDirectory = FileManager.default.currentDirectoryPath
        // Canonicalised: the temporary directory is itself reached
        // through a symlink on macOS, and these tests compare paths.
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
          .resolvingSymlinksInPath()
          .appendingPathComponent("ckh-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        root = base.path
    }

    override func tearDownWithError() throws {
        FileManager.default.changeCurrentDirectoryPath(savedWorkingDirectory)
        try? FileManager.default.removeItem(atPath: root)
    }

    private func path(_ components: String...) -> String {
        components.reduce(root!) { ($0 as NSString).appendingPathComponent($1) }
    }

    @discardableResult
    private func write(_ contents: String, to relative: String) throws -> String {
        let full = path(relative)
        try FileManager.default.createDirectory(
          atPath: (full as NSString).deletingLastPathComponent,
          withIntermediateDirectories: true)
        try contents.write(toFile: full, atomically: true, encoding: .utf8)
        return full
    }

    /// A link at cfgdir/config pointing at ../dotfiles/ckh-config,
    /// which is the shape of a config kept in a dotfiles checkout.
    private func makeRelativeSymlink(contents: String = "Alacritty\n") throws -> (link: String, target: String) {
        let target = try write(contents, to: "dotfiles/ckh-config")
        try FileManager.default.createDirectory(
          atPath: path("cfgdir"), withIntermediateDirectories: true)
        let link = path("cfgdir", "config")
        try FileManager.default.createSymbolicLink(
          atPath: link, withDestinationPath: "../dotfiles/ckh-config")
        return (link, target)
    }

    // MARK: - validatePath

    func testPlainFileResolvesToItself() throws {
        let file = try write("Alacritty\n", to: "config")
        XCTAssertEqual(try loader.validatePath(file), file)
    }

    func testAbsoluteSymlinkResolvesToItsTarget() throws {
        let target = try write("Alacritty\n", to: "dotfiles/ckh-config")
        let link = path("config")
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: target)
        XCTAssertEqual(try loader.validatePath(link), target)
    }

    /// A relative target has to come back as a path, not as the
    /// "../dotfiles/ckh-config" it is stored as.
    func testRelativeSymlinkResolvesAgainstTheLinksOwnDirectory() throws {
        let (link, target) = try makeRelativeSymlink()
        let resolved = try loader.validatePath(link)
        XCTAssertTrue((resolved as NSString).isAbsolutePath,
                      "a relative target must not be returned as written")
        XCTAssertEqual(URL(fileURLWithPath: resolved).standardized.path, target)
    }

    /// The condition that hid the defect in testing and made it fatal
    /// under launchd: the working directory is not the link's own.
    func testRelativeSymlinkResolvesFromAnUnrelatedWorkingDirectory() throws {
        let (link, target) = try makeRelativeSymlink()
        XCTAssertTrue(FileManager.default.changeCurrentDirectoryPath("/"))
        let resolved = try loader.validatePath(link)
        XCTAssertEqual(URL(fileURLWithPath: resolved).standardized.path, target)
    }

    func testMissingFileThrowsFileNotFound() {
        let missing = path("nope")
        XCTAssertThrowsError(try loader.validatePath(missing)) { error in
            guard case ConfigError.fileNotFound(let reported) = error else {
                return XCTFail("expected fileNotFound, got \(error)")
            }
            XCTAssertEqual(reported, missing, "the error names the path the caller gave")
        }
    }

    func testDirectoryThrowsNotRegularFile() throws {
        try FileManager.default.createDirectory(
          atPath: path("adir"), withIntermediateDirectories: true)
        XCTAssertThrowsError(try loader.validatePath(path("adir"))) { error in
            guard case ConfigError.notRegularFile = error else {
                return XCTFail("expected notRegularFile, got \(error)")
            }
        }
    }

    /// A link to a link to a regular file, which is what a dotfiles
    /// manager leaves behind when the config is linked into place and
    /// the target is itself linked into a store.
    func testChainedSymlinkResolvesToTheRegularFile() throws {
        let target = try write("Alacritty\n", to: "dotfiles/ckh-config")
        let middle = path("middle")
        try FileManager.default.createSymbolicLink(atPath: middle, withDestinationPath: target)
        let link = path("config")
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: middle)
        XCTAssertEqual(try loader.validatePath(link), target)
    }

    /// Following the chain has to stop somewhere: a cycle would
    /// otherwise spin rather than fail. The kernel would refuse this
    /// open with ELOOP, so reporting it as missing matches what the
    /// read would have said.
    func testSymlinkCycleThrowsFileNotFoundRatherThanSpinning() throws {
        let first = path("first")
        let second = path("second")
        try FileManager.default.createSymbolicLink(atPath: first, withDestinationPath: second)
        try FileManager.default.createSymbolicLink(atPath: second, withDestinationPath: first)
        XCTAssertThrowsError(try loader.validatePath(first)) { error in
            guard case ConfigError.fileNotFound = error else {
                return XCTFail("expected fileNotFound, got \(error)")
            }
        }
    }

    /// A chain of links, each to the next, ending at a regular file.
    /// Returns the path of the first link.
    private func chain(ofLength length: Int, to target: String) throws -> String {
        var next = target
        for i in 0..<length {
            let link = path("link-\(i)")
            try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: next)
            next = link
        }
        return next
    }

    /// The limit is the kernel's, so a chain it would open resolves
    /// here too.
    func testAChainAtTheLimitResolves() throws {
        let target = try write("Alacritty\n", to: "dotfiles/ckh-config")
        let link = try chain(ofLength: 32, to: target)
        XCTAssertEqual(try loader.validatePath(link), target)
    }

    /// One link past the limit is a chain the kernel would refuse with
    /// ELOOP, so validation has to refuse it rather than hand back the
    /// link it stopped on.
    func testAChainPastTheLimitIsRefused() throws {
        let target = try write("Alacritty\n", to: "dotfiles/ckh-config")
        let link = try chain(ofLength: 33, to: target)
        XCTAssertThrowsError(try loader.validatePath(link)) { error in
            guard error is ConfigError else {
                return XCTFail("expected a ConfigError, got \(error)")
            }
        }
    }

    func testBrokenSymlinkThrowsFileNotFound() throws {
        let link = path("broken")
        try FileManager.default.createSymbolicLink(
          atPath: link, withDestinationPath: "../nowhere/missing")
        XCTAssertThrowsError(try loader.validatePath(link)) { error in
            guard case ConfigError.fileNotFound = error else {
                return XCTFail("expected fileNotFound, got \(error)")
            }
        }
    }

    /// Errors name the path the caller passed rather than the resolved
    /// one, so the message matches what is in the plist or on the
    /// command line.
    func testErrorsReportTheOriginalPathNotTheTarget() throws {
        let link = path("config")
        try FileManager.default.createSymbolicLink(
          atPath: link, withDestinationPath: "../nowhere/missing")
        XCTAssertThrowsError(try loader.validatePath(link)) { error in
            guard case ConfigError.fileNotFound(let reported) = error else {
                return XCTFail("expected fileNotFound, got \(error)")
            }
            XCTAssertEqual(reported, link)
        }
    }

    // MARK: - loadConfigFile

    func testNilPathYieldsNoApps() throws {
        XCTAssertEqual(try loader.loadConfigFile(nil), [])
    }

    func testBlankLinesAndSurroundingWhitespaceAreDropped() throws {
        let file = try write("Alacritty\n\n  Ghostty  \n\t\n kitty\n", to: "config")
        XCTAssertEqual(try loader.loadConfigFile(file), ["Alacritty", "Ghostty", "kitty"])
    }

    func testEmptyFileYieldsNoApps() throws {
        let file = try write("", to: "config")
        XCTAssertEqual(try loader.loadConfigFile(file), [])
    }

    func testLoadFollowsARelativeSymlinkFromAnUnrelatedWorkingDirectory() throws {
        let (link, _) = try makeRelativeSymlink(contents: "Ghostty\n")
        XCTAssertTrue(FileManager.default.changeCurrentDirectoryPath("/"))
        XCTAssertEqual(try loader.loadConfigFile(link), ["Ghostty"])
    }
}
