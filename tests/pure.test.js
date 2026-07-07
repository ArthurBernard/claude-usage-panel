import {test} from 'node:test';
import assert from 'node:assert/strict';

import {
    clampPercent, severityClass, normalizeUsage, sparkline,
    formatResets, alertThreshold, summarizeCursorSpend, summarizeCursorToday,
} from '../claude-usage-panel@fschmutz.github.io/lib/pure.js';

test('clampPercent clamps and rounds', () => {
    assert.equal(clampPercent(42.4), 42);
    assert.equal(clampPercent(-5), 0);
    assert.equal(clampPercent(150), 100);
    assert.equal(clampPercent('nope'), 0);
});

test('severityClass maps severities', () => {
    assert.equal(severityClass('critical'), 'cu-critical');
    assert.equal(severityClass('warning'), 'cu-warning');
    assert.equal(severityClass('normal'), 'cu-normal');
    assert.equal(severityClass(undefined), 'cu-normal');
});

test('normalizeUsage reads limits[] incl per-model, sorted', () => {
    const cards = normalizeUsage({
        limits: [
            {kind: 'weekly_scoped', percent: 100, severity: 'critical',
                resets_at: '2026-07-07T06:00:00Z', is_active: true,
                scope: {model: {display_name: 'Fable'}}},
            {kind: 'session', percent: 42, severity: 'normal', is_active: false},
            {kind: 'weekly_all', percent: 72, severity: 'normal'},
        ],
    });
    assert.deepEqual(cards.map(c => c.key),
        ['session', 'weekly_all', 'weekly_scoped:Fable']);
    const fable = cards.find(c => c.key === 'weekly_scoped:Fable');
    assert.equal(fable.label, 'Weekly · Fable');
    assert.equal(fable.percent, 100);
    assert.equal(fable.severity, 'critical');
    assert.equal(fable.active, true);
});

test('normalizeUsage falls back to legacy fields', () => {
    const cards = normalizeUsage({
        five_hour: {utilization: 10, resets_at: 'x'},
        seven_day: {utilization: 55},
    });
    assert.equal(cards.length, 2);
    assert.equal(cards[0].key, 'session');
    assert.equal(cards[0].active, true);
    assert.equal(cards[1].percent, 55);
});

test('normalizeUsage returns [] for empty payloads', () => {
    assert.deepEqual(normalizeUsage({}), []);
    assert.deepEqual(normalizeUsage({limits: []}), []);
});

test('sparkline needs >=2 samples and maps to blocks', () => {
    assert.equal(sparkline([]), '');
    assert.equal(sparkline([50]), '');
    assert.equal(sparkline([0, 100]).length, 2);
    assert.equal(sparkline([100, 100]), '██');
    assert.equal(sparkline([0, 0]).startsWith(' '), true);
});

test('formatResets formats with injected now', () => {
    const now = Date.parse('2026-07-01T00:00:00Z');
    assert.equal(formatResets('2026-07-01T03:06:00Z', now), 'Resets in 3h 06m');
    assert.equal(formatResets('2026-07-05T02:00:00Z', now), 'Resets in 4d 2h');
    assert.equal(formatResets('2026-07-01T00:00:00Z', now), 'Resetting…');
    assert.equal(formatResets(null, now), '');
    assert.equal(formatResets('not-a-date', now), '');
});

test('alertThreshold buckets 0/90/100', () => {
    assert.equal(alertThreshold(0), 0);
    assert.equal(alertThreshold(89), 0);
    assert.equal(alertThreshold(90), 90);
    assert.equal(alertThreshold(99), 90);
    assert.equal(alertThreshold(100), 100);
});

test('summarizeCursorSpend without a monthly limit → spend, no percent', () => {
    const s = summarizeCursorSpend([
        {email: 'a@x', overallSpendCents: 100000},
        {email: 'b@x', overallSpendCents: 25000},
    ]);
    assert.equal(s.cycleUSD, 1250);
    assert.equal(s.members, 2);
    assert.equal(s.percent, null);
    assert.equal(s.topSpender.email, 'a@x');
    assert.equal(s.topSpender.usd, 1000);
});

test('summarizeCursorSpend with a monthly limit → % gauge', () => {
    const s = summarizeCursorSpend([
        {email: 'a@x', overallSpendCents: 6000, monthlyLimitDollars: 100},
        {email: 'b@x', overallSpendCents: 0, monthlyLimitDollars: 100},
    ]);
    assert.equal(s.cycleUSD, 60);
    assert.equal(s.limitUSD, 200);
    assert.equal(s.percent, 30);
});

test('summarizeCursorToday sums chargedCents', () => {
    assert.equal(summarizeCursorToday([{chargedCents: 150}, {chargedCents: 89}]), 2.39);
    assert.equal(summarizeCursorToday([]), 0);
});
