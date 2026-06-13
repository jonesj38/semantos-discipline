---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/guides/LEGACY-INGEST-GMAIL-SETUP.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.745147+00:00
---

# Wiring Google OAuth for Gmail Ingest

> **Note (2026-05)**: The full end-to-end dogfood runbook is
> [`docs/operator-runbooks/dogfood-gmail.md`](../operator-runbooks/dogfood-gmail.md).
> This document covers the Google Cloud Console steps in detail; for the
> full operator flow, start there.

**Status**: Operator runbook.
**Audience**: Operator (you) wiring the legacy-ingest pipeline against a real
Gmail inbox for the first time.
**Time**: ~10 minutes (5 in Google Cloud Console, 5 at the REPL).
**Reference**: [`docs/design/WALLET-LEGACY-INGEST.md`](../design/WALLET-LEGACY-INGEST.md) §3 LI1 + LI2.

---

## What this gets you

After completing this guide:

- `semantos legacy connect gmail` opens a browser to Google's OAuth consent
- After you approve, Google redirects to your `/auth/callback` page on
  `http://localhost:3001` (the loopback flow Google permits for installed
  apps; served by the dogfood-stack widget — see
  [`docs/operator-runbooks/dogfood-gmail.md`](../operator-runbooks/dogfood-gmail.md))
- The callback page displays a `legacy resume <state> <code>` command
- Pasting that command into your REPL completes the grant; tokens encrypted
  at rest under your wallet KEK
- `semantos legacy ingest gmail --since 2020-01-01` walks the inbox into the
  encrypted blob store; the AS4 right-panel attention feed starts populating
  from your real customer history

You only do the Google Cloud Console steps **once per Google account**. The
client credentials live encrypted in your local node and stay valid until
you choose to revoke them.

---

## Part 1 — Google Cloud Console (one-time, ~5 minutes)

### 1.1 Create or select a Google Cloud project

Go to <https://console.cloud.google.com>.

If you don't have a project yet, click the project dropdown at the top of
the page → **New Project**. Name it something like `Semantos Legacy
Ingest`. Organisation/location can stay at default.

If you have an existing personal-Gmail project (`oddjobtodd-gmail-bot` or
similar) you can reuse it.

### 1.2 Enable the Gmail API

- Left rail → **APIs & Services** → **Library**
- Search for `Gmail API`
- Click it → click **Enable**

This is per-project; you only do it once.

### 1.3 Configure the OAuth consent screen

- Left rail → **APIs & Services** → **OAuth consent screen**
- User type: **External**
- App name: `Semantos Legacy Ingest` (or anything; the operator sees this on
  the Google consent page)
- User support email: your Gmail address
- Developer contact email: same
- Click **Save and Continue**

#### Scopes
- Click **Add or Remove Scopes**
- Find `https://www.googleapis.com/auth/gmail.readonly` and tick it
- Save

(The narrower `gmail.metadata` scope is also fine if you want stricter
privacy and accept reduced extraction quality. Default is `gmail.readonly`.)

#### Test users
- Add your own Gmail address as a test user (the one whose mail you want to
  ingest)
- Save

You can leave the publishing status at **Testing** indefinitely if it's
just you using it. Google's "Testing" mode allows up to 100 test users
with no review required. You only need to publish if you're letting other
operators use the same OAuth client.

### 1.4 Create the OAuth 2.0 client

- Left rail → **APIs & Services** → **Credentials**
- Click **Create Credentials** → **OAuth client ID**
- Application type: **Web application**
- Name: `Semantos Legacy Ingest`

#### Authorized redirect URIs
Add this **exact** URL:
```
http://localhost:3001/auth/callback
```

This is the loopback flow Google permits for installed apps. The widget
in the dogfood stack (`scripts/dogfood-up.sh`) serves this route on
`:3001` by default; if you bring up the widget on a different port, use
that port here instead and pass `--widget-port` to dogfood-up to match.

Google strictly matches the redirect URI — including scheme (`http`, not
`https`), port, and path.

Click **Create**.

You'll see a modal with:
- **Client ID** (a long string ending in `.apps.googleusercontent.com`)
- **Client secret** (starts with `GOCSPX-`)

Copy both — you'll paste them in Part 2.

> **Security note.** The client secret is the credential the *server side*
> of the OAuth flow uses to prove it's your registered app. It's not as
> sensitive as a Google account password (the redirect URI binding limits
> what an attacker with the secret can do), but treat it like a token —
> don't paste it into chat, don't commit it to git, don't share it. The
> Semantos client config store encrypts it at rest under your wallet KEK.

---

## Part 2 — Register the credentials in your local node (~3 minutes)

Open your `semantos` REPL on the operator host (your laptop today; the
sovereign node once stage 1 ships).

### 2.1 Confirm Gmail is a registered provider

```
> legacy providers
{
  "providers": [
    { "id": "gmail", "displayName": "Gmail", "oauthScopes": ["https://www.googleapis.com/auth/gmail.readonly"] }
  ]
}
```

If Gmail isn't listed, the host hasn't loaded the legacy-ingest providers
yet. Follow the bootstrap notes in `docs/design/WALLET-LEGACY-INGEST.md` §3
LI1 deliverable 1 to register the provider.

### 2.2 Register your client credentials

```
> legacy register-client gmail \
    --client-id 0123456789-abcdefghij.apps.googleusercontent.com \
    --client-secret GOCSPX-your-actual-secret \
    --redirect-uri http://localhost:3001/auth/callback
{
  "ok": true,
  "providerId": "gmail",
  "redirectUri": "http://localhost:3001/auth/callback",
  "pkce": false,
  "hasClientSecret": true,
  "note": "Client credentials stored encrypted at rest under your wallet KEK."
}
```

The credentials are now persisted at `~/.semantos/legacy-clients/gmail.enc`,
encrypted under your wallet KEK. They survive REPL restarts and sovereign-
node reboots.

### 2.3 Verify the registration

```
> legacy clients
{
  "clients": [
    {
      "providerId": "gmail",
      "clientIdFingerprint": "01234567….com",
      "redirectUri": "http://localhost:3001/auth/callback",
      "pkce": false,
      "hasClientSecret": true,
      "registeredAt": "2026-04-28T13:00:00.000Z",
      "registeredBy": "hat-1"
    }
  ]
}
```

The `clientIdFingerprint` is the first 8 + last 4 chars of your client id
— enough to recognise which client is registered without surfacing a full
credential. The client secret is **never** included in this output.

---

## Part 3 — Run the OAuth grant (~2 minutes)

### 3.1 Start the connect flow

```
> legacy connect gmail
{
  "ok": true,
  "providerId": "gmail",
  "authorizeUrl": "https://accounts.google.com/o/oauth2/v2/auth?...",
  "stateNonce": "z9k7m3fjs2-...",
  "instructions": "Open this URL on your phone or laptop to grant access:\n  https://accounts.google.com/o/oauth2/v2/auth?..."
}
```

If your shell host wired `openBrowser`, the URL opens automatically.
Otherwise copy the URL into a browser.

### 3.2 Approve in Google's consent screen

Google prompts you to:
- Sign in (if you weren't already)
- Confirm the test-user warning ("Google hasn't verified this app") — click
  **Continue** since you're the developer
- Approve the `gmail.readonly` scope

### 3.3 Copy the resume command from the callback page

Google redirects to `http://localhost:3001/auth/callback?...`. The page
displays:

```
PASTE INTO YOUR SEMANTOS REPL
legacy resume z9k7m3fjs2-... 4/0AeaYSHB-...
[Copy]
```

Click **Copy** (or select the text manually).

### 3.4 Paste in your REPL

```
> legacy resume z9k7m3fjs2-... 4/0AeaYSHB-...
{
  "ok": true,
  "providerId": "gmail",
  "grantId": "a1b2c3d4...",
  "tokenExpiresAt": "2026-04-28T14:00:00.000Z",
  "hasRefreshToken": true,
  "scopes": "https://www.googleapis.com/auth/gmail.readonly"
}
```

Done. The grant is persisted encrypted at rest. Refresh tokens rotate
automatically before expiry; you won't need to repeat this dance.

---

## Part 4 — Run the first backfill

```
> legacy ingest gmail --since 2024-01-01
```

The worker walks `messages.list` + `messages.get?format=raw` against the
Gmail API, persisting each raw RFC822 envelope to
`~/.semantos/legacy-ingest/gmail/<message-id>.enc`. Resumable across
`kill -9` via the cursor checkpoint.

Watch progress:

```
> legacy status gmail
{
  "providers": {
    "gmail": {
      "grants": [
        {
          "grantId": "a1b2c3d4...",
          "ingest": {
            "cursor": "page-token-or-null",
            "since": null,
            "highWatermark": "2024-12-15T...",
            "pagesProcessed": 47,
            "itemsPersisted": 4291,
            "completed": false,
            "lastUpdatedAt": "2026-04-28T13:14:00.000Z"
          }
        }
      ],
      "rawItemsStored": 4291,
      "queue": {
        "pending": 0
      },
      "continuous": []
    }
  }
}
```

Once you've ingested some, run the extractor + ratification:

```
> legacy review --confidence ">=0.85"   # see what the extractor proposed
> legacy ratify gmail:<proposal-id>      # confirm one
> legacy bulk-ratify --provider gmail --confidence ">=0.85" --dry-run
```

That's the Paskian loop on real customer history.

---

## Troubleshooting

### "no client config for 'gmail'"
You haven't run `legacy register-client gmail` yet. See §2.2.

### "redirect_uri_mismatch" on Google's consent screen
The redirect URI you registered with Google doesn't match the one in your
client config. Compare:
- Google Cloud Console → Credentials → your OAuth client → Authorized
  redirect URIs
- `legacy clients` → `redirectUri` field

They must match **exactly**, including the trailing slash policy.

### "access_denied" on the callback page
You declined Google's consent prompt, or the OAuth consent screen still
has you as a non-test-user. Add yourself as a test user (§1.3) and retry.

### "state nonce expired" when you paste the resume command
State nonces TTL out after 10 minutes (LI1 spec). Re-run
`legacy connect gmail` to generate a fresh nonce + URL, then complete
the consent flow within 10 minutes.

### `legacy clients` shows my client but `connect` says "no client config"
The orchestrator's cache is out of sync with the persisted store. Run
`legacy register-client gmail ...` again with the same credentials —
it's idempotent and triggers a cache reload.

---

## Operating the credential lifecycle

### Rotating the client secret

Google Cloud Console → Credentials → your OAuth client → **Reset secret**.
Then re-run `legacy register-client gmail ...` with the new secret.
Existing grants keep working until their refresh tokens expire — refresh
uses the new secret on the next rotation.

### Removing the client config

```
> legacy unregister-client gmail
```

This removes the local credentials. Existing grants are **not** deleted;
they remain usable until the provider revokes them or their refresh
tokens expire. To also revoke the grants, follow with:

```
> legacy disconnect gmail
```

### What happens when you migrate to the sovereign node

When stage 2 (WSITE) ships, the OAuth callback can optionally move under
your wallet origin (e.g. `https://wallet.example/auth/callback`). The
loopback flow on `http://localhost:3001/auth/callback` remains the
default for installed-app deployments and stays supported. If you
choose to migrate:

1. Update the redirect URI in the Google Cloud Console
2. Re-run `legacy register-client gmail ...` with the updated redirect URI
3. Existing grants don't need reconnecting — only new grants land at the
   updated callback URL

See V1.0 plan §5.

---

## Cross-references

- [`docs/design/WALLET-LEGACY-INGEST.md`](../design/WALLET-LEGACY-INGEST.md) — full spec for LI1–LI6
- [`docs/design/V1.0-EXECUTION-PLAN.md`](../design/V1.0-EXECUTION-PLAN.md) §5 — stage 5 status
- `runtime/legacy-ingest/src/client-config-store.ts` — encrypted-at-rest store
- `runtime/legacy-ingest/src/oauth.ts` — OAuth orchestrator
- `runtime/legacy-ingest/src/verb.ts` — REPL verb implementation
- [todriguez/ojt PR #19](https://github.com/todriguez/ojt/pull/19) — `/auth/callback` Next.js page
- Google Cloud Console: <https://console.cloud.google.com>
- Gmail API reference: <https://developers.google.com/gmail/api/reference/rest>
