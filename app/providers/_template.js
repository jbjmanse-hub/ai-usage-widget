// ─────────────────────────────────────────────────────────────
//  Template for adding a new AI service
//  1) Copy this file and rename it, e.g. mytool.js
//     (files whose name starts with _ are ignored)
//  2) Edit the @ settings and the script below for your service.
//  3) Right-click the widget → Show AI → Reload AI tools
// ─────────────────────────────────────────────────────────────
//
// @name My AI Tool
//      Name shown on the widget (required)
// @color #8AB4F8
//      Title color (optional)
// @host https://example.com/robots.txt
//      A light page on the same site, opened while fetching. The script below runs on this site. (required)
// @home https://example.com/
//      Home page, opened once at start to pass security checks (optional, default: root of @host)
// @login https://example.com/login
//      Page opened by the [Sign in] button (optional, default: @home)
// @domains example.com auth.example.com
//      Domains whose cookies are removed on sign-out (optional, default: base domain of @host)
//
// The script runs inside the signed-in site, so fetch() sends the sign-in cookies automatically.
// LANG is 'ko' or 'en' (the widget language) so you can localize labels.
// Return ONE of these as a JSON string:
//   success:            { ok: true, plan: 'Pro', rows: [ { label: 'Daily', pct: 42, reset: 1735660800000 } ] }
//                       pct   = percent used (0-100)
//                       reset = when the limit resets (millisecond timestamp, 0 if unknown)
//   value without %:    { ok: true, rows: [ { label: 'Research', value: '12 left' } ] }
//   sign-in required:   { login: true }
//   error:              { err: 'message to show' }
//   security check:     { cf: true }     (a Cloudflare check page came back)
//
// To find where a site serves its usage, open the browser DevTools (F12) → Network tab
// and open the site's usage page.
(async () => {
  const ko = (typeof LANG !== 'undefined' && LANG === 'ko');
  const r = await fetch('/api/usage', { credentials: 'include', headers: { 'Accept': 'application/json' } });
  if (r.status === 401 || r.status === 403) return JSON.stringify({ login: true });
  if (r.status !== 200) return JSON.stringify({ err: 'HTTP ' + r.status });
  const j = await r.json();

  // ↓ adapt to the response format
  const used = j.used, limit = j.limit;
  return JSON.stringify({
    ok: true,
    plan: j.plan || '',
    rows: [ { label: ko ? '이번 달' : 'This month', pct: limit ? used / limit * 100 : 0, reset: j.reset_at ? Date.parse(j.reset_at) : 0 } ]
  });
})()
