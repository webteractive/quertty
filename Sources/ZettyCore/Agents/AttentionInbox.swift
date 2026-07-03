import Foundation

/// Read/unread bookkeeping for the in-app attention bell.
///
/// Agent state stays the source of truth for WHO needs attention; the inbox
/// only tracks which of those the user has already seen. A read mark applies
/// to the current attention episode: when a pane leaves the needs-attention
/// set (its agent got input), the mark is dropped, so the pane's NEXT episode
/// shows as unread again. State is session-scoped by design — nothing here
/// is persisted.
public final class AttentionInbox {

    /// Panes currently needing attention (mirrors agent state).
    private var needsAttention: Set<UUID> = []
    /// Panes the user has seen during their current attention episode.
    private var acknowledged: Set<UUID> = []

    public init() {}

    /// Panes needing attention that the user hasn't seen yet.
    public var unread: Set<UUID> { needsAttention.subtracting(acknowledged) }

    public var unreadCount: Int { unread.count }

    /// Syncs the inbox with the current needs-attention set. Panes that left
    /// the set lose their read mark (their episode ended).
    public func update(needsAttention current: Set<UUID>) {
        needsAttention = current
        acknowledged.formIntersection(current)
    }

    /// Marks one pane's current episode as read (the user visited it).
    public func acknowledge(_ id: UUID) {
        guard needsAttention.contains(id) else { return }
        acknowledged.insert(id)
    }

    /// Marks every current episode as read ("Clear All").
    public func acknowledgeAll() {
        acknowledged = needsAttention
    }
}
