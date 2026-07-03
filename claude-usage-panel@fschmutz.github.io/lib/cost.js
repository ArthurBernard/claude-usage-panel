// Optional cost layer: the official usage API does not expose the dollar cost
// of token usage on subscription plans, so we shell out to `ccusage` (which
// computes it from the local ~/.claude/projects/*.jsonl logs).

import Gio from 'gi://Gio';

/**
 * Run `ccusage blocks --active --json` and resolve the active block cost.
 * Tries a globally installed `ccusage` first, then falls back to `npx`.
 * @returns {Promise<{costUSD: number, tokens: number} | null>}
 */
export function fetchActiveCost() {
    return new Promise(resolve => {
        const candidates = [
            ['ccusage', 'blocks', '--active', '--json'],
            ['npx', '-y', 'ccusage@latest', 'blocks', '--active', '--json'],
        ];

        const tryNext = index => {
            if (index >= candidates.length) {
                resolve(null);
                return;
            }
            let proc;
            try {
                proc = Gio.Subprocess.new(
                    candidates[index],
                    Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_SILENCE
                );
            } catch {
                tryNext(index + 1);
                return;
            }

            proc.communicate_utf8_async(null, null, (self, res) => {
                try {
                    const [, stdout] = self.communicate_utf8_finish(res);
                    if (!self.get_successful() || !stdout) {
                        tryNext(index + 1);
                        return;
                    }
                    const json = JSON.parse(stdout);
                    const block = json?.blocks?.[0];
                    if (!block) {
                        resolve(null);
                        return;
                    }
                    resolve({
                        costUSD: Number(block.costUSD) || 0,
                        tokens: Number(block.totalTokens) || 0,
                    });
                } catch {
                    tryNext(index + 1);
                }
            });
        };

        tryNext(0);
    });
}
