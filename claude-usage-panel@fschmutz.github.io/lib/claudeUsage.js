// Data layer: read the local Claude Code OAuth token and query the official
// usage endpoint. Read-only — we never write back to the credentials file.

import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Soup from 'gi://Soup';

const USAGE_ENDPOINT = 'https://api.anthropic.com/api/oauth/usage';
const OAUTH_BETA_HEADER = 'oauth-2025-04-20';
const CREDENTIALS_PATH = `${GLib.get_home_dir()}/.claude/.credentials.json`;

// Human labels + ordering for the limit kinds the endpoint returns.
const KIND_LABELS = {
    session: 'Current session',
    weekly_all: 'Weekly · all models',
    weekly_scoped: 'Weekly',
    weekly_oauth_apps: 'Weekly · apps',
};

const KIND_ORDER = ['session', 'weekly_all', 'weekly_scoped', 'weekly_oauth_apps'];

/**
 * Read the OAuth access token from ~/.claude/.credentials.json.
 * Returns the token string, or null when missing / unreadable.
 */
export function readAccessToken() {
    try {
        const file = Gio.File.new_for_path(CREDENTIALS_PATH);
        const [ok, contents] = file.load_contents(null);
        if (!ok)
            return null;

        const decoder = new TextDecoder('utf-8');
        const json = JSON.parse(decoder.decode(contents));
        const oauth = json.claudeAiOauth ?? json;
        return oauth.accessToken ?? oauth.access_token ?? oauth.token ?? null;
    } catch {
        return null;
    }
}

/**
 * Turn a limit entry from the API into a normalized card model.
 */
function normalizeLimit(entry) {
    let label = KIND_LABELS[entry.kind] ?? entry.kind;
    const model = entry.scope?.model?.display_name;
    if (model)
        label = `${label} · ${model}`;

    return {
        key: entry.kind + (model ? `:${model}` : ''),
        label,
        percent: Math.max(0, Math.min(100, Math.round(Number(entry.percent) || 0))),
        severity: entry.severity ?? 'normal', // normal | warning | critical
        resetsAt: entry.resets_at ?? null,
        active: Boolean(entry.is_active),
    };
}

/**
 * Extract a list of normalized limit cards from the raw API payload.
 * Prefers the modern `limits[]` array; falls back to the legacy
 * five_hour / seven_day fields for older API shapes.
 */
export function normalizeUsage(payload) {
    if (Array.isArray(payload?.limits) && payload.limits.length) {
        return payload.limits
            .map(normalizeLimit)
            .sort((a, b) => {
                const ai = KIND_ORDER.indexOf(a.key.split(':')[0]);
                const bi = KIND_ORDER.indexOf(b.key.split(':')[0]);
                return (ai < 0 ? 99 : ai) - (bi < 0 ? 99 : bi);
            });
    }

    const cards = [];
    if (Number.isFinite(Number(payload?.five_hour?.utilization))) {
        cards.push({
            key: 'session',
            label: KIND_LABELS.session,
            percent: Math.round(payload.five_hour.utilization),
            severity: 'normal',
            resetsAt: payload.five_hour.resets_at ?? null,
            active: true,
        });
    }
    if (Number.isFinite(Number(payload?.seven_day?.utilization))) {
        cards.push({
            key: 'weekly_all',
            label: KIND_LABELS.weekly_all,
            percent: Math.round(payload.seven_day.utilization),
            severity: 'normal',
            resetsAt: payload.seven_day.resets_at ?? null,
            active: false,
        });
    }
    return cards;
}

/**
 * Fetch usage from the endpoint.
 * @returns {Promise<{ok: true, cards: object[], raw: object}
 *                   | {ok: false, code: string, message: string}>}
 */
export function fetchUsage(session) {
    return new Promise(resolve => {
        const token = readAccessToken();
        if (!token) {
            resolve({
                ok: false,
                code: 'no_token',
                message: 'No Claude credentials found. Sign in with Claude Code.',
            });
            return;
        }

        const message = Soup.Message.new('GET', USAGE_ENDPOINT);
        message.request_headers.append('authorization', `Bearer ${token}`);
        message.request_headers.append('anthropic-beta', OAUTH_BETA_HEADER);

        session.send_and_read_async(message, GLib.PRIORITY_DEFAULT, null, (self, result) => {
            try {
                const bytes = self.send_and_read_finish(result);
                const status = message.get_status();
                if (status === 401 || status === 403) {
                    resolve({
                        ok: false,
                        code: 'auth_expired',
                        message: 'Claude session expired. Run any Claude Code command to refresh.',
                    });
                    return;
                }
                if (status < 200 || status >= 300) {
                    resolve({ok: false, code: 'http_error', message: `HTTP ${status}`});
                    return;
                }

                const decoder = new TextDecoder('utf-8');
                const raw = JSON.parse(decoder.decode(bytes.get_data()));
                resolve({ok: true, cards: normalizeUsage(raw), raw});
            } catch (e) {
                resolve({ok: false, code: 'parse_error', message: e.message});
            }
        });
    });
}
