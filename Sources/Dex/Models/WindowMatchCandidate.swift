import CoreGraphics
import Foundation

struct WindowMatchCandidate: Equatable {
    let windowID: CGWindowID
    let ownerPID: pid_t
    let title: String
    let bounds: CGRect
}

enum WindowMatchResolver {
    static func bestMatch(
        forPID pid: pid_t,
        title: String,
        frame: CGRect,
        in candidates: [WindowMatchCandidate],
        usedWindowIDs: inout Set<CGWindowID>
    ) -> WindowMatchCandidate? {
        let available = candidates.filter { candidate in
            candidate.ownerPID == pid && !usedWindowIDs.contains(candidate.windowID)
        }
        guard !available.isEmpty else { return nil }

        let exactTitleMatches = available.filter { !$0.title.isEmpty && $0.title == title }
        let pool = exactTitleMatches.isEmpty ? available : exactTitleMatches
        guard let match = pool.min(by: { lhs, rhs in
            lhs.bounds.distance(to: frame) < rhs.bounds.distance(to: frame)
        }) else {
            return nil
        }

        usedWindowIDs.insert(match.windowID)
        return match
    }
}

private extension CGRect {
    func distance(to other: CGRect) -> CGFloat {
        abs(minX - other.minX) +
            abs(minY - other.minY) +
            abs(width - other.width) +
            abs(height - other.height)
    }
}
