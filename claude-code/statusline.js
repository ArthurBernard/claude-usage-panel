#!/usr/bin/env node
// Claude Code status line: a condensed, one-line view of your Claude plan
// usage, rendered just under the prompt input. It reads only what Claude Code
// pipes on stdin — the context window, the account Session (5 h) / Week (7 d)
// rate limits, and the session transcript for a token total — so it needs no
// credentials, no network, and no cache of its own.
//
// The `normalizeUsage` and cache helpers below are retained (and covered by the
// cross-port parity and cache unit tests) as the shared normalization contract
// with the GNOME extension (lib/pure.js) and the macOS app; the status line
// itself renders from stdin. Output is left-aligned (Claude Code anchors the
// status line to the left; use the settings `padding` field to indent it).

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const CACHE_PATH = path.join(os.tmpdir(), 'claude-usage-statusline.json');
export const CACHE_TTL_MS = 120_000; // TTL for the shared on-disk cache helpers

// Short labels + ordering for the limit kinds the endpoint returns. Kept
// terse because the status line has little horizontal room.
const KIND_LABELS = {
  session: 'Session',
  weekly_all: 'Week',
  weekly_scoped: 'Week',
  weekly_oauth_apps: 'Apps',
};
const KIND_ORDER = ['session', 'weekly_all', 'weekly_scoped', 'weekly_oauth_apps'];

// ANSI palette. The status line renders ANSI, so we color each gauge by the
// API's own severity — green while healthy, yellow warning, red critical.
const SEV_COLOR = {
  normal: '\x1b[32m', // green
  warning: '\x1b[33m', // yellow
  critical: '\x1b[1;31m', // bold red
};
const DIM = '\x1b[2m';
const RESET = '\x1b[0m';

// Gauge glyphs: a full block, eighth-block fractions for sub-cell precision so
// even a few percent shows a sliver, and a light shade for the empty remainder.
const FULL = '█';
const FRACTIONS = ['', '▏', '▎', '▍', '▌', '▋', '▊', '▉'];
const EMPTY = '░';
const GAUGE_WIDTH = 6;

function normalizeLimit(entry) {
  const model = entry.scope?.model?.display_name;
  // For per-model limits the model name alone is the most informative and
  // compact label; otherwise use the short kind label.
  const label = model ?? KIND_LABELS[entry.kind] ?? entry.kind;
  return {
    kind: entry.kind,
    label,
    percent: Math.max(0, Math.min(100, Math.round(Number(entry.percent) || 0))),
    severity: entry.severity ?? 'normal',
    resetsAt: entry.resets_at ?? null,
    active: Boolean(entry.is_active),
  };
}

export function normalizeUsage(payload) {
  if (Array.isArray(payload?.limits) && payload.limits.length) {
    return payload.limits.map(normalizeLimit).sort((a, b) => {
      const ai = KIND_ORDER.indexOf(a.kind);
      const bi = KIND_ORDER.indexOf(b.kind);
      return (ai < 0 ? 99 : ai) - (bi < 0 ? 99 : bi);
    });
  }
  const cards = [];
  if (Number.isFinite(Number(payload?.five_hour?.utilization))) {
    cards.push({
      kind: 'session',
      label: KIND_LABELS.session,
      percent: Math.round(payload.five_hour.utilization),
      severity: 'normal',
      resetsAt: payload.five_hour.resets_at ?? null,
      active: true,
    });
  }
  if (Number.isFinite(Number(payload?.seven_day?.utilization))) {
    cards.push({
      kind: 'weekly_all',
      label: KIND_LABELS.weekly_all,
      percent: Math.round(payload.seven_day.utilization),
      severity: 'normal',
      resetsAt: payload.seven_day.resets_at ?? null,
      active: false,
    });
  }
  return cards;
}

// Returns {raw, fresh}: raw is the last cached payload (even when stale); fresh
// says whether it's within the TTL. null when there's no cache at all. `path`
// and `nowMs` are injectable so the cache logic is unit-testable.
export function readCache(path = CACHE_PATH, nowMs = Date.now()) {
  try {
    const stat = fs.statSync(path);
    const raw = JSON.parse(fs.readFileSync(path, 'utf8'));
    return {raw, fresh: nowMs - stat.mtimeMs <= CACHE_TTL_MS};
  } catch {
    return null;
  }
}

// Bump the cache mtime so a failed fetch backs off for another TTL instead of
// re-hitting (and re-triggering) a rate-limited endpoint on every refresh.
export function touchCache(path = CACHE_PATH, nowMs = Date.now()) {
  try {
    const secs = nowMs / 1000;
    fs.utimesSync(path, secs, secs);
  } catch {}
}

export function writeCache(raw, path = CACHE_PATH) {
  try {
    fs.writeFileSync(path, JSON.stringify(raw), {mode: 0o600});
  } catch {
    // A read-only tmp dir just means no cache; not fatal.
  }
}

// "Resets in 3h06m" / "4d2h" — compact, only the two most significant units.
export function resetHint(resetsAt) {
  if (!resetsAt) return '';
  const ms = new Date(resetsAt).getTime() - Date.now();
  if (!Number.isFinite(ms) || ms <= 0) return '';
  const mins = Math.round(ms / 60_000);
  const d = Math.floor(mins / 1440);
  const h = Math.floor((mins % 1440) / 60);
  const m = mins % 60;
  if (d > 0) return ` ${d}d${h}h`;
  if (h > 0) return ` ${h}h${String(m).padStart(2, '0')}m`;
  return ` ${m}m`;
}

// A compact fixed-width bar whose fill (colored by severity) tracks the
// percentage down to 1/8 of a cell, with the remainder dimmed.
export function gauge(percent, color) {
  const eighths = Math.round((percent / 100) * GAUGE_WIDTH * 8);
  const full = Math.floor(eighths / 8);
  const rem = eighths % 8;
  const bar = FULL.repeat(full) + (rem ? FRACTIONS[rem] : '');
  const empty = EMPTY.repeat(Math.max(0, GAUGE_WIDTH - full - (rem ? 1 : 0)));
  return `${color}${bar}${DIM}${empty}${RESET}`;
}

export function render(cards) {
  const active = cards.filter((c) => c.active || c.percent > 0);
  const shown = active.length ? active : cards;
  if (!shown.length) return '';

  // A reset countdown is shown once, after the LAST limit that displays the same
  // value — so a weekly reset shared by Week and each per-model card (whose raw
  // timestamps differ by microseconds but render identically) isn't repeated.
  const hints = shown.map((c) => resetHint(c.resetsAt));
  const lastWithHint = new Map();
  hints.forEach((h, i) => {
    if (h) lastWithHint.set(h, i);
  });

  return shown
    .map((c, i) => {
      const color = SEV_COLOR[c.severity] ?? SEV_COLOR.normal;
      const reset = lastWithHint.get(hints[i]) === i ? `${DIM}${hints[i]}${RESET}` : '';
      return `${c.label} ${gauge(c.percent, color)} ${color}${c.percent}%${RESET}${reset}`;
    })
    .join('  ');
}

// Severity for values that carry no API severity (context, stdin fallback):
// green under 70 %, yellow up to 90 %, red above.
const thresholdSeverity = (p) => (p >= 90 ? 'critical' : p >= 70 ? 'warning' : 'normal');

// A "Context" card for the context-window usage Claude Code passes on stdin,
// rendered in the same gauge format as the plan limits. Returns '' when the
// field is absent (older Claude Code) or stdin isn't valid JSON.
export function contextSegment(stdinText) {
  let pct;
  try {
    pct = JSON.parse(stdinText)?.context_window?.used_percentage;
  } catch {
    return '';
  }
  if (!Number.isFinite(Number(pct))) return '';
  const p = Math.round(Number(pct));
  const color = SEV_COLOR[thresholdSeverity(p)];
  return `Context ${gauge(p, color)} ${color}${p}%${RESET}`;
}

// Fallback source: the Session (five_hour) and Week (seven_day) rate limits
// Claude Code passes on stdin. No per-model (Fable) and no severity, so colors
// use a local threshold; resets_at is epoch seconds and converted to ISO.
export function cardsFromStdin(stdinText) {
  let rl;
  try {
    rl = JSON.parse(stdinText)?.rate_limits;
  } catch {
    return [];
  }
  const cards = [];
  const add = (win, kind, label) => {
    const pct = Math.round(Number(win?.used_percentage));
    if (!Number.isFinite(pct)) return;
    const p = Math.max(0, Math.min(100, pct));
    const secs = Number(win.resets_at);
    cards.push({
      kind,
      label,
      percent: p,
      severity: thresholdSeverity(p),
      resetsAt: Number.isFinite(secs) ? new Date(secs * 1000).toISOString() : null,
      active: true,
    });
  };
  add(rl?.five_hour, 'session', KIND_LABELS.session);
  add(rl?.seven_day, 'weekly_all', KIND_LABELS.weekly_all);
  return cards;
}

// Compact token count: 847 → "847", 16_700 → "16.7k", 1_240_000 → "1.2M".
export function formatTokens(n) {
  if (n >= 1e6) return `${(n / 1e6).toFixed(1)}M`;
  if (n >= 1e3) return `${(n / 1e3).toFixed(1)}k`;
  return String(n);
}

// Sum every token each assistant turn consumed — prompt, cache writes, cache
// reads and completion — across all assistant messages in the session
// transcript (a JSONL, one message per line). Deduped by message id so a
// replayed line isn't counted twice. Cache reads dominate a long session, so
// this is the true throughput; pass includeCacheRead=false for "fresh" tokens.
export function sumTranscriptTokens(jsonlText, includeCacheRead = true) {
  let total = 0;
  const seen = new Set();
  for (const line of jsonlText.split('\n')) {
    if (!line) continue;
    let o;
    try {
      o = JSON.parse(line);
    } catch {
      continue; // a partial last line while Claude Code is writing — skip it
    }
    const u = o?.message?.usage;
    if (!u) continue;
    const id = o.message?.id;
    if (id) {
      if (seen.has(id)) continue;
      seen.add(id);
    }
    total += (Number(u.input_tokens) || 0) +
      (Number(u.output_tokens) || 0) +
      (Number(u.cache_creation_input_tokens) || 0) +
      (includeCacheRead ? (Number(u.cache_read_input_tokens) || 0) : 0);
  }
  return total;
}

// The "∑ N tok" total-tokens card: the cumulative tokens this window has
// consumed. Reads the session transcript Claude Code points to on stdin
// (transcript_path) and sums each turn's usage. Returns '' when the path is
// absent (e.g. before the first turn) or unreadable. readFile is injectable so
// the parsing can be unit-tested without touching disk.
export function tokensSegment(stdinText, {
  includeCacheRead = true,
  readFile = (p) => fs.readFileSync(p, 'utf8'),
} = {}) {
  let p;
  try {
    p = JSON.parse(stdinText)?.transcript_path;
  } catch {
    return '';
  }
  if (!p) return '';
  let text;
  try {
    text = readFile(p);
  } catch {
    return ''; // transcript not on disk yet, or not readable
  }
  const total = sumTranscriptTokens(text, includeCacheRead);
  if (!total) return '';
  return `${DIM}∑ ${formatTokens(total)} tok${RESET}`;
}

// The segments the line can show, keyed by the name used in --segments. Each
// takes the stdin text and the parsed config and returns its rendered string.
const SEGMENTS = {
  context: (stdin) => contextSegment(stdin),
  limits: (stdin) => render(cardsFromStdin(stdin)),
  tokens: (stdin, cfg) => tokensSegment(stdin, {includeCacheRead: cfg.includeCacheRead}),
};
const DEFAULT_SEGMENTS = ['context', 'limits', 'tokens'];

// Configure the line from the command's argv (install.sh bakes these into the
// settings.json command): `--segments=a,b,c` picks which segments to show and
// in what order; `--tokens=fresh` sums only new tokens (excludes cache reads).
// Unknown segment names are dropped; an empty/missing list falls back to all.
export function parseConfig(argv) {
  const cfg = {segments: DEFAULT_SEGMENTS, includeCacheRead: true};
  for (const arg of argv) {
    const seg = /^--segments=(.*)$/.exec(arg);
    if (seg) {
      const list = seg[1].split(',').map((s) => s.trim()).filter((s) => SEGMENTS[s]);
      if (list.length) cfg.segments = list;
    } else if (arg === '--tokens=fresh') {
      cfg.includeCacheRead = false;
    } else if (arg === '--tokens=all') {
      cfg.includeCacheRead = true;
    }
  }
  return cfg;
}

function readStdin() {
  try {
    return fs.readFileSync(0, 'utf8'); // fd 0; Claude Code always pipes JSON here
  } catch {
    return '';
  }
}

function main() {
  const cfg = parseConfig(process.argv.slice(2));
  const stdin = readStdin();
  // Claude Code left-anchors the status line (indent via the settings `padding`
  // field), so we just emit the chosen segments, in order, left-aligned. Context
  // is always available; Session/Week appear once Claude Code provides
  // rate_limits (Pro/Max, after the first API response of the session).
  const parts = cfg.segments.map((key) => SEGMENTS[key](stdin, cfg)).filter(Boolean);
  process.stdout.write(parts.join('  '));
}

// Only render when run directly; importing (e.g. from tests) is side-effect free.
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  // A status line must never crash if the reader closes the pipe early.
  process.stdout.on('error', (e) => {
    if (e.code === 'EPIPE') process.exit(0);
    throw e;
  });
  main();
}
