// Optional Cursor layer: query the Cursor Admin API for team spend.
// Auth is HTTP Basic with the admin API key as the username (empty password).
// Cursor is usage-based (no fixed % limit), so we surface spend, not a gauge.

import GLib from 'gi://GLib';
import Soup from 'gi://Soup';

import {summarizeCursorSpend, summarizeCursorToday} from './pure.js';

const BASE = 'https://api.cursor.com';

function basicAuth(key) {
    const bytes = new TextEncoder().encode(`${key}:`);
    return `Basic ${GLib.base64_encode(bytes)}`;
}

function postJSON(session, key, path, body) {
    return new Promise((resolve, reject) => {
        const message = Soup.Message.new('POST', BASE + path);
        message.request_headers.append('authorization', basicAuth(key));
        const payload = new TextEncoder().encode(JSON.stringify(body));
        message.set_request_body_from_bytes('application/json', new GLib.Bytes(payload));

        session.send_and_read_async(message, GLib.PRIORITY_DEFAULT, null, (self, result) => {
            try {
                const buf = self.send_and_read_finish(result);
                const status = message.get_status();
                if (status === 401 || status === 403) {
                    reject(new Error('Cursor API key rejected'));
                    return;
                }
                if (status < 200 || status >= 300) {
                    reject(new Error(`Cursor HTTP ${status}`));
                    return;
                }
                resolve(JSON.parse(new TextDecoder('utf-8').decode(buf.get_data())));
            } catch (e) {
                reject(e);
            }
        });
    });
}

function startOfTodayMs() {
    const now = GLib.DateTime.new_now_local();
    const midnight = GLib.DateTime.new_local(
        now.get_year(), now.get_month(), now.get_day_of_month(), 0, 0, 0);
    return midnight.to_unix() * 1000;
}

/**
 * Fetch a compact Cursor spend summary.
 * @returns {Promise<{cycleUSD:number, topSpender:{email:string,usd:number}|null,
 *                     members:number, todayUSD:number}>}
 */
export async function fetchCursor(session, key) {
    const spend = await postJSON(session, key, '/teams/spend', {page: 1, pageSize: 100});
    const rows = spend.teamMemberSpend ?? spend.spend ?? [];
    const summary = summarizeCursorSpend(rows);

    // Today's charged spend (first page is enough for a headline figure).
    let todayUSD = null;
    try {
        const ev = await postJSON(session, key, '/teams/filtered-usage-events', {
            startDate: startOfTodayMs(),
            endDate: GLib.DateTime.new_now_local().to_unix() * 1000,
            page: 1,
            pageSize: 100,
        });
        todayUSD = summarizeCursorToday(ev.usageEvents ?? ev.events ?? []);
    } catch {
        todayUSD = null; // unknown; hidden in the UI
    }

    return {...summary, todayUSD};
}
