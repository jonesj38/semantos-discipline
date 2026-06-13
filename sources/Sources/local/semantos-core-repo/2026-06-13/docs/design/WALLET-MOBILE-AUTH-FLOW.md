---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/WALLET-MOBILE-AUTH-FLOW.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.737966+00:00
---

# Mobile Auth Flow

**Version**: 0.1 DRAFT
**Status**: Spec
**Authors**: Todd
**Related**: `docs/design/WALLET-TIER-CUSTODY.md` (v0.4), `docs/design/WALLET-SITE-AS-SOVEREIGN-NODE.md` (WSITE auth protocol), `docs/design/WALLET-HEADERS-TRUSTLESS-SPV.md`

---

## 0. Headline

> Mobile Safari and Android Chrome don't behave like desktop browsers. The popup-and-postMessage pattern that works on desktop breaks on mobile. The wallet's mobile-platform UX uses **full-page redirects with callback URLs** — the same pattern Sign-In-With-Apple, Sign-In-With-Ethereum, and every payment processor's hosted-checkout-page already use. Detect platform; pick the right transport; converge on the same wallet origin and the same v0.4 onboarding flow.

---

## 1. Why Mobile Is Different

Three concrete reasons the desktop popup pattern doesn't work on mobile:

1. **Popups become tabs.** iOS Safari and Android Chrome open `window.open(...)` as new tabs, not floating popup windows. The new tab loses its `window.opener` reference reliably across various OS / browser combinations. `postMessage` to `window.opener` returns `undefined`. The desktop "popup talks back to opener" pattern is dead on mobile.

2. **Tab switching is OS-mediated.** When the user taps "Sign in with Semantos," the wallet tab opens; the user signs in; tab-switching back to the original site is a manual gesture (swipe up, pick the original tab). Many users never make it back. Friction kills conversion.

3. **Third-party cookies and ITP.** Safari's Intelligent Tracking Prevention blocks cross-site cookies aggressively. Even if the wallet origin sets a cookie ("user is signed in"), the origin can't read that cookie in an iframe context on the dApp's site. iframe-based session detection patterns that work on desktop fail silently on iOS.

The wallet must use the **redirect-and-callback** pattern on mobile: full-page navigation away from the dApp to the wallet origin, complete the flow, full-page redirect back to a callback URL the dApp listens at. This is universally supported, has been the standard for OAuth / SAML / WebAuthn / Sign-In-With-Apple for years, and degrades gracefully across browsers.

---

## 2. Platform Detection

The dApp's frontend (or the wallet's connect-button SDK) detects the platform and picks the right transport:

```ts
function detectPlatform(): "desktop" | "mobile" | "embedded" {
  const ua = navigator.userAgent;
  
  // Embedded webviews (in-app browsers, e.g. Twitter, Instagram)
  // — most don't support popups OR third-party cookies. Treat as mobile.
  if (/FBAN|FBAV|Instagram|Twitter|Line/.test(ua)) return "embedded";
  
  // Mobile browsers (iOS Safari/Chrome, Android Chrome/Firefox)
  if (/iPhone|iPad|iPod|Android/.test(ua)) return "mobile";
  
  return "desktop";
}
```

| Platform | Auth transport | UX |
|---|---|---|
| Desktop | popup + postMessage | Floating popup window, opener-managed |
| Mobile | full-page redirect | New tab loaded with auth URL |
| Embedded webview | full-page redirect (only viable option) | Same tab navigation |

The wallet's connect-button SDK exposes one method — `connect(options)` — that picks the appropriate transport internally:

```ts
// dApp-side code
import { semantosConnect } from "@semantos/connect";

const result = await semantosConnect({
  challenge: "q7H9aK2pXr8mN3vL5jZ1cT4eW6yU0iS=",
  walletOriginHints: ["https://wallet.semantos.app"],
  returnTo: window.location.href,
  purpose: "identity_auth",
});

// On desktop: popup opens, returns when popup closes
// On mobile: full-page navigation to wallet, browser navigates back
//            with result on the URL params; SDK picks it up from URL on load
```

---

## 3. The Redirect Flow End-to-End

```
[1] Mobile user opens https://writes.example.com/articles/premium/x
     │
[2] Site responds 401 with X-Semantos-Challenge headers
     │
[3] Site's frontend JS:
     - Reads challenge from headers
     - Detects platform = mobile
     - Renders "Sign in with Semantos" button
     - User taps
     │
[4] Browser navigates (full-page) to:
     https://wallet.semantos.app/connect?
       version=1
       &dapp=writes.example.com
       &challenge=q7H9aK...
       &expectedIssuers=writes.example.com,*
       &returnTo=https%3A%2F%2Fwrites.example.com%2Fauth%2Fcallback
       &purpose=identity_auth
       &platform=mobile
     │
[5] wallet.semantos.app loads in mobile tab
     - WASM bundle initializes
     - IndexedDB checked for existing wallet
     │
[6a] If existing wallet:
      - Show "Sign in to writes.example.com? Approve?" (1 tap)
      - User taps Approve
      - Tier 0 signing (no factor required for identity proof)
      - Sign over the challenge nonce with identity key
[6b] If no existing wallet:
      - Show "Welcome — create wallet" v0.4 flow
      - 3 challenges + retype + soft warnings
      - Set Tier 1 PIN (skip if user wants identity-only)
      - Build dispatch envelope
      - Show backup options (Plexus / share / download / QR)
      - User picks one (or skips with explicit confirmation)
      - Identity created
      - Sign over the challenge nonce
     │
[7] Browser navigates back (full-page) to:
     https://writes.example.com/auth/callback?
       version=1
       &identityCert=<base64>
       &signature=<DER ECDSA hex>
       &nonce=q7H9aK...
       &returnTo=%2Farticles%2Fpremium%2Fx
     │
[8] Site's /auth/callback handler:
     - Verifies signature against the cert's pubkey + the challenge nonce
       (matched against the __semantos_challenge cookie set in step [2])
     - Verifies cert against trusted issuers
     - Issues a session JWT
     - Sets __semantos_session cookie
     - Returns 302 redirect to /articles/premium/x
     │
[9] Browser navigates to /articles/premium/x with session cookie
     - Site serves 200 OK with content
     - User reads the premium article
```

Total elapsed time: 60-90 seconds for a brand-new user (most spent in step [6b] doing the 3-challenge setup). 5-10 seconds for a returning user (step [6a] is just an approval tap).

**No popup. No `window.opener`. No cross-site cookies. No iframe.** Just two navigations — out to the wallet, back to the site — both visible and intuitive in the browser's tab + back-button model.

---

## 4. Platform-Specific Considerations

### 4.1 iOS Safari

- **ITP**: third-party cookies are blocked aggressively. Don't try to set cross-site cookies for cross-site auth. The session cookie set by the site in step [8] is *first-party* (the site's own origin), so it works.
- **Safari View Controller**: if the dApp is inside a native iOS app's web view, the auth flow may break depending on the WKWebView vs SFSafariViewController split. Document: "Embed via SFSafariViewController for proper auth-flow support; WKWebView with custom URL handling can also work."
- **WebAuthn**: iOS 16+ supports passkeys for identity factors. Tier 1+ biometric factors can use Face ID / Touch ID via WebAuthn API in step [6b].
- **Universal Links**: if a Semantos native iOS app exists in the future, the wallet origin URL in step [4] could deep-link directly into the app. Out of scope for v0.1 (web-only) but the redirect URL scheme should be designed to support universal links later.

### 4.2 Android Chrome

- **Custom Tabs**: dApp Android wrappers using Chrome Custom Tabs share cookies with the user's main Chrome session — auth state persists across dApp-tab boundaries. This is good; document it.
- **WebAuthn**: Android supports Pixel-bundled fingerprint / FIDO2 keys via WebAuthn since Android 9. Tier 1+ biometric factors work.
- **App Links**: parallel to iOS Universal Links — for future native-app deep linking.
- **WebView in app**: same caveat as iOS — apps embedding the wallet flow in a webview need to handle the URL navigation; document the supported configurations.

### 4.3 Embedded webviews (Twitter, Instagram, Facebook)

- **No popups, no third-party cookies, often no localStorage isolation issues with the parent app.** The redirect flow is the *only* viable pattern.
- **Some webviews intercept URL navigations** for analytics or to keep the user "in the app." The wallet origin URL must be configured on a domain the embedding app respects (`wallet.semantos.app` should not redirect to a different host mid-flow, or the webview may break the chain).
- **WebAuthn is unreliable in embedded webviews** — most don't support it. Tier 1 (PIN, fallback to wallet-side Argon2id) and Tier 2 (passphrase if biometric unavailable) should be the defaults in this context.

### 4.4 First-party cookie discipline

The session cookie the site sets in step [8] is **first-party** to the site's origin. The challenge cookie set in step [2] is also first-party. No cross-site cookies anywhere in the flow. This is essential for cross-browser reliability.

What about state across the wallet origin → site round-trip? It's carried in URL parameters (the `nonce`, `identityCert`, `signature`), not cookies. The challenge cookie on the site's side (`__semantos_challenge`) holds *what the site is expecting*; the URL parameters carry *what the wallet is asserting*. Server compares them in the callback handler. Stateless apart from the brief challenge-cookie lifetime.

---

## 5. The Wallet-Origin Picker

Different users want different wallet-origin trust postures. The site's "Sign in with Semantos" button can either:

**Option A — Direct redirect** (simplest, default for most sites):
- Site is configured to use a specific wallet origin (default `wallet.semantos.app`)
- Button click → redirect to that origin
- One option, fastest UX

**Option B — Origin picker** (advanced):
- Site shows a list of wallet origins:
  ```
  Sign in with Semantos:
    [ wallet.semantos.app ]      ← default, recommended
    [ wallet.gorillapool.io ]    ← community-operated alternative
    [ this site's wallet ]       ← if site offers wallet hosting (WSITE6)
    [ my own wallet origin ]     ← user types their VPS URL
  ```
- More clicks for the user, but full control over trust posture

**Recommendation**: default to Option A with a discreet "change wallet origin" link in the corner. Most users (95%+) just want the default; advanced users can change. The link's destination is a small "wallet origin picker" page hosted by the site (or a default page on `wallet.semantos.app`).

When a user picks a non-default wallet origin:
- The site's connect-button SDK persists the preference (first-party localStorage, scoped to the site)
- Subsequent sign-in attempts skip the picker, go straight to the user's chosen origin
- User can change again via "wallet settings" in their site profile

---

## 6. Implementation Deliverables

This isn't a phased work plan — it's a UX spec that informs the implementation of WSITE3 (the auth protocol on the server side) and the wallet origin's `/connect` endpoint (on the client side). The deliverables fall across existing phases:

### In WSITE3 (`WALLET-SITE-AS-SOVEREIGN-NODE.md`)

Add to the auth handler:
1. Platform-aware challenge headers — include `X-Semantos-Wallet-Origin-Hint` always; the site's frontend picks transport based on its own platform detection.
2. Redirect-friendly callback — the `/auth/callback` endpoint returns a 302 redirect to the original `Return-To` URL on success (not just `200 OK`). This makes the round-trip a clean pair of navigations on mobile.

### In the wallet bundle's `/connect` endpoint

1. Read `platform=mobile` URL param; if present, behavior shifts:
   - Don't try to use `window.opener.postMessage`
   - On completion, navigate via `window.location = returnTo` (full-page) instead of attempting popup-back communication
2. Same v0.4 create flow regardless of platform; just the result delivery differs.
3. Loading-state UX optimized for mobile: avoid unnecessary scroll, single-column layout, large touch targets.

### Connect-button SDK (`@semantos/connect`)

A small npm package (or zero-dep snippet) that dApp authors paste in to handle platform detection + transport selection:

```ts
// dApp's index.html
<script type="module">
  import { semantosConnect } from "https://wallet.semantos.app/connect.js";
  
  document.querySelector("#sign-in").addEventListener("click", async () => {
    const result = await semantosConnect({
      challenge: window.semantosChallenge,
      returnTo: "/protected/dashboard",
    });
    // On desktop: result is the cert + signature directly
    // On mobile: redirect already happened; this never runs
    //            (the page reloaded at the callback URL,
    //             which the SDK auto-detects via URL params)
  });
</script>
```

The SDK's job: pick popup-vs-redirect, package URL params, handle return-state on mobile (parse callback URL params on page load, deliver to dApp via callback or event), abstract the platform difference from the dApp author.

### Mobile-optimized v0.4 onboarding screens in the wallet

The challenge-and-confirm UX from earlier conversations needs mobile-specific layout:
- Numeric keypad input mode for any answer that's likely numeric
- Show normalized form ("Will be saved as: 'springfield'") prominently
- Soft-warn buttons sized for thumbs
- Backup options vertical-stacked (not horizontal)
- "Save to Plexus" / "Share" / "Download" / "QR" buttons as full-width cards with icons

---

## 7. Acceptance Criteria

The mobile auth flow is correctly implemented when:

1. **iOS Safari roundtrip works**: brand-new user on iPhone hits a 401-gated path, taps Sign In, completes wallet creation, returns to the gated path with session cookie set, accesses content. End-to-end <90s.
2. **Android Chrome roundtrip works**: same scenario on Android.
3. **Returning user roundtrip works**: same iPhone, second site visit, taps Sign In, single approval tap, returns. End-to-end <10s.
4. **Embedded webview roundtrip works**: open the gated URL inside Twitter's in-app browser; complete auth flow; returns successfully. (Some webviews may break — document which work.)
5. **No third-party cookies needed**: the entire flow uses first-party cookies and URL parameters only. Block third-party cookies in browser settings → flow still works.
6. **Wallet origin picker** visible and functional: default origin works without picker; "change wallet origin" link surfaces the picker; user-chosen origin persists per-site.
7. **Compatibility matrix documented**: which platforms work fully, which work with caveats, which don't work (with workarounds).
8. **WebAuthn integration tested**: Tier 1+ factors using passkey / Touch ID / Face ID / fingerprint where supported.
9. **The connect SDK is < 5KB gzipped** (minified, no dependencies beyond standard fetch).

---

## 8. Compatibility Matrix

To be filled in during testing — initial expected support:

| Platform | Identity auth | Payment (BRC-29) | Tier 1 PIN | Tier 2 biometric | Notes |
|---|---|---|---|---|---|
| iOS Safari 16+ | ✅ | ✅ | ✅ | ✅ (Face/Touch ID via WebAuthn) | First-class support |
| iOS Chrome 100+ | ✅ | ✅ | ✅ | ✅ | First-class support |
| Android Chrome 100+ | ✅ | ✅ | ✅ | ✅ (fingerprint via WebAuthn) | First-class support |
| Android Firefox 100+ | ✅ | ✅ | ✅ | ⚠ (WebAuthn support patchier) | Workable |
| Twitter in-app browser | ✅ | ✅ | ✅ | ❌ (no WebAuthn) | Use PIN factor |
| Instagram in-app browser | ✅ | ✅ | ✅ | ❌ | Use PIN factor |
| Facebook in-app browser | ⚠ (URL navigation sometimes intercepted) | ⚠ | ✅ | ❌ | Recommend "open in browser" |
| WeChat in-app browser | ⚠ | ⚠ | ✅ | ❌ | Region-specific behavior |

---

## 9. What This Spec Does Not Cover

- **Native mobile apps** — out of scope for v0.1. The browser flow is universal; native apps come later as a v1.x project.
- **Universal Links / App Links to deep-link into a Semantos native app** — design hooks are present (the URL scheme is forward-compatible) but no native app exists yet.
- **Push notifications** for wallet events — out of scope; future PWA work.
- **Offline support** — first-time wallet creation requires network (for the wallet origin to load); subsequent operations work offline (cached bundle, IndexedDB-backed state).
- **Account-recovery UX in mobile-specific contexts** — covered by the existing recovery flow in the wallet design doc; mobile should use the same flow with redirect-style transport.

---

## 10. Cross-references

- `docs/design/WALLET-TIER-CUSTODY.md` — v0.4 creation flow that runs at the wallet origin
- `docs/design/WALLET-SITE-AS-SOVEREIGN-NODE.md` — server-side auth handler specifies the wire format mobile flow uses
- `docs/design/WALLET-SHELL-VPS-SUBSTRATE.md` — BRAIN provides the substrate the wallet origin runs on
- WebAuthn Level 2 spec — for biometric factor integration
- Sign-In-With-Apple / Sign-In-With-Ethereum / OAuth 2.0 redirect patterns — established prior art for the mobile flow design
