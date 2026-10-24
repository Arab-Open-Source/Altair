<div class="hero-split">
  <div class="hero-copy">
    <p class="hero-eyebrow"><span class="dot"></span>Crystal web framework</p>
    <h1>The batteries-included framework for <span class="accent">Crystal</span></h1>
    <p class="hero-lede">Routing, controllers, views, a real ORM, generators and a CLI — with sane defaults, so building a web app feels like the framework is working <em>for</em> you.</p>
    <ul class="hero-badges">
      <li class="badge"><b>992</b>&nbsp;specs passing</li>
      <li class="badge">SQLite + PostgreSQL</li>
      <li class="badge">Linux &middot; macOS &middot; Windows</li>
    </ul>
    <div class="button-row">
      <a class="btn btn-primary" href="/docs/install.html">Get started</a>
      <a class="btn btn-secondary" href="/docs/routing.html">Read the guides</a>
    </div>
    <p class="hero-meta">MIT licensed · <a href="https://github.com/Arab-Open-Source/Altair" rel="noopener">Star on GitHub</a></p>
  </div>
  <div class="terminal" role="region" aria-label="Quick start terminal">
    <div class="terminal-bar"><i></i><i></i><i></i><span>terminal — quick start</span></div>
    <div class="terminal-tabs" role="tablist" aria-label="Quick start steps">
      <button role="tab" aria-selected="true">Install</button>
      <button role="tab" aria-selected="false">Scaffold</button>
      <button role="tab" aria-selected="false">Run</button>
    </div>
    <div class="terminal-body" role="tabpanel">
<span class="line"><span class="prompt">$</span> <span class="cmd">curl -fsSL https://github.com/Arab-Open-Source/Altair/releases/latest/download/install.sh | sh</span></span>
<span class="line"><span class="comment"># verifies SHA-256, installs to ~/.local/bin</span></span>
<span class="line"><span class="prompt">$</span> <span class="cmd">altair --version</span></span>
<span class="line"><span class="out">Altair 0.3.x</span></span>
    </div>
    <div class="terminal-body" role="tabpanel" hidden>
<span class="line"><span class="prompt">$</span> <span class="cmd">altair new blog</span></span>
<span class="line"><span class="prompt">$</span> <span class="cmd">cd blog && shards install</span></span>
<span class="line"><span class="prompt">$</span> <span class="cmd">altair g scaffold Post title:string body:text</span></span>
<span class="line"><span class="comment"># model + migration + controller + views + routes</span></span>
    </div>
    <div class="terminal-body" role="tabpanel" hidden>
<span class="line"><span class="prompt">$</span> <span class="cmd">altair db:migrate && altair server</span></span>
<span class="line"><span class="out">Listening on http://localhost:3000</span></span>
<span class="line"><span class="comment"># open http://localhost:3000 — posts persist across restarts</span></span>
    </div>
  </div>
</div>

<div class="content-narrow">

## One framework, the whole stack

Everything a web app needs ships together and agrees on conventions — typed at compile time, so renames break the build instead of the page.

</div>

<div class="bento">
  <div class="bento-card featured span-4">
    <span class="bento-icon"><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><ellipse cx="12" cy="5" rx="9" ry="3"/><path d="M21 12c0 1.66-4 3-9 3s-9-1.34-9-3"/><path d="M3 5v14c0 1.66 4 3 9 3s9-1.34 9-3V5"/></svg></span>
    <h3><a href="/docs/record.html">Record — a real ORM</a></h3>
    <p>SQLite3 and PostgreSQL adapters, migrations with <code>db/schema.cr</code>, validations, callbacks, associations with batched eager loading, and a contract suite that runs against both backends.</p>
    <a class="card-link" href="/docs/record.html">Read the ORM guide</a>
  </div>
  <div class="bento-card span-2 accent-top">
    <span class="bento-icon"><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><circle cx="6" cy="6" r="3"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="12" r="3"/><path d="M8.5 8.5L13.5 9.5"/><path d="M8.5 15.5L13.5 14.5"/></svg></span>
    <h3><a href="/docs/routing.html">Segment-based routing</a></h3>
    <p>Typed <code>to: PagesController.index</code> references, resources, constraints, globs and redirects.</p>
  </div>
  <div class="bento-card span-2 accent-top">
    <span class="bento-icon"><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="2" y="2" width="20" height="8" rx="2"/><rect x="2" y="14" width="20" height="8" rx="2"/><line x1="6" y1="6" x2="6.01" y2="6"/><line x1="6" y1="18" x2="6.01" y2="18"/></svg></span>
    <h3><a href="/docs/controllers.html">Controllers</a></h3>
    <p>Per-request instances, typed params, filters, callbacks and content negotiation.</p>
  </div>
  <div class="bento-card span-2 accent-top">
    <span class="bento-icon"><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></svg></span>
    <h3><a href="/docs/views.html">Views</a></h3>
    <p>Compile-time ECR with auto-escaping, layouts, partials and a form builder.</p>
  </div>
  <div class="bento-card span-2 accent-top">
    <span class="bento-icon"><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="11" width="18" height="11" rx="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg></span>
    <h3><a href="/docs/sessions.html">Sessions and auth</a></h3>
    <p>Signed cookies, flash, CSRF and full registration via <code>altair g auth</code>.</p>
  </div>
  <div class="bento-card span-2 accent-top">
    <span class="bento-icon"><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/></svg></span>
    <h3><a href="/docs/security.html">Secure by default</a></h3>
    <p>Security headers, request ids, sliding-window rate limiting and opt-in CORS.</p>
  </div>
  <div class="bento-card span-2 accent-top">
    <span class="bento-icon"><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><polyline points="4 17 10 11 4 5"/><line x1="12" y1="19" x2="20" y2="19"/></svg></span>
    <h3><a href="/docs/cli.html">CLI + generators</a></h3>
    <p><code>new</code>, <code>g scaffold</code>, <code>server</code>, <code>routes</code> and database commands.</p>
  </div>
</div>

<div class="content-narrow">

<div class="section-head">
<p class="kicker">Performance</p>
<h2>Measured under real load</h2>
<p>A public k6 harness compares Altair with Express, Fiber and a Ruby full-stack MVC app on identical PostgreSQL-backed CRUD endpoints — 100 virtual users for 60 seconds at an identical connection budget.</p>
</div>

</div>

<div class="bench-strip">
  <div class="bench-card highlight">
    <div class="bench-head"><img class="bench-logo" src="/assets/img/logos/crystal.svg" alt="Crystal"><span class="bench-name">Altair</span></div>
    <p class="workload">Write &middot; POST /items</p>
    <p class="figure">17,245 <small>req/s</small></p>
    <p class="note">1.7x Express &middot; 6.7x the Ruby full-stack arm &middot; best write tail of all four (max 18.1 ms).</p>
  </div>
  <div class="bench-card highlight">
    <div class="bench-head"><img class="bench-logo" src="/assets/img/logos/crystal.svg" alt="Crystal"><span class="bench-name">Altair</span></div>
    <p class="workload">Read &middot; GET /items/:id</p>
    <p class="figure">15,539 <small>req/s</small></p>
    <p class="note">1.6x Express &middot; 4.4x the Ruby full-stack arm &middot; zero meaningful failures in every run.</p>
  </div>
  <div class="bench-card">
    <p class="workload">Methodology</p>
    <p class="figure">100 <small>VUs &middot; 60s</small></p>
    <p class="note"><a href="/docs/benchmarks.html">Full report</a> with latency tables, framework logos and the tail-latency investigation.</p>
  </div>
</div>

<div class="content-narrow">
  <div class="vs-wrap">
  <table class="vs-table">
    <thead>
      <tr><th>Framework</th><th>Write req/s</th><th>Write p99</th><th>Write max</th><th>Read req/s</th><th>Read p99</th></tr>
    </thead>
    <tbody>
      <tr class="vs-altair"><td><span class="vs-fw"><img src="/assets/img/logos/crystal.svg" alt="Crystal logo">Altair</span></td><td>17,245</td><td>8.6 ms</td><td><strong>18.1 ms</strong></td><td>15,539</td><td>14.6 ms</td></tr>
      <tr><td><span class="vs-fw"><img src="/assets/img/logos/go.svg" alt="Go logo">Fiber (Go)</span></td><td><strong>22,080</strong></td><td><strong>8.5 ms</strong></td><td>24.8 ms</td><td><strong>20,908</strong></td><td><strong>10.4 ms</strong></td></tr>
      <tr><td><span class="vs-fw"><img src="/assets/img/logos/nodejs.svg" alt="Node.js logo">Express</span></td><td>10,074</td><td>16.2 ms</td><td>53.6 ms</td><td>9,532</td><td>20.5 ms</td></tr>
      <tr><td><span class="vs-fw"><img src="/assets/img/logos/ruby.svg" alt="Ruby logo">Ruby full-stack</span></td><td>2,587</td><td>337.7 ms</td><td>1,060 ms</td><td>3,531</td><td>257.5 ms</td></tr>
    </tbody>
  </table>
  </div>
  <p class="vs-caption">100 virtual users, 60 seconds, one 20-connection / 6-worker budget for every framework. Altair holds second place on throughput with the best write tail of all four arms; the closest architectural peer — the Ruby full-stack arm — trails 6.7x on writes and 4.4x on reads.</p>
</div>

<div class="content-narrow">
<div class="section-head">
<p class="kicker">Start here</p>
<h2>Documentation</h2>
<p>Install once, scaffold in seconds, and learn the framework guide by guide.</p>
</div>

</div>

<div class="doc-cards">
  <a class="doc-card" href="/docs/install.html">
    <h3><svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>Install</h3>
    <p>One-command setup on Linux, macOS and Windows with checksum verification.</p>
  </a>
  <a class="doc-card" href="/docs/usage.html">
    <h3><svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><polygon points="5 3 19 12 5 21 5 3"/></svg>Usage</h3>
    <p>Create a project, generate a scaffold and run the server.</p>
  </a>
  <a class="doc-card" href="/docs/routing.html">
    <h3><svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><circle cx="6" cy="6" r="3"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="12" r="3"/></svg>Guides</h3>
    <p>Routing, controllers, views, the ORM, sessions, security and uploads.</p>
  </a>
  <a class="doc-card" href="/docs/cli.html">
    <h3><svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><polyline points="4 17 10 11 4 5"/><line x1="12" y1="19" x2="20" y2="19"/></svg>CLI reference</h3>
    <p>Every command and generator, with flags and examples.</p>
  </a>
</div>
