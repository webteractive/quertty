import Foundation

/// Pure decision for auto-hibernating a project. Kept free of clocks and AppKit
/// so it's fully testable; the app supplies `idleFor` and `isBusy`.
public enum HibernationPolicy {
    public static func shouldHibernate(
        idleFor: TimeInterval,
        hibernateAfter: TimeInterval,
        isBusy: Bool,
        isActive: Bool,
        isHibernated: Bool,
        autoDisabled: Bool
    ) -> Bool {
        guard hibernateAfter > 0 else { return false }   // feature off
        guard !isActive, !isHibernated, !autoDisabled, !isBusy else { return false }
        return idleFor >= hibernateAfter
    }
}
