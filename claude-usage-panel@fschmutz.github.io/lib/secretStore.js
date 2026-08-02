// System-keyring storage (libsecret / gnome-keyring) for the one secret the
// extension holds: the optional Cursor Admin API key. dconf is a cleartext,
// world-readable-to-the-user store - the same exposure class as the macOS
// UserDefaults CodeQL flagged - so the key lives in the login keyring instead,
// unlocked with the session, like the Claude Code token this extension reads.
//
// Everything here is fail-soft: on a system without a running Secret Service
// the calls resolve to null/false and the callers keep the legacy dconf path,
// so the panel never breaks over a missing keyring daemon.

import Secret from 'gi://Secret';

const SCHEMA = Secret.Schema.new(
    'io.github.fschmutz.claude-usage-panel',
    Secret.SchemaFlags.NONE,
    {name: Secret.SchemaAttributeType.STRING}
);

// The Secret.password_* functions are callback-async; wrap them once.
const call = (start, finish) => new Promise(resolve => {
    try {
        start((_src, res) => {
            try {
                resolve(finish(res));
            } catch (e) {
                console.warn(`claude-usage-panel: keyring unavailable: ${e.message}`);
                resolve(null);
            }
        });
    } catch (e) {
        console.warn(`claude-usage-panel: keyring unavailable: ${e.message}`);
        resolve(null);
    }
});

/** Store (or clear, when value is empty) a named secret. Resolves true on success. */
export function storeSecret(name, value) {
    if (!value) {
        return call(
            cb => Secret.password_clear(SCHEMA, {name}, null, cb),
            res => {
                Secret.password_clear_finish(res); // false just means nothing was stored
                return true;
            }
        ).then(r => r === true);
    }
    return call(
        cb => Secret.password_store(SCHEMA, {name}, Secret.COLLECTION_DEFAULT,
            `Claude Usage Panel: ${name}`, value, null, cb),
        res => Secret.password_store_finish(res)
    ).then(r => r === true);
}

/** Look a named secret up. Resolves to the string, or null (absent OR no keyring). */
export function lookupSecret(name) {
    return call(
        cb => Secret.password_lookup(SCHEMA, {name}, null, cb),
        res => Secret.password_lookup_finish(res)
    );
}
