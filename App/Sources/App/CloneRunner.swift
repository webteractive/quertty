import Foundation
import ZettyCore

/// Executes clone process IO: the APFS copy-on-write duplication (with a
/// plain-copy fallback for non-APFS volumes) and git inside the clone/source.
/// All calls are blocking — run them off the main thread. Pure planning and
/// parsing live in `CloneSupport` (ZettyCore).
enum CloneRunner {

    struct Outcome {
        let usedCoW: Bool          // false → plain-copy fallback was used
        let branchError: String?   // non-nil → branch setup failed (non-fatal)
    }

    enum Failure: Error {
        case copyFailed(String)

        var message: String {
            switch self { case .copyFailed(let m): return m }
        }
    }

    /// Copies the source directory to the plan's target (`cp -Rc`, falling
    /// back to `cp -R`), then creates the clone branch when the copy is a git
    /// repo. A failed copy deletes the partial target and reports the error;
    /// a failed branch is non-fatal (`Outcome.branchError`).
    static func clone(_ plan: ClonePlan) -> Result<Outcome, Failure> {
        let fm = FileManager.default
        let root = CloneSupport.clonesRoot(home: NSHomeDirectory())
        do {
            try fm.createDirectory(atPath: root, withIntermediateDirectories: true)
        } catch {
            return .failure(.copyFailed("cannot create \(root): \(error.localizedDescription)"))
        }
        guard !fm.fileExists(atPath: plan.targetPath) else {
            return .failure(.copyFailed("target already exists: \(plan.targetPath)"))
        }

        var usedCoW = true
        if runProcess("/bin/cp", ["-Rc", plan.sourceRootPath, plan.targetPath]) != nil {
            // clonefile unavailable (non-APFS) or failed midway — clean up and
            // fall back to a byte copy.
            try? fm.removeItem(atPath: plan.targetPath)
            usedCoW = false
            if let error = runProcess("/bin/cp", ["-R", plan.sourceRootPath, plan.targetPath]) {
                try? fm.removeItem(atPath: plan.targetPath)
                return .failure(.copyFailed(error))
            }
        }

        var branchError: String?
        let gitDir = (plan.targetPath as NSString).appendingPathComponent(".git")
        if fm.fileExists(atPath: gitDir) {
            branchError = runGit(CloneSupport.createBranchArgs(branch: plan.branchName),
                                 in: plan.targetPath)
        }
        return .success(Outcome(usedCoW: usedCoW, branchError: branchError))
    }

    /// Runs `git -C <directory> <args>`; nil on success, stderr/exit message on failure.
    static func runGit(_ args: [String], in directory: String) -> String? {
        runProcess("/usr/bin/git", ["-C", directory] + args)
    }

    /// Runs `git -C <directory> <args>`; stdout on success (exit 0), nil on failure.
    static func runGitOutput(_ args: [String], in directory: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory] + args
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        // Read to EOF before waiting so a large listing can't deadlock the pipe.
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Runs an executable to completion; nil on success, an error message
    /// (stderr or exit status) on failure.
    private static func runProcess(_ launchPath: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let stderr = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = stderr
        do { try process.run() } catch { return error.localizedDescription }
        let data = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return text.isEmpty
                ? "\(launchPath) exited \(process.terminationStatus)" : text
        }
        return nil
    }
}
