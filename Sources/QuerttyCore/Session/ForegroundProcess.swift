import Foundation

/// Resolves what a preserved pane is actually running, from a `ps` snapshot.
///
/// libghostty exposes no PTY/pid, but a zmx-backed pane does: `zmx list` gives
/// the session's root shell pid. That pid's TTY hosts one foreground process
/// group — its leader is "the CLI running in the pane" (codex, claude, vim …).
/// A shell as the foreground leader means the pane is idle at a prompt.
public enum ForegroundProcess {

    struct Row {
        let pid: Int32
        let pgid: Int32
        let stat: String
        let tty: String
        let comm: String
    }

    /// The foreground command on the TTY of `sessionPID`, from the output of
    /// `ps -axo pid=,pgid=,stat=,tty=,comm=`. Returns the process-group
    /// leader's binary basename, or nil when the pane is idle (shell in the
    /// foreground), the pid is unknown, or it has no TTY.
    public static func command(forSessionPID sessionPID: Int32, psOutput: String) -> String? {
        let rows = parse(psOutput)
        guard let session = rows.first(where: { $0.pid == sessionPID }),
              !session.tty.isEmpty, session.tty != "??" else { return nil }

        let foreground = rows.filter { $0.tty == session.tty && $0.stat.contains("+") }
        guard let leader = foreground.first(where: { $0.pid == $0.pgid }) ?? foreground.first else {
            return nil
        }
        let name = basename(of: leader.comm)
        return TabTitle.isShellName(name) ? nil : name
    }

    // MARK: - Parsing

    private static func parse(_ output: String) -> [Row] {
        output.split(separator: "\n").compactMap { line in
            // pid pgid stat tty comm — comm is the remainder (may contain spaces).
            let fields = line.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
            guard fields.count == 5,
                  let pid = Int32(fields[0]), let pgid = Int32(fields[1]) else { return nil }
            return Row(
                pid: pid,
                pgid: pgid,
                stat: String(fields[2]),
                tty: String(fields[3]),
                comm: fields[4].trimmingCharacters(in: .whitespaces)
            )
        }
    }

    private static func basename(of command: String) -> String {
        command.contains("/") ? URL(fileURLWithPath: command).lastPathComponent : command
    }
}
