import XCTest

@testable import ClaudeUsageCore

final class UsageNormalizerTests: XCTestCase {
    func testLimitsArrayIncludesPerModelAndSorts() {
        let cards = UsageNormalizer.normalize([
            "limits": [
                [
                    "kind": "weekly_scoped", "percent": 100, "severity": "critical",
                    "resets_at": "2026-07-07T06:00:00Z", "is_active": true,
                    "scope": ["model": ["display_name": "Fable"]],
                ],
                ["kind": "session", "percent": 42, "severity": "normal", "is_active": false],
                ["kind": "weekly_all", "percent": 72, "severity": "normal"],
            ]
        ])
        XCTAssertEqual(cards.map(\.id), ["session", "weekly_all", "weekly_scoped:Fable"])
        let fable = cards.first { $0.id == "weekly_scoped:Fable" }
        XCTAssertEqual(fable?.label, "Weekly · Fable")
        XCTAssertEqual(fable?.percent, 100)
        XCTAssertEqual(fable?.severity, .critical)
        XCTAssertEqual(fable?.active, true)
    }

    func testLegacyFallback() {
        let cards = UsageNormalizer.normalize([
            "five_hour": ["utilization": 10, "resets_at": "x"],
            "seven_day": ["utilization": 55],
        ])
        XCTAssertEqual(cards.count, 2)
        XCTAssertEqual(cards[0].id, "session")
        XCTAssertTrue(cards[0].active)
        XCTAssertEqual(cards[1].percent, 55)
    }

    func testEmptyPayloads() {
        XCTAssertTrue(UsageNormalizer.normalize([:]).isEmpty)
        XCTAssertTrue(UsageNormalizer.normalize(["limits": [[String: Any]]()]).isEmpty)
    }

    func testPercentClampAndRound() {
        let cards = UsageNormalizer.normalize([
            "limits": [["kind": "session", "percent": 142.6]]
        ])
        XCTAssertEqual(cards.first?.percent, 100)
    }
}

final class CursorMathTests: XCTestCase {
    func testSpendWithoutLimit() {
        let s = CursorMath.summarizeSpend([
            ["email": "a@x", "overallSpendCents": 100_000],
            ["email": "b@x", "overallSpendCents": 25000],
        ])
        XCTAssertEqual(s.cycleUSD, 1250)
        XCTAssertEqual(s.members, 2)
        XCTAssertNil(s.percent)
        XCTAssertEqual(s.top?.email, "a@x")
        XCTAssertEqual(s.top?.usd, 1000)
    }

    func testSpendWithLimitGivesGauge() {
        let s = CursorMath.summarizeSpend([
            ["email": "a@x", "overallSpendCents": 6000, "monthlyLimitDollars": 100],
            ["email": "b@x", "overallSpendCents": 0, "monthlyLimitDollars": 100],
        ])
        XCTAssertEqual(s.cycleUSD, 60)
        XCTAssertEqual(s.limitUSD, 200)
        XCTAssertEqual(s.percent, 30)
    }

    func testToday() {
        XCTAssertEqual(
            CursorMath.summarizeToday([["chargedCents": 150], ["chargedCents": 89]]), 2.39)
        XCTAssertEqual(CursorMath.summarizeToday([]), 0)
    }
}
