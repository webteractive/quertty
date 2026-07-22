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

        // cp exits nonzero when ANY entry fails; sockets/fifos always fail
        // (they can't be copied and are recreatable runtime artifacts), so a
        // copy whose only errors are those still counts as success — without
        // this, one stray .sock file forces a pointless full-copy fallback.
        var usedCoW = true
        if let error = runProcess("/bin/cp", ["-Rc", plan.sourceRootPath, plan.targetPath]),
           !CloneSupport.copyErrorsAreTolerable(error) {
            // clonefile unavailable (non-APFS) or failed midway — clean up and
            // fall back to a byte copy.
            try? fm.removeItem(atPath: plan.targetPath)
            usedCoW = false
            if let fallbackError = runProcess("/bin/cp", ["-R", plan.sourceRootPath, plan.targetPath]),
               !CloneSupport.copyErrorsAreTolerable(fallbackError) {
                try? fm.removeItem(atPath: plan.targetPath)
                return .failure(.copyFailed(CloneSupport.summarizeCopyErrors(fallbackError)))
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

    /// Runs `git -C <directory> <args>`, returning the exit status and combined
    /// stdout+stderr (trimmed) — used where the merge summary/conflict text matters.
    static func runGitResult(_ args: [String], in directory: String) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory] + args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return (-1, error.localizedDescription) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (process.terminationStatus, text)
    }

    /// True iff `git -C <directory> <args>` exits 0 (for predicate git commands).
    static func gitSucceeds(_ args: [String], in directory: String) -> Bool {
        runGitResult(args, in: directory).status == 0
    }

    // MARK: - Removal

    /// What deleting the clone at `cloneRoot` would lose. Blocking (spawns git).
    /// A non-repo clone reports `.clean` — there is no git work to save, and
    /// the whole-directory loss is inherent to removing a clone.
    static func probeWorkState(cloneRoot: String, sourceRoot: String) -> CloneWorkState {
        guard let porcelain = runGitOutput(["status", "--porcelain"], in: cloneRoot) else {
            return .clean   // not a git repo (or git unavailable)
        }
        let dirty = GitStatus.parseChangeCount(porcelain) > 0
        var unfetched = false
        if let tipRaw = runGitOutput(CloneSupport.tipArgs, in: cloneRoot),
           let sha = CloneSupport.parseTipSHA(tipRaw) {
            // The tip commit missing from the source's object store means the
            // clone has commits the original hasn't fetched yet.
            unfetched = runGitOutput(CloneSupport.commitExistsArgs(sha: sha), in: sourceRoot) == nil
        }
        return CloneSupport.workState(hasUncommittedChanges: dirty, hasUnfetchedCommits: unfetched)
    }

    /// Lands the clone's branch in the SOURCE repo as a local branch.
    /// nil on success; an error message on failure (nothing is deleted then).
    static func fetchBack(sourceRoot: String, clonePath: String, branch: String) -> String? {
        runGit(CloneSupport.fetchBackArgs(clonePath: clonePath, branch: branch), in: sourceRoot)
    }

    // MARK: - Update from source (source → clone)

    enum UpdateOutcome: Equatable {
        case updated(summary: String)  // source's latest merged into the clone cleanly
        case upToDate                  // clone already contains the source tip
        case conflicts(files: [String])// merge left in progress in the clone to resolve
        case refused(String)           // notGit / cloneDirty
        case failed(String)            // fetch/merge failed otherwise
    }

    /// Merges the SOURCE's current branch tip into the CLONE (leave-conflicts).
    /// Blocking — run off-main. Nothing is deleted; on conflict the clone is left
    /// mid-merge for the user to resolve, then commit + PR.
    static func updateFromSource(cloneRoot: String, sourceRoot: String) -> UpdateOutcome {
        let isCloneGit = (runGitOutput(CloneSupport.isGitWorkTreeArgs(), in: cloneRoot)?
            .trimmingCharacters(in: .whitespacesAndNewlines) == "true")
        let isSourceGit = (runGitOutput(CloneSupport.isGitWorkTreeArgs(), in: sourceRoot)?
            .trimmingCharacters(in: .whitespacesAndNewlines) == "true")
        let cloneDirty = GitStatus.parseChangeCount(
            runGitOutput(CloneSupport.cloneStatusArgs(), in: cloneRoot) ?? "") > 0

        switch CloneSupport.updateReadiness(isCloneGitWorkTree: isCloneGit,
                                            isSourceGitWorkTree: isSourceGit, cloneDirty: cloneDirty) {
        case .notGit:
            return .refused("clone or source is not a git repository — nothing to update")
        case .cloneDirty:
            return .refused("clone has uncommitted changes — commit them first, then update")
        case .ready:
            break
        }

        if let fetchError = runGit(CloneSupport.updateFetchArgs(sourcePath: sourceRoot), in: cloneRoot) {
            return .failed("fetch from source failed — nothing changed: \(fetchError)")
        }
        if gitSucceeds(CloneSupport.alreadyCurrentArgs, in: cloneRoot) {
            return .upToDate
        }
        let result = runGitResult(CloneSupport.updateMergeArgs, in: cloneRoot)
        if result.status == 0 {
            let summary = result.output.split(separator: "\n").first.map(String.init) ?? "updated"
            return .updated(summary: summary)
        }
        // Merge failed. If it's a conflict, LEAVE it in the clone to resolve.
        let conflicts = (runGitOutput(CloneSupport.conflictFilesArgs, in: cloneRoot) ?? "")
            .split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        if !conflicts.isEmpty { return .conflicts(files: conflicts) }
        // Non-conflict failure — abort so the clone isn't left half-merged.
        _ = runGit(["merge", "--abort"], in: cloneRoot)
        return .failed("update failed and was aborted: \(result.output)")
    }

    /// The clone's current branch — the branch its work actually lives on.
    /// Robust against renames: derived from the repo, not the project name.
    /// nil for a detached HEAD or non-repo.
    static func currentBranch(in cloneRoot: String) -> String? {
        guard let raw = runGitOutput(["rev-parse", "--abbrev-ref", "HEAD"], in: cloneRoot) else {
            return nil
        }
        let branch = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return (branch.isEmpty || branch == "HEAD") ? nil : branch
    }

    /// Deletes a clone directory — guarded to paths strictly inside
    /// ~/.zetty/clones. nil on success; an error message otherwise.
    static func deleteCloneDirectory(at path: String) -> String? {
        guard CloneSupport.isSafeToDelete(path: path, home: NSHomeDirectory()) else {
            return "refusing to delete \(path) — not inside ~/.zetty/clones"
        }
        do {
            try FileManager.default.removeItem(atPath: path)
            return nil
        } catch {
            return error.localizedDescription
        }
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
