// Claude Usage Panel — GNOME Shell 45-50
// Shows Claude Code plan limits (session / weekly / per-model) in the top bar
// with a designed dropdown, plus optional session cost via ccusage.

import GObject from 'gi://GObject';
import St from 'gi://St';
import Clutter from 'gi://Clutter';
import GLib from 'gi://GLib';
import Gio from 'gi://Gio';
import Soup from 'gi://Soup';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import {Extension, gettext as _} from 'resource:///org/gnome/shell/extensions/extension.js';

import {fetchUsage} from './lib/claudeUsage.js';
import {fetchActiveCost} from './lib/cost.js';

const TRACK_WIDTH = 300; // px, must match .cu-track min-width in stylesheet.css

function severityClass(severity) {
    if (severity === 'critical')
        return 'cu-critical';
    if (severity === 'warning')
        return 'cu-warning';
    return 'cu-normal';
}

// "Resets in 3h 06m" / "Resets in 4d 2h"
function formatResets(iso) {
    if (!iso)
        return '';
    const target = Date.parse(iso);
    if (Number.isNaN(target))
        return '';
    let delta = Math.floor((target - Date.now()) / 1000);
    if (delta <= 0)
        return _('Resetting…');
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
    return _('Resets in %s').format(span);
}

// One limit row: label, percentage, colored progress bar, reset time.
const UsageCard = GObject.registerClass(
class UsageCard extends St.BoxLayout {
    _init() {
        super._init({vertical: true, style_class: 'cu-card', x_expand: true});

        const head = new St.BoxLayout({style_class: 'cu-card-head', x_expand: true});
        this._label = new St.Label({style_class: 'cu-card-label', x_expand: true});
        this._pct = new St.Label({style_class: 'cu-card-pct'});
        head.add_child(this._label);
        head.add_child(this._pct);

        // St.Bin centers its child by default; force START so the fill grows
        // from the left edge instead of sitting centered in the track.
        const track = new St.Bin({
            style_class: 'cu-track',
            x_align: Clutter.ActorAlign.START,
            y_align: Clutter.ActorAlign.CENTER,
            x_expand: false,
        });
        this._fill = new St.Widget({style_class: 'cu-fill'});
        track.set_child(this._fill);

        this._reset = new St.Label({style_class: 'cu-card-reset'});

        this.add_child(head);
        this.add_child(track);
        this.add_child(this._reset);
    }

    update(card) {
        const sev = severityClass(card.severity);
        this._label.text = card.label + (card.active ? '  ●' : '');
        this._pct.text = `${card.percent}%`;
        this._pct.style_class = `cu-card-pct ${sev}`;
        const px = Math.round((card.percent / 100) * TRACK_WIDTH);
        this._fill.style_class = `cu-fill ${sev}`;
        this._fill.style = `width: ${px}px;`;
        this._reset.text = formatResets(card.resetsAt);
    }
});

const ClaudeUsageButton = GObject.registerClass(
class ClaudeUsageButton extends PanelMenu.Button {
    _init(extension) {
        super._init(0.0, 'Claude Usage Panel');
        this._extension = extension;
        this._settings = extension.getSettings();
        this._httpSession = new Soup.Session({timeout: 20});
        this._httpSession.set_user_agent('claude-usage-panel/1.0');
        this._cards = new Map();
        this._timerId = 0;
        this._lastCost = null;
        this._refreshing = false;
        this._destroyed = false;

        // Panel button: brand glyph + compact worst-limit readout.
        const box = new St.BoxLayout({style_class: 'cu-panel'});
        this._panelIcon = new St.Label({text: '✳', style_class: 'cu-panel-icon'});
        this._panelLabel = new St.Label({
            text: '…',
            style_class: 'cu-panel-label',
            y_align: Clutter.ActorAlign.CENTER,
        });
        box.add_child(this._panelIcon);
        box.add_child(this._panelLabel);
        this.add_child(box);

        this._buildMenu();

        this._settings.connectObject(
            'changed::refresh-interval', () => this._restartTimer(),
            'changed::show-cost', () => this.refresh(),
            'changed::panel-mode', () => this._renderPanel(),
            this
        );

        this.refresh();
        this._restartTimer();
    }

    _buildMenu() {
        // Header
        const header = new PopupMenu.PopupBaseMenuItem({reactive: false, can_focus: false});
        const hbox = new St.BoxLayout({vertical: true, x_expand: true, style_class: 'cu-header'});
        const titleRow = new St.BoxLayout({x_expand: true});
        const title = new St.Label({text: 'Claude usage', style_class: 'cu-title', x_expand: true});
        this._planLabel = new St.Label({text: '', style_class: 'cu-plan'});
        titleRow.add_child(title);
        titleRow.add_child(this._planLabel);
        hbox.add_child(titleRow);
        header.add_child(hbox);
        this.menu.addMenuItem(header);

        // Cards container
        this._cardsItem = new PopupMenu.PopupBaseMenuItem({reactive: false, can_focus: false});
        this._cardsBox = new St.BoxLayout({vertical: true, x_expand: true, style_class: 'cu-cards'});
        this._cardsItem.add_child(this._cardsBox);
        this.menu.addMenuItem(this._cardsItem);

        // Status / cost line
        this._statusItem = new PopupMenu.PopupBaseMenuItem({reactive: false, can_focus: false});
        this._statusBox = new St.BoxLayout({vertical: true, x_expand: true, style_class: 'cu-status'});
        this._costLabel = new St.Label({text: '', style_class: 'cu-cost'});
        this._updatedLabel = new St.Label({text: '', style_class: 'cu-updated'});
        this._statusBox.add_child(this._costLabel);
        this._statusBox.add_child(this._updatedLabel);
        this._statusItem.add_child(this._statusBox);
        this.menu.addMenuItem(this._statusItem);

        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());

        const refreshItem = new PopupMenu.PopupImageMenuItem(_('Refresh now'), 'view-refresh-symbolic');
        refreshItem.connect('activate', () => this.refresh());
        this.menu.addMenuItem(refreshItem);

        const prefsItem = new PopupMenu.PopupImageMenuItem(_('Settings'), 'emblem-system-symbolic');
        prefsItem.connect('activate', () => this._extension.openPreferences());
        this.menu.addMenuItem(prefsItem);

        const quitItem = new PopupMenu.PopupImageMenuItem(_('Quit'), 'application-exit-symbolic');
        quitItem.connect('activate', () => this._quit());
        this.menu.addMenuItem(quitItem);
    }

    // Disable the extension: unloads it now and keeps it off across logins
    // until re-enabled (gnome-extensions enable … or ./install.sh).
    _quit() {
        this.menu.close();
        try {
            Gio.Subprocess.new(
                ['gnome-extensions', 'disable', this._extension.uuid],
                Gio.SubprocessFlags.NONE
            );
        } catch (e) {
            logError(e, 'claude-usage-panel: failed to disable');
        }
    }

    _restartTimer() {
        if (this._timerId) {
            GLib.Source.remove(this._timerId);
            this._timerId = 0;
        }
        const interval = Math.max(60, this._settings.get_int('refresh-interval'));
        this._timerId = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, interval, () => {
            this.refresh();
            return GLib.SOURCE_CONTINUE;
        });
    }

    async refresh() {
        // Skip if a refresh is already in flight (e.g. a slow ccusage call
        // straddling the next timer tick) — avoids piling up requests.
        if (this._refreshing)
            return;
        this._refreshing = true;
        try {
            const result = await fetchUsage(this._httpSession);
            if (this._destroyed)
                return;
            if (!result.ok) {
                this._renderError(result.message);
                return;
            }
            this._latest = result.cards;
            this._renderCards(result.cards);
            this._renderPanel();
            this._updatedLabel.text = _('Updated %s').format(this._nowString());

            // Plan label from the raw spend/extra hints, best-effort.
            this._planLabel.text = result.raw?.plan_label ?? '';

            if (this._settings.get_boolean('show-cost')) {
                this._costLabel.visible = true;
                this._costLabel.text = _('Session cost: computing…');
                const cost = await fetchActiveCost();
                if (this._destroyed)
                    return;
                if (cost) {
                    this._lastCost = cost;
                    this._costLabel.text = _('Session cost: $%s · %s tokens')
                        .format(cost.costUSD.toFixed(2), this._compact(cost.tokens));
                } else {
                    this._costLabel.text = _('Session cost: unavailable (install ccusage)');
                }
            } else {
                this._costLabel.visible = false;
            }
        } finally {
            this._refreshing = false;
        }
    }

    _renderCards(cards) {
        const seen = new Set();
        for (const card of cards) {
            seen.add(card.key);
            let widget = this._cards.get(card.key);
            if (!widget) {
                widget = new UsageCard();
                this._cards.set(card.key, widget);
                this._cardsBox.add_child(widget);
            }
            widget.update(card);
        }
        // Drop cards that disappeared.
        for (const [key, widget] of this._cards) {
            if (!seen.has(key)) {
                widget.destroy();
                this._cards.delete(key);
            }
        }
    }

    _renderPanel() {
        if (!this._latest || !this._latest.length) {
            this._panelLabel.text = '…';
            return;
        }
        const mode = this._settings.get_string('panel-mode'); // 'worst' | 'session'
        let card;
        if (mode === 'session')
            card = this._latest.find(c => c.key.startsWith('session')) ?? this._latest[0];
        else
            card = [...this._latest].sort((a, b) => b.percent - a.percent)[0];

        const shortLabel = card.label.split('·').pop().trim();
        this._panelLabel.text = `${shortLabel} ${card.percent}%`;
        const sev = severityClass(card.severity);
        this._panelLabel.style_class = `cu-panel-label ${sev}`;
        this._panelIcon.style_class = `cu-panel-icon ${sev}`;
    }

    _renderError(message) {
        this._panelLabel.text = _('Claude ?');
        this._panelLabel.style_class = 'cu-panel-label cu-warning';
        for (const [, widget] of this._cards)
            widget.destroy();
        this._cards.clear();
        this._updatedLabel.text = message;
    }

    _compact(n) {
        if (n >= 1_000_000)
            return `${(n / 1_000_000).toFixed(1)}M`;
        if (n >= 1_000)
            return `${Math.round(n / 1_000)}k`;
        return String(n);
    }

    _nowString() {
        const now = GLib.DateTime.new_now_local();
        return now.format('%H:%M');
    }

    destroy() {
        this._destroyed = true;
        if (this._timerId) {
            GLib.Source.remove(this._timerId);
            this._timerId = 0;
        }
        this._settings?.disconnectObject(this);
        this._httpSession?.abort();
        this._httpSession = null;
        super.destroy();
    }
});

export default class ClaudeUsagePanelExtension extends Extension {
    enable() {
        this._button = new ClaudeUsageButton(this);
        Main.panel.addToStatusArea(this.uuid, this._button, 0, 'right');
    }

    disable() {
        this._button?.destroy();
        this._button = null;
    }
}
