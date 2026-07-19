#!/usr/bin/env node
// Claude Usage MCP server: exposes the same plan-usage data as the desktop
// panels through one Model Context Protocol tool (`get_usage`), so any MCP
// client — Claude Code, Cursor, Claude Desktop… — can ask "how much of my plan
// have I used?" in-conversation. Zero dependencies, stdio transport, read-only:
// it reads the OAuth token Claude Code already stores locally and calls the
// official usage endpoint, exactly like the GNOME extension and the macOS app.
//
// This is the fourth port of the shared normalization contract (see CLAUDE.md
// "one contract, N ports"): lib/pure.js (GNOME) · Model.swift (macOS) ·
// statusline.js (terminal) · this file. tests/parity.test.js keeps them in sync.

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
import {pathToFileURL} from 'node:url';

// Bumped by scripts/bump-version.sh — keep in sync with package.json.
export const VERSION = '1.5.0';

const USAGE_ENDPOINT = 'https://api.anthropic.com/api/oauth/usage';
const OAUTH_BETA_HEADER = 'oauth-2025-04-20';
const FETCH_TIMEOUT_MS = 10_000;

// Newest first; initialize echoes the client's requested version when we
// support it, otherwise answers with our newest (per the MCP spec).
const PROTOCOL_VERSIONS = ['2025-06-18', '2025-03-26', '2024-11-05'];

// ── Shared normalization contract (mirrors lib/pure.js) ─────────────────────────

const KIND_LABELS = {
  session: 'Current session',
  weekly_all: 'Weekly · all models',
  weekly_scoped: 'Weekly',
  weekly_oauth_apps: 'Weekly · apps',
};
const KIND_ORDER = ['session', 'weekly_all', 'weekly_scoped', 'weekly_oauth_apps'];

export function clampPercent(v) {
  const n = Number(v);
  if (!Number.isFinite(n)) return 0;
  return Math.max(0, Math.min(100, Math.round(n)));
}

function normalizeLimit(entry) {
  let label = KIND_LABELS[entry.kind] ?? entry.kind;
  const model = entry.scope?.model?.display_name;
  if (model) label = `${label} · ${model}`;
  return {
    key: entry.kind + (model ? `:${model}` : ''),
    label,
    percent: clampPercent(entry.percent),
    severity: entry.severity ?? 'normal',
    resetsAt: entry.resets_at ?? null,
    active: Boolean(entry.is_active),
  };
}

// Extract normalized limit cards from the raw usage payload. Prefers the modern
// `limits[]` array; falls back to legacy five_hour / seven_day fields.
export function normalizeUsage(payload) {
  if (Array.isArray(payload?.limits) && payload.limits.length) {
    return payload.limits.map(normalizeLimit).sort((a, b) => {
      const ai = KIND_ORDER.indexOf(a.key.split(':')[0]);
      const bi = KIND_ORDER.indexOf(b.key.split(':')[0]);
      return (ai < 0 ? 99 : ai) - (bi < 0 ? 99 : bi);
    });
  }
  const cards = [];
  if (Number.isFinite(Number(payload?.five_hour?.utilization))) {
    cards.push({
      key: 'session', label: KIND_LABELS.session,
      percent: clampPercent(payload.five_hour.utilization),
      severity: 'normal', resetsAt: payload.five_hour.resets_at ?? null, active: true,
    });
  }
  if (Number.isFinite(Number(payload?.seven_day?.utilization))) {
    cards.push({
      key: 'weekly_all', label: KIND_LABELS.weekly_all,
      percent: clampPercent(payload.seven_day.utilization),
      severity: 'normal', resetsAt: payload.seven_day.resets_at ?? null, active: false,
    });
  }
  return cards;
}

// "resets in 3h06m" / "4d2h" — the two most significant units, like the
// status line's resetHint.
export function resetHint(resetsAt, now = Date.now()) {
  if (!resetsAt) return '';
  const ms = new Date(resetsAt).getTime() - now;
  if (!Number.isFinite(ms) || ms <= 0) return '';
  const mins = Math.round(ms / 60_000);
  const d = Math.floor(mins / 1440);
  const h = Math.floor((mins % 1440) / 60);
  const m = mins % 60;
  if (d > 0) return `${d}d${h}h`;
  if (h > 0) return `${h}h${String(m).padStart(2, '0')}m`;
  return `${m}m`;
}

// ── Token + fetch (mirrors lib/claudeUsage.js / Usage.swift) ────────────────────

function tokenFromJSON(text) {
  try {
    const json = JSON.parse(text);
    const oauth = json.claudeAiOauth ?? json;
    return oauth.accessToken ?? oauth.access_token ?? oauth.token ?? null;
  } catch {
    return null;
  }
}

/**
 * Read the OAuth access token. On Linux it lives in
 * ~/.claude/.credentials.json; on macOS, Claude Code stores it in the login
 * Keychain, so we fall back to `security find-generic-password`.
 */
export function readAccessToken({homedir = os.homedir(), platform = process.platform} = {}) {
  try {
    const raw = fs.readFileSync(path.join(homedir, '.claude', '.credentials.json'), 'utf8');
    const token = tokenFromJSON(raw);
    if (token) return token;
  } catch {
    // fall through to the Keychain on macOS
  }
  if (platform === 'darwin') {
    for (const service of ['Claude Code-credentials', 'Claude Code', 'claude']) {
      try {
        const raw = execFileSync('/usr/bin/security',
          ['find-generic-password', '-s', service, '-w'],
          {encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore']}).trim();
        const token = tokenFromJSON(raw);
        if (token) return token;
      } catch {
        // try the next service name
      }
    }
  }
  return null;
}

/**
 * Fetch and normalize usage.
 * @returns {Promise<{ok: true, cards: object[], raw: object}
 *                   | {ok: false, code: string, message: string}>}
 */
export async function fetchUsage({fetchImpl = fetch, token = readAccessToken()} = {}) {
  if (!token) {
    return {
      ok: false, code: 'no_token',
      message: 'No Claude credentials found. Sign in with Claude Code first.',
    };
  }
  let response;
  try {
    response = await fetchImpl(USAGE_ENDPOINT, {
      headers: {
        authorization: `Bearer ${token}`,
        'anthropic-beta': OAUTH_BETA_HEADER,
      },
      signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
    });
  } catch (e) {
    return {ok: false, code: 'network_error', message: e.message};
  }
  if (response.status === 401 || response.status === 403) {
    return {
      ok: false, code: 'auth_expired',
      message: 'Claude session expired. Run any Claude Code command to refresh it.',
    };
  }
  if (!response.ok) return {ok: false, code: 'http_error', message: `HTTP ${response.status}`};
  try {
    const raw = await response.json();
    return {ok: true, cards: normalizeUsage(raw), raw};
  } catch (e) {
    return {ok: false, code: 'parse_error', message: e.message};
  }
}

// One markdown line per limit: label, percent, severity, reset countdown.
export function renderCards(cards, now = Date.now()) {
  if (!cards.length) return 'No plan limits reported by the usage endpoint.';
  return cards.map(c => {
    const reset = resetHint(c.resetsAt, now);
    const parts = [`**${c.label}** — ${c.percent}%`];
    if (c.severity !== 'normal') parts.push(c.severity.toUpperCase());
    if (reset) parts.push(`resets in ${reset}`);
    return `- ${parts.join(' · ')}`;
  }).join('\n');
}

// ── MCP plumbing (stdio JSON-RPC 2.0, newline-delimited) ────────────────────────

const GET_USAGE_TOOL = {
  name: 'get_usage',
  title: 'Claude plan usage',
  description:
    'Current Claude plan usage: session, weekly, and per-model limits — ' +
    'percent used, severity, and reset time for each, from the official ' +
    'Anthropic usage endpoint (same numbers as /usage).',
  inputSchema: {type: 'object', properties: {}, additionalProperties: false},
  outputSchema: {
    type: 'object',
    properties: {
      limits: {
        type: 'array',
        items: {
          type: 'object',
          properties: {
            key: {type: 'string'},
            label: {type: 'string'},
            percent: {type: 'integer', minimum: 0, maximum: 100},
            severity: {type: 'string', enum: ['normal', 'warning', 'critical']},
            resetsAt: {type: ['string', 'null']},
            active: {type: 'boolean'},
          },
          required: ['key', 'label', 'percent', 'severity'],
        },
      },
    },
    required: ['limits'],
  },
  annotations: {readOnlyHint: true, openWorldHint: true},
};

export async function handleRequest(msg, deps = {}) {
  switch (msg.method) {
    case 'initialize': {
      const requested = msg.params?.protocolVersion;
      const protocolVersion =
        PROTOCOL_VERSIONS.includes(requested) ? requested : PROTOCOL_VERSIONS[0];
      return {
        protocolVersion,
        capabilities: {tools: {listChanged: false}},
        serverInfo: {name: 'claude-usage', title: 'Claude Usage Panel', version: VERSION},
      };
    }
    case 'ping':
      return {};
    case 'tools/list':
      return {tools: [GET_USAGE_TOOL]};
    case 'tools/call': {
      if (msg.params?.name !== 'get_usage')
        throw new RpcError(-32602, `Unknown tool: ${msg.params?.name}`);
      const result = await fetchUsage(deps);
      if (!result.ok)
        return {content: [{type: 'text', text: `${result.code}: ${result.message}`}], isError: true};
      return {
        content: [{type: 'text', text: renderCards(result.cards)}],
        structuredContent: {limits: result.cards},
      };
    }
    default:
      throw new RpcError(-32601, `Method not found: ${msg.method}`);
  }
}

class RpcError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

function reply(id, body) {
  process.stdout.write(`${JSON.stringify({jsonrpc: '2.0', id, ...body})}\n`);
}

export function main() {
  let buffer = '';
  // In-flight request count: on stdin EOF we must let pending async work
  // (a tools/call mid-fetch) answer before exiting, not die mid-request.
  let pending = 0;
  let ended = false;
  const maybeExit = () => {
    if (ended && pending === 0) process.exit(0);
  };
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', chunk => {
    buffer += chunk;
    let nl;
    while ((nl = buffer.indexOf('\n')) >= 0) {
      const line = buffer.slice(0, nl).trim();
      buffer = buffer.slice(nl + 1);
      if (!line) continue;
      let msg;
      try {
        msg = JSON.parse(line);
      } catch {
        reply(null, {error: {code: -32700, message: 'Parse error'}});
        continue;
      }
      // Notifications (no id) expect no response; requests get exactly one.
      const isRequest = msg.id !== undefined && msg.id !== null;
      if (typeof msg.method !== 'string') {
        if (isRequest) reply(msg.id, {error: {code: -32600, message: 'Invalid request'}});
        continue;
      }
      if (!isRequest) continue;
      pending += 1;
      handleRequest(msg)
        .then(result => reply(msg.id, {result}))
        .catch(e => reply(msg.id, {
          error: {code: e instanceof RpcError ? e.code : -32603, message: e.message},
        }))
        .finally(() => {
          pending -= 1;
          maybeExit();
        });
    }
  });
  process.stdin.on('end', () => {
    ended = true;
    maybeExit();
  });
}

// Run when executed directly — including through the npm/npx bin shim, which
// invokes us via a node_modules/.bin symlink, so compare realpaths.
const invokedAs = (() => {
  try {
    return process.argv[1] && pathToFileURL(fs.realpathSync(process.argv[1])).href;
  } catch {
    return null;
  }
})();
if (invokedAs === import.meta.url) {
  main();
}
