import Adw from 'gi://Adw';
import Gtk from 'gi://Gtk';
import {ExtensionPreferences, gettext as _} from 'resource:///org/gnome/Shell/Extensions/js/extensions/prefs.js';

import {storeSecret, lookupSecret} from './lib/secretStore.js';

export default class ClaudeUsagePanelPrefs extends ExtensionPreferences {
    fillPreferencesWindow(window) {
        const settings = this.getSettings();

        const page = new Adw.PreferencesPage({
            title: _('General'),
            icon_name: 'utilities-system-monitor-symbolic',
        });

        const behavior = new Adw.PreferencesGroup({
            title: _('Behavior'),
            description: _('How often to poll the Claude usage endpoint.'),
        });

        // Refresh interval (minutes, mapped to seconds in the setting).
        const intervalRow = new Adw.SpinRow({
            title: _('Refresh interval'),
            subtitle: _('Minutes between updates (min 1)'),
            adjustment: new Gtk.Adjustment({lower: 1, upper: 60, step_increment: 1}),
        });
        intervalRow.set_value(Math.max(1, Math.round(settings.get_int('refresh-interval') / 60)));
        intervalRow.connect('notify::value', row =>
            settings.set_int('refresh-interval', Math.round(row.get_value()) * 60));
        behavior.add(intervalRow);

        // Panel display mode.
        const modeRow = new Adw.ComboRow({
            title: _('Top bar shows'),
            subtitle: _('Which limit to display in the panel'),
            model: Gtk.StringList.new([_('Worst limit'), _('Current session')]),
        });
        modeRow.set_selected(settings.get_string('panel-mode') === 'session' ? 1 : 0);
        modeRow.connect('notify::selected', row =>
            settings.set_string('panel-mode', row.get_selected() === 1 ? 'session' : 'worst'));
        behavior.add(modeRow);

        const alertsRow = new Adw.SwitchRow({
            title: _('Limit-crossing alerts'),
            subtitle: _('Notify when a limit reaches 90% or 100%'),
        });
        settings.bind('alerts-enabled', alertsRow, 'active', 0);
        behavior.add(alertsRow);

        page.add(behavior);

        const cost = new Adw.PreferencesGroup({
            title: _('Cost'),
            description: _('The official API does not expose dollar cost on subscription plans. Enable this to compute it locally with ccusage (requires Node/npx).'),
        });
        const costRow = new Adw.SwitchRow({
            title: _('Show session cost'),
            subtitle: _('Runs `ccusage blocks --active` on each refresh'),
        });
        settings.bind('show-cost', costRow, 'active', 0);
        cost.add(costRow);
        page.add(cost);

        const cursor = new Adw.PreferencesGroup({
            title: _('Cursor (optional)'),
            description: _('Show Cursor team spend using the Cursor Admin API. Create a key at cursor.com → team → Settings → Admin API. Stored in the system keyring.'),
        });
        const cursorRow = new Adw.SwitchRow({
            title: _('Show Cursor usage'),
            subtitle: _('Adds a Cursor spend section to the dropdown'),
        });
        settings.bind('cursor-enabled', cursorRow, 'active', 0);
        cursor.add(cursorRow);

        // The key lives in the system keyring (libsecret). The dconf slot is
        // only a legacy source (migrated by the extension) and a fallback for
        // systems without a Secret Service. `loaded` gates the changed handler
        // so prefilling the row can't echo the value back into a store cycle.
        const keyRow = new Adw.PasswordEntryRow({title: _('Cursor Admin API key')});
        let loaded = false;
        lookupSecret('cursor-admin-api-key').then(stored => {
            keyRow.text = stored ?? settings.get_string('cursor-api-key');
            loaded = true;
        });
        keyRow.connect('changed', row => {
            if (!loaded)
                return;
            storeSecret('cursor-admin-api-key', row.text).then(ok => {
                if (ok) {
                    // Scrub any legacy cleartext copy and nudge the running
                    // extension (the stamp carries no secret).
                    if (settings.get_string('cursor-api-key'))
                        settings.set_string('cursor-api-key', '');
                    settings.set_string('cursor-key-stamp', String(Date.now()));
                } else {
                    // No Secret Service on this system: keep the old dconf
                    // path so the feature still works.
                    settings.set_string('cursor-api-key', row.text);
                }
            });
        });
        cursor.add(keyRow);
        page.add(cursor);

        window.add(page);
    }
}
