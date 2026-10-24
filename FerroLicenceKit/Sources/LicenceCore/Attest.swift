public import Foundation

/// Recovering the stamp from a sample of identifiers (`docs/design.md` §8).
///
/// For each candidate key, count the version 7 identifiers whose last two
/// bytes equal the key's stamp for their own timestamp. Under the null
/// hypothesis each match is a Bernoulli trial with probability 2⁻¹⁶, so the
/// count is Binomial(n, 2⁻¹⁶) and its upper tail is the p-value.
public enum Attest {
    /// The chance that one identifier matches a key it was not minted with.
    public static let chanceMatch = 1.0 / 65_536.0

    /// A key to test the sample against.
    public struct Candidate: Sendable {
        public let label: String
        public let key: StampKey
        /// The last day of the licence, if it is one.
        public let notAfter: CivilDate?
        /// The first day it no longer counts, if revoked.
        public let revokedFrom: CivilDate?

        public init(label: String, key: StampKey, notAfter: CivilDate?, revokedFrom: CivilDate?) {
            self.label = label
            self.key = key
            self.notAfter = notAfter
            self.revokedFrom = revokedFrom
        }
    }

    /// One candidate's result.
    public struct Finding: Equatable, Sendable {
        public let label: String
        public let sampled: Int
        public let matched: Int
        public let pValue: Double
        public let firstMatch: Date?
        public let lastMatch: Date?
        public let matchedAfterNotAfter: Int
        public let matchedFromRevocation: Int
    }

    /// The whole report, most significant finding first.
    public struct Report: Equatable, Sendable {
        public let total: Int
        public let notV7: Int
        public let findings: [Finding]

        /// Identifiers that are version 7 and so carry a stamp.
        public var sampled: Int { total - notV7 }

        /// The finding that reaches `threshold`, if any.
        public func best(threshold: Double) -> Finding? {
            findings.first.flatMap { $0.matched > 0 && $0.pValue <= threshold ? $0 : nil }
        }
    }

    /// Test `ids` against every candidate.
    public static func run(_ ids: [UUID], candidates: [Candidate]) -> Report {
        let v7: [(UUID, UInt64)] = ids.compactMap { id in id.timestampMs.map { (id, $0) } }
        let unsorted: [Finding] = candidates.map { finding($0, v7) }
        // A stable sort: smallest p-value first, then most matches, then input order.
        let order: [Int] = unsorted.indices.sorted { i, j in
            let a = unsorted[i], b = unsorted[j]
            if a.pValue != b.pValue { return a.pValue < b.pValue }
            if a.matched != b.matched { return a.matched > b.matched }
            return i < j
        }
        return Report(total: ids.count, notV7: ids.count - v7.count, findings: order.map { unsorted[$0] })
    }

    static func finding(_ c: Candidate, _ v7: [(UUID, UInt64)]) -> Finding {
        var matched = 0, after = 0, revoked = 0
        var first: UInt64?, last: UInt64?
        for (id, ts) in v7 where c.key.carries(id) {
            matched += 1
            first = min(first ?? ts, ts)
            last = max(last ?? ts, ts)
            let day = CivilDate(Date(timeIntervalSince1970: TimeInterval(ts) / 1000))
            if let notAfter = c.notAfter, day > notAfter { after += 1 }
            if let from = c.revokedFrom, day >= from { revoked += 1 }
        }
        func date(_ ms: UInt64?) -> Date? { ms.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) } }
        return Finding(
            label: c.label, sampled: v7.count, matched: matched,
            pValue: binomialUpperTail(n: v7.count, k: matched, p: chanceMatch),
            firstMatch: date(first), lastMatch: date(last),
            matchedAfterNotAfter: after, matchedFromRevocation: revoked)
    }

    /// Every parseable UUID in `text`, in order, duplicates kept.
    public static func uuids(in text: String) -> [UUID] {
        text.split { !($0.isHexDigit || $0 == "-") }
            .filter { $0.count == 36 }
            .compactMap { UUID(uuidString: String($0)) }
    }

    /// `P[X ≥ k]` for `X ~ Binomial(n, p)`, summing whichever tail is small in
    /// log space and taking the complement for the other, exactly as the Rust
    /// checker does.
    public static func binomialUpperTail(n: Int, k: Int, p: Double) -> Double {
        if k == 0 { return 1 }
        if k > n || p <= 0 { return 0 }
        if p >= 1 { return 1 }
        if Double(k) <= Double(n) * p {
            return min(max(1 - lowerTail(n, k - 1, p), 0), 1)
        }
        return min(upperTail(n, k, p), 1)
    }

    static func lnPMF(_ n: Int, _ i: Int, _ p: Double) -> Double {
        let m = min(i, n - i)
        var lnChoose = 0.0
        if m > 0 {
            for j in 1...m { lnChoose += log(Double(n - m + j)) - log(Double(j)) }
        }
        return lnChoose + Double(i) * log(p) + Double(n - i) * log(1 - p)
    }

    static func upperTail(_ n: Int, _ k: Int, _ p: Double) -> Double {
        let ratio = log(p) - log(1 - p)
        var lnTerm = lnPMF(n, k, p)
        var total = 0.0
        var i = k
        while true {
            let term = exp(lnTerm)
            total += term
            if i >= n || term < Double.leastNormalMagnitude || term < total * 1e-17 { break }
            lnTerm += log(Double(n - i) / Double(i + 1)) + ratio
            i += 1
        }
        return total
    }

    static func lowerTail(_ n: Int, _ k: Int, _ p: Double) -> Double {
        let ratio = log(1 - p) - log(p)
        var lnTerm = lnPMF(n, k, p)
        var total = 0.0
        var i = k
        while true {
            let term = exp(lnTerm)
            total += term
            if i == 0 || term < Double.leastNormalMagnitude || term < total * 1e-17 { break }
            lnTerm += log(Double(i) / Double(n - i + 1)) + ratio
            i -= 1
        }
        return total
    }
}
