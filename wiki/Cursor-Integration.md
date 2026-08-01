# Cursor Integration (optional)

Adds a **Cursor team-spend** section to the dropdown using the Cursor Admin API.

## Setup

1. Create an Admin API key at **cursor.com → your team → Settings → Admin API**.
2. Enable **Show Cursor usage** in [[Settings]] and paste the key.

## What it shows

- **This cycle** - total team spend for the billing cycle, and member count.
- **Today** - today's charged spend.
- **Top** - the top spender.
- **Gauge** - when the team has a monthly spend limit set, a colored `%` bar (spend ÷ limit);
  otherwise it shows spend text (Cursor is usage-based).

## Endpoints

`POST /teams/spend` and `POST /teams/filtered-usage-events` on `api.cursor.com`, HTTP Basic auth
with the key as the username. The key is stored locally (dconf / `UserDefaults`) and never leaves
your machine except to Cursor.
