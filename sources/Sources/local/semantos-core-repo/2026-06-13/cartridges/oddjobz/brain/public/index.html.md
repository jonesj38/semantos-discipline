---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/public/index.html
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.482787+00:00
---

# cartridges/oddjobz/brain/public/index.html

```html
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Oddjobz — Sunshine Coast Handyman</title>
  <meta name="description" content="Reliable handyman services across the Sunshine Coast. Get a rough quote in minutes — just describe the job.">
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="stylesheet" href="/chat-widget/chat-widget.css">
  <style>
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

    :root {
      --brand: #1d4ed8;
      --brand-light: #dbeafe;
      --text: #0f172a;
      --muted: #64748b;
      --bg: #f8fafc;
      --white: #ffffff;
      --border: #e2e8f0;
      --radius: 12px;
    }

    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto,
                   "Helvetica Neue", Arial, sans-serif;
      background: var(--bg);
      color: var(--text);
      line-height: 1.6;
    }

    /* ── Nav ── */
    nav {
      background: var(--white);
      border-bottom: 1px solid var(--border);
      padding: 0 24px;
      display: flex;
      align-items: center;
      justify-content: space-between;
      height: 56px;
      position: sticky;
      top: 0;
      z-index: 10;
    }
    .nav-logo {
      font-weight: 700;
      font-size: 20px;
      color: var(--brand);
      letter-spacing: -0.5px;
    }
    .nav-logo span { color: var(--text); }
    .nav-phone {
      font-size: 14px;
      color: var(--muted);
      text-decoration: none;
    }
    .nav-phone strong { color: var(--text); }

    /* ── Hero ── */
    .hero {
      max-width: 1100px;
      margin: 0 auto;
      padding: 64px 24px 48px;
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 48px;
      align-items: start;
    }
    @media (max-width: 720px) {
      .hero {
        grid-template-columns: 1fr;
        padding: 40px 16px 32px;
        gap: 32px;
      }
    }

    .hero-copy h1 {
      font-size: clamp(28px, 4vw, 44px);
      font-weight: 800;
      line-height: 1.15;
      letter-spacing: -1px;
      margin-bottom: 16px;
    }
    .hero-copy h1 em {
      font-style: normal;
      color: var(--brand);
    }
    .hero-copy p {
      font-size: 17px;
      color: var(--muted);
      margin-bottom: 28px;
      max-width: 420px;
    }

    .tag-list {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      margin-bottom: 32px;
    }
    .tag {
      background: var(--brand-light);
      color: var(--brand);
      font-size: 13px;
      font-weight: 600;
      padding: 4px 10px;
      border-radius: 20px;
    }

    .trust-row {
      display: flex;
      flex-direction: column;
      gap: 8px;
    }
    .trust-item {
      display: flex;
      align-items: center;
      gap: 8px;
      font-size: 14px;
      color: var(--muted);
    }
    .trust-item::before {
      content: "✓";
      color: #16a34a;
      font-weight: 700;
      font-size: 15px;
      flex-shrink: 0;
    }

    /* ── Chat widget slot ── */
    .hero-chat {
      display: flex;
      flex-direction: column;
      align-items: center;
    }
    .hero-chat-label {
      font-size: 13px;
      font-weight: 600;
      color: var(--muted);
      text-transform: uppercase;
      letter-spacing: 0.5px;
      margin-bottom: 10px;
      align-self: flex-start;
    }

    #oddjobz-chat-widget {
      --oddjobz-chat-width: 100%;
      --oddjobz-chat-height: 480px;
      width: 100%;
      max-width: 420px;
    }
    @media (max-width: 720px) {
      #oddjobz-chat-widget {
        --oddjobz-chat-height: 60vh;
      }
    }

    /* ── Services ── */
    .services {
      background: var(--white);
      border-top: 1px solid var(--border);
      border-bottom: 1px solid var(--border);
      padding: 56px 24px;
      margin-top: 24px;
    }
    .services-inner {
      max-width: 1100px;
      margin: 0 auto;
    }
    .services h2 {
      font-size: 26px;
      font-weight: 700;
      margin-bottom: 8px;
    }
    .services-sub {
      color: var(--muted);
      margin-bottom: 36px;
    }
    .services-grid {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(180px, 1fr));
      gap: 16px;
    }
    .service-card {
      border: 1px solid var(--border);
      border-radius: var(--radius);
      padding: 20px 16px;
      background: var(--bg);
    }
    .service-icon { font-size: 28px; margin-bottom: 8px; }
    .service-card h3 {
      font-size: 15px;
      font-weight: 600;
      margin-bottom: 4px;
    }
    .service-card p {
      font-size: 13px;
      color: var(--muted);
    }

    /* ── How it works ── */
    .how {
      max-width: 900px;
      margin: 0 auto;
      padding: 56px 24px;
    }
    .how h2 {
      font-size: 26px;
      font-weight: 700;
      margin-bottom: 8px;
    }
    .how-sub {
      color: var(--muted);
      margin-bottom: 36px;
    }
    .steps {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
      gap: 24px;
    }
    .step {
      display: flex;
      flex-direction: column;
      gap: 8px;
    }
    .step-num {
      width: 36px;
      height: 36px;
      border-radius: 50%;
      background: var(--brand);
      color: var(--white);
      font-weight: 700;
      font-size: 16px;
      display: flex;
      align-items: center;
      justify-content: center;
    }
    .step h3 { font-size: 15px; font-weight: 600; }
    .step p { font-size: 14px; color: var(--muted); }

    /* ── Footer ── */
    footer {
      text-align: center;
      padding: 32px 24px;
      font-size: 13px;
      color: var(--muted);
      border-top: 1px solid var(--border);
    }
  </style>
</head>
<body>

  <nav>
    <div class="nav-logo">Oddjobz<span>.</span></div>
    <a class="nav-phone" href="tel:+61412345678"><strong>Sunshine Coast Handyman</strong></a>
  </nav>

  <main>
    <section class="hero">
      <div class="hero-copy">
        <h1>Get a <em>rough quote</em> in minutes</h1>
        <p>Describe the job in the chat. We'll ask a couple of questions and give you a ballpark — no obligation, free on-site quote to follow.</p>

        <div class="tag-list">
          <span class="tag">Carpentry</span>
          <span class="tag">Plumbing</span>
          <span class="tag">Electrical</span>
          <span class="tag">Painting</span>
          <span class="tag">Fencing</span>
          <span class="tag">Tiling</span>
          <span class="tag">Doors &amp; Windows</span>
          <span class="tag">General handyman</span>
        </div>

        <div class="trust-row">
          <div class="trust-item">Sunshine Coast based — Noosa to Caloundra</div>
          <div class="trust-item">Free on-site quote for most jobs</div>
          <div class="trust-item">No call centre — you talk directly to the tradie</div>
          <div class="trust-item">Same-day response on urgent jobs</div>
        </div>
      </div>

      <div class="hero-chat">
        <div class="hero-chat-label">Chat to get a quote</div>
        <div id="oddjobz-chat-widget"
             data-endpoint="/api/chat"
             data-title="Get a rough quote"
             data-placeholder="Describe the job — e.g. 'dripping kitchen tap' or '3 fence panels need replacing'..."
             data-greeting="G'day! Tell me about the job and I'll give you a rough ballpark. What's going on?">
        </div>
      </div>
    </section>

    <section class="services">
      <div class="services-inner">
        <h2>What we take on</h2>
        <p class="services-sub">Most jobs around the house. If you're not sure, just describe it in the chat.</p>
        <div class="services-grid">
          <div class="service-card">
            <div class="service-icon">🔨</div>
            <h3>Carpentry</h3>
            <p>Decks, shelves, framing, cabinets, pergolas</p>
          </div>
          <div class="service-card">
            <div class="service-icon">🚿</div>
            <h3>Plumbing</h3>
            <p>Taps, drains, hot water, pipes, toilets</p>
          </div>
          <div class="service-card">
            <div class="service-icon">⚡</div>
            <h3>Electrical</h3>
            <p>Power points, switches, light fittings</p>
          </div>
          <div class="service-card">
            <div class="service-icon">🎨</div>
            <h3>Painting</h3>
            <p>Interior, exterior, feature walls, patching</p>
          </div>
          <div class="service-card">
            <div class="service-icon">🏚️</div>
            <h3>Fencing</h3>
            <p>Palings, panels, posts, gates</p>
          </div>
          <div class="service-card">
            <div class="service-icon">🪟</div>
            <h3>Doors &amp; Windows</h3>
            <p>Hanging, adjusting, locks, frames</p>
          </div>
          <div class="service-card">
            <div class="service-icon">🪴</div>
            <h3>Gardening</h3>
            <p>Mowing, hedging, mulch, retaining walls</p>
          </div>
          <div class="service-card">
            <div class="service-icon">🔧</div>
            <h3>General</h3>
            <p>Assembly, hanging, TV mounts, odd jobs</p>
          </div>
        </div>
      </div>
    </section>

    <section class="how">
      <h2>How it works</h2>
      <p class="how-sub">No forms. No waiting. Just describe the job.</p>
      <div class="steps">
        <div class="step">
          <div class="step-num">1</div>
          <h3>Describe the job</h3>
          <p>Tell the chat what needs doing — as much or as little detail as you have.</p>
        </div>
        <div class="step">
          <div class="step-num">2</div>
          <h3>Get a ballpark</h3>
          <p>We'll ask a couple of quick questions and give you a rough order of magnitude.</p>
        </div>
        <div class="step">
          <div class="step-num">3</div>
          <h3>Free on-site quote</h3>
          <p>Todd comes out, takes a proper look, and gives you a real number — no charge.</p>
        </div>
        <div class="step">
          <div class="step-num">4</div>
          <h3>Book it in</h3>
          <p>Happy with the quote? We'll lock in a time that works for you.</p>
        </div>
      </div>
    </section>
  </main>

  <footer>
    &copy; 2026 Oddjobz &mdash; Sunshine Coast Handyman &mdash; ABN 00 000 000 000
  </footer>

  <script src="/chat-widget/chat-widget.js" defer></script>
</body>
</html>

```
