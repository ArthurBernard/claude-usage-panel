// Cross-port parity: the normalization contract lives in three hand-written
// copies — lib/pure.js (GNOME), claude-code/statusline.js (terminal), and
// ClaudeUsageCore/Model.swift (macOS). Rather than physically share the code
// (which would break the status line's zero-dependency single-file install),
// every port is asserted against ONE shared fixture set: tests/fixtures/
// normalize.json. The Swift port asserts the same file in ClaudeUsageCoreTests.
// If any port drifts on the semantic core (kinds, order, percent, severity,
// reset, active), this test — and its Swift twin — go red.
import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

import {normalizeUsage as normalizePure} from '../claude-usage-panel@fschmutz.github.io/lib/pure.js';
import {normalizeUsage as normalizeStatusline} from '../claude-code/statusline.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const {cases} = JSON.parse(fs.readFileSync(path.join(here, 'fixtures', 'normalize.json'), 'utf8'));

// Project a port's card onto the presentation-agnostic core the fixture pins.
// `key` (pure.js: "kind:model") and `kind` (statusline: raw kind) both reduce
// to the raw kind here; labels are port-specific and deliberately not compared.
const core = (c) => ({
    kind: (c.key ?? c.kind).split(':')[0],
    percent: c.percent,
    severity: c.severity,
    resetsAt: c.resetsAt ?? null,
    active: c.active,
});

for (const {name, input, expected} of cases) {
    test(`pure.js normalize — ${name}`, () => {
        assert.deepEqual(normalizePure(input).map(core), expected);
    });
    test(`statusline.js normalize — ${name}`, () => {
        assert.deepEqual(normalizeStatusline(input).map(core), expected);
    });
}
