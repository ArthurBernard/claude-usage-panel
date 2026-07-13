#!/usr/bin/env node
// Claude Code status line: a condensed, one-line view of your Claude plan usage,
// rendered just under the prompt input. It reads ONLY what Claude Code pipes on
// stdin — the context window, the account Session (5 h) / Week (7 d) rate limits,
// and the session transcript for a token total — so it needs no credentials and
// no network. This is deliberately the cheap terminal projection: per-model
// (e.g. Fable) weekly limits and API severity are API-only and shown only by the
// GNOME extension and the macOS app, never here. Output is left-aligned (Claude
// Code anchors the line to the left; use the settings `padding` field to indent).

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

// Compact per-transcript token sums are cached here so a multi-MB JSONL isn't
// re-read and re-parsed on every refresh (see transcriptTotals).
const TOKENS_CACHE_PATH = path.join(os.tmpdir(), 'claude-usage-statusline-tokens.json');

// Short labels for the two rate-limit windows stdin exposes. Terse because the
// status line has little horizontal room.
const KIND_LABELS = {session: 'Session', weekly_all: 'Week'};

// ANSI palette. Each gauge is colored by severity — green healthy, yellow
// warning, red critical.
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
// percentage down to 1/8 of a cell, with the remainder dimmed. The percent is
// clamped to [0,100] here so no caller can overflow the width or (with a
// negative value) drive FULL.repeat() to throw — the line must never crash.
export function gauge(percent, color) {
  const p = Math.max(0, Math.min(100, Number(percent) || 0));
  const eighths = Math.round((p / 100) * GAUGE_WIDTH * 8);
  const full = Math.floor(eighths / 8);
  const rem = eighths % 8;
  const bar = FULL.repeat(full) + (rem ? FRACTIONS[rem] : '');
  const empty = EMPTY.repeat(Math.max(0, GAUGE_WIDTH - full - (rem ? 1 : 0)));
  return `${color}${bar}${DIM}${empty}${RESET}`;
}

// Severity for values that carry no API severity (context, stdin rate limits):
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
  const p = Math.max(0, Math.min(100, Math.round(Number(pct))));
  const color = SEV_COLOR[thresholdSeverity(p)];
  return `Context ${gauge(p, color)} ${color}${p}%${RESET}`;
}

// The Session (five_hour) and Week (seven_day) rate limits Claude Code passes on
// stdin. No per-model card and no API severity, so colors use a local threshold;
// resets_at is epoch seconds and converted to ISO.
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

export function render(cards) {
  const active = cards.filter((c) => c.active || c.percent > 0);
  const shown = active.length ? active : cards;
  if (!shown.length) return '';

  // A reset countdown is shown once, after the LAST limit that displays the same
  // value — so a weekly reset shared by several cards isn't repeated.
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

// Compact token count: 847 → "847", 16_700 → "16.7k", 1_240_000 → "1.2M". Guards
// the unit boundary so 999_999 promotes to "1.0M" rather than "1000.0k".
export function formatTokens(n) {
  if (n >= 1e6) return `${(n / 1e6).toFixed(1)}M`;
  if (n >= 1e3) {
    const k = (n / 1e3).toFixed(1);
    return k === '1000.0' ? '1.0M' : `${k}k`;
  }
  return String(n);
}

// Sum every token each assistant turn consumed — prompt, cache writes, cache
// reads and completion — across all assistant messages in the session transcript
// (a JSONL, one message per line). Deduped by message id so a replayed line
// isn't counted twice. Cache reads dominate a long session, so this is the true
// throughput; pass includeCacheRead=false for "fresh" tokens.
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

// {all, fresh} token totals for a transcript, cached on disk keyed by the file's
// path+mtime+size. Claude Code re-invokes this command on every refresh and a
// long transcript is tens of MB, so without this each refresh would re-read and
// re-parse the whole JSONL. Returns null when the transcript isn't on disk yet.
// stat/read/cachePath are injectable for tests.
export function transcriptTotals(p, {
  statFile = fs.statSync,
  readFile = (f) => fs.readFileSync(f, 'utf8'),
  cachePath = TOKENS_CACHE_PATH,
} = {}) {
  let sig;
  try {
    const st = statFile(p);
    sig = `${p}:${st.mtimeMs}:${st.size}`;
  } catch {
    return null; // transcript not on disk yet, or not readable
  }
  try {
    const cached = JSON.parse(fs.readFileSync(cachePath, 'utf8'));
    if (cached && cached.sig === sig) return cached;
  } catch {
    // no cache, unreadable, or a different transcript — recompute below.
  }
  let text;
  try {
    text = readFile(p);
  } catch {
    return null;
  }
  const totals = {
    sig,
    all: sumTranscriptTokens(text, true),
    fresh: sumTranscriptTokens(text, false),
  };
  try {
    fs.writeFileSync(cachePath, JSON.stringify(totals), {mode: 0o600});
  } catch {
    // A read-only tmp dir just means no cache; not fatal.
  }
  return totals;
}

// The "∑ N tok" card: cumulative tokens this window has consumed, from the
// transcript Claude Code points to on stdin (transcript_path). Returns '' when
// the path is absent (before the first turn) or unreadable.
export function tokensSegment(stdinText, {
  includeCacheRead = true,
  statFile,
  readFile,
  cachePath,
} = {}) {
  let p;
  try {
    p = JSON.parse(stdinText)?.transcript_path;
  } catch {
    return '';
  }
  if (!p) return '';
  const totals = transcriptTotals(p, {statFile, readFile, cachePath});
  if (!totals) return '';
  const total = includeCacheRead ? totals.all : totals.fresh;
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
// settings.json command): `--segments=a,b,c` picks which segments to show and in
// what order; `--tokens=fresh` sums only new tokens (excludes cache reads).
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
  // field), so we emit the chosen segments in order, left-aligned. Context is
  // always available; Session/Week appear once Claude Code provides rate_limits.
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
