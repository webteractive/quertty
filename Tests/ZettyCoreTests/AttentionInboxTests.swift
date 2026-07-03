import Foundation
import Testing
@testable import ZettyCore

private let a = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
private let b = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!

@Test func unreadIsTheAttentionSetMinusAcknowledged() {
    let inbox = AttentionInbox()
    inbox.update(needsAttention: [a, b])
    #expect(inbox.unread == [a, b])

    inbox.acknowledge(a)
    #expect(inbox.unread == [b])
    #expect(inbox.unreadCount == 1)
}

@Test func acknowledgeAllEmptiesUnread() {
    let inbox = AttentionInbox()
    inbox.update(needsAttention: [a, b])
    inbox.acknowledgeAll()
    #expect(inbox.unread.isEmpty)
    #expect(inbox.unreadCount == 0)
}

@Test func attentionEpisodeEndResetsTheReadMark() {
    let inbox = AttentionInbox()
    inbox.update(needsAttention: [a])
    inbox.acknowledge(a)
    #expect(inbox.unread.isEmpty)

    // The agent gets input (leaves needsAttention), then needs attention again:
    // that's a NEW episode — it must show as unread.
    inbox.update(needsAttention: [])
    inbox.update(needsAttention: [a])
    #expect(inbox.unread == [a])
}

@Test func acknowledgingAnUnknownPaneIsHarmless() {
    let inbox = AttentionInbox()
    inbox.update(needsAttention: [a])
    inbox.acknowledge(b)
    #expect(inbox.unread == [a])
}

@Test func sidebarWidthClampsToBounds() {
    #expect(SidebarMetrics.clampWidth(100) == SidebarMetrics.minWidth)
    #expect(SidebarMetrics.clampWidth(999) == SidebarMetrics.maxWidth)
    #expect(SidebarMetrics.clampWidth(300) == 300)
    #expect(SidebarMetrics.defaultWidth == 244)
}
