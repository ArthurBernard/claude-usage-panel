// Pure logic — no GJS/gi imports, so it is unit-testable under plain `node`.
// Shared by the extension (extension.js / claudeUsage.js / cursorUsage.js).

const KIND_LABELS = {
    session: 'Current session',
    weekly_all: 'Weekly · all models',
    weekly_scoped: 'Weekly',
    weekly_oauth_apps: 'Weekly · apps',
};
const KIND_ORDER = ['session', 'weekly_all', 'weekly_scoped', 'weekly_oauth_apps'];

const SPARK_BLOCKS = ' ▁▂▃▄▅▆▇█';

export function clampPercent(v) {
    const n = Number(v);
    if (!Number.isFinite(n))
        return 0;
    return Math.max(0, Math.min(100, Math.round(n)));
}

export function severityClass(severity) {
    if (severity === 'critical')
        return 'cu-critical';
    if (severity === 'warning')
        return 'cu-warning';
    return 'cu-normal';
}

function normalizeLimit(entry) {
    let label = KIND_LABELS[entry.kind] ?? entry.kind;
    const model = entry.scope?.model?.display_name;
    if (model)
        label = `${label} · ${model}`;
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

// Render a history array (percentages) as a unicode sparkline.
export function sparkline(history) {
    if (!history || history.length < 2)
        return '';
    return history.map(p => {
        const i = Math.max(0, Math.min(8, Math.round((p / 100) * 8)));
        return SPARK_BLOCKS[i];
    }).join('');
}

// "Resets in 3h 06m" / "Resets in 4d 2h". nowMs is injectable for tests.
export function formatResets(iso, nowMs = Date.now()) {
    if (!iso)
        return '';
    const target = Date.parse(iso);
    if (Number.isNaN(target))
        return '';
    let delta = Math.floor((target - nowMs) / 1000);
    if (delta <= 0)
        return 'Resetting…';
    const d = Math.floor(delta / 86400);
    delta %= 86400;
    const h = Math.floor(delta / 3600);
    const m = Math.floor((delta % 3600) / 60);
    let span;
    if (d > 0)
        span = `${d}d ${h}h`;
    else if (h > 0)
        span = `${h}h ${String(m).padStart(2, '0')}m`;
    else
        span = `${m}m`;
    return `Resets in ${span}`;
}

// Threshold a limit crossed (0 / 90 / 100), for alert logic.
export function alertThreshold(percent) {
    return percent >= 100 ? 100 : (percent >= 90 ? 90 : 0);
}

// Summarize Cursor /teams/spend rows into cycle spend, limit, %, top, members.
export function summarizeCursorSpend(rows) {
    let cycleCents = 0;
    let limitUSD = 0;
    let top = null;
    for (const r of rows ?? []) {
        const c = r.overallSpendCents ?? r.spendCents ?? 0;
        cycleCents += c;
        limitUSD += r.monthlyLimitDollars ?? 0;
        if (!top || c > top.cents)
            top = {email: r.email ?? r.name ?? '?', cents: c};
    }
    const cycleUSD = cycleCents / 100;
    return {
        cycleUSD,
        limitUSD,
        percent: limitUSD > 0 ? Math.min(100, Math.round((cycleUSD / limitUSD) * 100)) : null,
        topSpender: top ? {email: top.email, usd: top.cents / 100} : null,
        members: (rows ?? []).length,
    };
}

// Sum chargedCents across Cursor usage events → dollars.
export function summarizeCursorToday(events) {
    let cents = 0;
    for (const e of events ?? [])
        cents += e.chargedCents ?? 0;
    return cents / 100;
}
