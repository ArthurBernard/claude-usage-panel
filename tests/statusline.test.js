import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import {
    normalizeUsage, gauge, resetHint, render, contextSegment, cardsFromStdin,
    readCache, writeCache, touchCache, CACHE_TTL_MS,
} from '../claude-code/statusline.js';

// Strip ANSI so we can assert on the visible glyphs. Built via RegExp
// constructor to keep the ESC control char out of a regex literal.
const ESC = String.fromCharCode(27);
const strip = (s) => s.replace(new RegExp(`${ESC}\\[[0-9;]*m`, 'g'), '');

test('gauge is full at 100%, empty at 0%', () => {
    assert.match(strip(gauge(100, '')), /^█{6}$/);
    assert.match(strip(gauge(0, '')), /^░{6}$/);
    assert.equal(strip(gauge(50, '')).split('█').length - 1, 3);
});

test('gauge shows a sub-cell sliver for small non-zero values', () => {
    // 4% must not render as an entirely empty bar.
    assert.ok(!/^░{6}$/.test(strip(gauge(4, ''))));
});

test('resetHint formats the two most significant units, blank when past', () => {
    assert.equal(resetHint(null), '');
    const future = Date.now() + 2 * 24 * 60 * 60 * 1000 + 60 * 60 * 1000;
    assert.equal(resetHint(new Date(future).toISOString()), ' 2d1h');
    assert.equal(resetHint(new Date(Date.now() - 1000).toISOString()), '');
});

test('normalizeUsage yields short labels for the status line', () => {
    const cards = normalizeUsage({
        limits: [
            {kind: 'session', percent: 11, severity: 'normal', is_active: true},
            {kind: 'weekly_all', percent: 22, severity: 'warning', is_active: false},
            {kind: 'weekly_scoped', percent: 29, severity: 'normal', is_active: false,
                scope: {model: {display_name: 'Fable'}}},
        ],
    });
    assert.deepEqual(cards.map((c) => c.label), ['Session', 'Week', 'Fable']);
});

test('render draws one gauge per shown limit, space-separated', () => {
    const cards = normalizeUsage({
        limits: [
            {kind: 'session', percent: 11, severity: 'normal', is_active: true},
            {kind: 'weekly_all', percent: 22, severity: 'warning', is_active: false},
        ],
    });
    const out = strip(render(cards));
    assert.match(out, /Session [█▏▎▍▌▋▊▉░]{6} 11%/); // label + 6-cell gauge + percent
    assert.match(out, /Week [█▏▎▍▌▋▊▉░]{6} 22%/);
    assert.ok(out.includes('  ')); // discreet double-space separator
});

test('render shows a shared reset once, after the last limit that has it', () => {
    const base = Date.now() + 25 * 60 * 60 * 1000; // ~1d1h out → day-scale hint
    // Two timestamps a few ms apart render to the same value ("1d1h").
    const t1 = new Date(base + 1).toISOString();
    const t2 = new Date(base + 400).toISOString();
    const cards = normalizeUsage({
        limits: [
            {kind: 'weekly_all', percent: 22, severity: 'normal', resets_at: t1, is_active: true},
            {kind: 'weekly_scoped', percent: 29, severity: 'normal', resets_at: t2, is_active: true,
                scope: {model: {display_name: 'Fable'}}},
        ],
    });
    const out = strip(render(cards));
    assert.match(out, /Week [█▏▎▍▌▋▊▉░]{6} 22%  Fable/); // Week: no countdown of its own
    assert.match(out, /Fable [█▏▎▍▌▋▊▉░]{6} 29% 1d1h/); // shared countdown after Fable
    assert.equal((out.match(/1d1h/g) || []).length, 1); // exactly once
});

test('contextSegment renders a gauge card like the plan limits, blank when absent', () => {
    assert.match(strip(contextSegment('{"context_window":{"used_percentage":8}}')),
        /^Context [█▏▎▍▌▋▊▉░]{6} 8%$/);
    assert.match(strip(contextSegment('{"context_window":{"used_percentage":73.6}}')),
        /^Context [█▏▎▍▌▋▊▉░]{6} 74%$/);
    assert.equal(contextSegment('{}'), '');
    assert.equal(contextSegment('not json'), '');
});

test('cardsFromStdin builds Session/Week cards from rate_limits', () => {
    const in3h = Math.floor((Date.now() + 3 * 60 * 60 * 1000) / 1000); // epoch seconds
    const in2d = Math.floor((Date.now() + 2 * 24 * 60 * 60 * 1000) / 1000);
    const cards = cardsFromStdin(JSON.stringify({
        rate_limits: {
            five_hour: {used_percentage: 14, resets_at: in3h},
            seven_day: {used_percentage: 92, resets_at: in2d},
        },
    }));
    assert.deepEqual(cards.map((c) => c.label), ['Session', 'Week']);
    assert.equal(cards[0].percent, 14);
    assert.equal(cards[0].severity, 'normal'); // local threshold
    assert.equal(cards[1].severity, 'critical'); // 92% ≥ 90
    // epoch-seconds resets_at is converted so resetHint renders it
    assert.match(strip(render(cards)), /Session [█▏▎▍▌▋▊▉░]{6} 14% \dh\d{2}m/);
    assert.deepEqual(cardsFromStdin('{}'), []);
    assert.deepEqual(cardsFromStdin('not json'), []);
});

// A unique temp cache path per invocation, cleaned up after each test.
const rnd = () => Math.random().toString(36).slice(2);
const tmpCache = () => path.join(os.tmpdir(), `cus-test-${rnd()}${rnd()}.json`);

test('writeCache round-trips through readCache', () => {
    const p = tmpCache();
    try {
        assert.equal(readCache(p), null); // nothing cached yet
        writeCache({limits: [{kind: 'session', percent: 7}]}, p);
        const got = readCache(p);
        assert.deepEqual(got.raw, {limits: [{kind: 'session', percent: 7}]});
        assert.equal(got.fresh, true);
    } finally {
        fs.rmSync(p, {force: true});
    }
});

test('readCache freshness flips exactly at the TTL boundary', () => {
    const p = tmpCache();
    try {
        writeCache({ok: 1}, p);
        const mtime = fs.statSync(p).mtimeMs;
        assert.equal(readCache(p, mtime + CACHE_TTL_MS).fresh, true); // <= TTL: fresh
        assert.equal(readCache(p, mtime + CACHE_TTL_MS + 1).fresh, false); // past TTL: stale
        assert.deepEqual(readCache(p, mtime + 10 * CACHE_TTL_MS).raw, {ok: 1}); // stale still returns data
    } finally {
        fs.rmSync(p, {force: true});
    }
});

test('touchCache backs off by advancing mtime, keeping the payload', () => {
    const p = tmpCache();
    try {
        writeCache({ok: 1}, p);
        const t0 = fs.statSync(p).mtimeMs;
        const later = t0 + 5 * CACHE_TTL_MS;
        // Simulate a failed fetch that backs off: touch to "now" = later.
        touchCache(p, later);
        // At `later` the cache reads fresh again (mtime moved forward), so the
        // next refresh won't re-hit the rate-limited endpoint.
        const got = readCache(p, later);
        assert.equal(got.fresh, true);
        assert.deepEqual(got.raw, {ok: 1});
        assert.ok(fs.statSync(p).mtimeMs >= t0 + 4 * CACHE_TTL_MS); // mtime advanced
    } finally {
        fs.rmSync(p, {force: true});
    }
});
