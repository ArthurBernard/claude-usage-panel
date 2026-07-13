// Cross-port parity: the OAuth-usage normalization contract lives in two
// hand-written copies — lib/pure.js (GNOME) and ClaudeUsageCore/Model.swift
// (macOS). Both are asserted against ONE shared fixture set: tests/fixtures/
// normalize.json (the Swift port asserts the same file in ClaudeUsageCoreTests).
// If either port drifts on the semantic core (kinds, order, percent, severity,
// reset, active), this test — and its Swift twin — go red.
//
// The Claude Code status line is intentionally NOT a party to this contract: it
// renders purely from Claude Code's stdin and never normalizes an OAuth payload,
// so it has no normalizeUsage to keep in sync.
import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

import {normalizeUsage as normalizePure} from '../claude-usage-panel@fschmutz.github.io/lib/pure.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const {cases} = JSON.parse(fs.readFileSync(path.join(here, 'fixtures', 'normalize.json'), 'utf8'));

// Project a port's card onto the presentation-agnostic core the fixture pins.
// `key` is pure.js's "kind:model"; labels are port-specific and not compared.
const core = (c) => ({
    kind: c.key.split(':')[0],
    percent: c.percent,
    severity: c.severity,
    resetsAt: c.resetsAt ?? null,
    active: c.active,
});

for (const {name, input, expected} of cases) {
    test(`pure.js normalize — ${name}`, () => {
        assert.deepEqual(normalizePure(input).map(core), expected);
    });
}
