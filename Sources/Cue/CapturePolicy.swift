import CueCore
import Foundation

enum CapturePolicy {
    static func duplicate(
        body: String,
        now: Date,
        items: [WorkItem],
        windowSeconds: TimeInterval
    ) -> WorkItem? {
        let hash = ContentHasher.hash(body)
        return items.first {
            $0.contentHash == hash &&
                $0.state != .archived &&
                abs(now.timeIntervalSince($0.createdAt)) <= windowSeconds
        }
    }
}
