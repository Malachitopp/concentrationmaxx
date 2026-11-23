import Foundation

/// Fixed-window rate limiting for the auth routes (PLAN.md section 5). In memory,
/// which is enough for one small server instance.
actor RateLimiter {
    struct Rule: Sendable {
        var limit: Int
        var window: TimeInterval
    }

    private struct Bucket {
        var windowStart: Date
        var count: Int
    }

    private var buckets: [String: Bucket] = [:]
    private let now: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    /// Counts one attempt. Throws `rate_limited` once more than `rule.limit`
    /// attempts were made within the window.
    func hit(_ key: String, rule: Rule) throws {
        let current = self.now()
        var bucket = activeBucket(key, rule: rule, at: current) ?? Bucket(windowStart: current, count: 0)
        bucket.count += 1
        buckets[key] = bucket
        if bucket.count > rule.limit {
            throw APIError.rateLimited(retryAfter: retryAfter(bucket, rule: rule, at: current))
        }
        pruneIfLarge(at: current, rule: rule)
    }

    /// Counts a failure without throwing (used for failed logins).
    func record(_ key: String, rule: Rule) {
        let current = self.now()
        var bucket = activeBucket(key, rule: rule, at: current) ?? Bucket(windowStart: current, count: 0)
        bucket.count += 1
        buckets[key] = bucket
        pruneIfLarge(at: current, rule: rule)
    }

    /// Throws `rate_limited` if the key has already reached its limit.
    func check(_ key: String, rule: Rule) throws {
        let current = self.now()
        if let bucket = activeBucket(key, rule: rule, at: current), bucket.count >= rule.limit {
            throw APIError.rateLimited(retryAfter: retryAfter(bucket, rule: rule, at: current))
        }
    }

    func reset(_ key: String) {
        buckets[key] = nil
    }

    private func activeBucket(_ key: String, rule: Rule, at current: Date) -> Bucket? {
        guard let bucket = buckets[key] else { return nil }
        if current.timeIntervalSince(bucket.windowStart) >= rule.window {
            buckets[key] = nil
            return nil
        }
        return bucket
    }

    private func retryAfter(_ bucket: Bucket, rule: Rule, at current: Date) -> Int {
        Int((rule.window - current.timeIntervalSince(bucket.windowStart)).rounded(.up))
    }

    /// Drops expired windows now and then, so memory stays bounded.
    private func pruneIfLarge(at current: Date, rule: Rule) {
        guard buckets.count > 10_000 else { return }
        let longestWindow = max(rule.window, 60 * 60)
        buckets = buckets.filter { current.timeIntervalSince($0.value.windowStart) < longestWindow }
    }
}
