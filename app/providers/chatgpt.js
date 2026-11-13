// @name ChatGPT
// @color #10A37F
// @home https://chatgpt.com/
// @host https://chatgpt.com/api/auth/session
// @login https://chatgpt.com/auth/login
// @domains chatgpt.com openai.com
// Shows the Codex usage limits (5-hour / weekly) of a ChatGPT subscription.
(async () => {
  const ko = (typeof LANG !== 'undefined' && LANG === 'ko');
  const isHtml = (t) => /<!doctype|<html/i.test(t || '');
  const s = await fetch('/api/auth/session', { credentials: 'include' });
  const st = await s.text();
  if (s.status === 403 && isHtml(st)) return JSON.stringify({ cf: true });
  if (s.status !== 200) return JSON.stringify({ err: 'HTTP ' + s.status });
  let sj;
  try { sj = JSON.parse(st); } catch (e) { return JSON.stringify(isHtml(st) ? { cf: true } : { login: true, why: 'session parse' }); }
  if (!sj || !sj.accessToken) return JSON.stringify({ login: true, why: 'no accessToken' });

  let acct = sj.account && sj.account.id;
  try {
    const p = JSON.parse(atob(sj.accessToken.split('.')[1].replace(/-/g, '+').replace(/_/g, '/')));
    acct = acct || ((p['https://api.openai.com/auth'] || {}).chatgpt_account_id);
  } catch (e) {}
  const h = { 'Authorization': 'Bearer ' + sj.accessToken, 'Accept': 'application/json' };
  if (acct) h['ChatGPT-Account-Id'] = acct;

  const r = await fetch('/backend-api/wham/usage', { credentials: 'include', headers: h });
  const rt = await r.text();
  if (r.status === 401) return JSON.stringify({ login: true, why: 'usage 401' });
  if (r.status === 403 && isHtml(rt)) return JSON.stringify({ cf: true });
  if (r.status !== 200) return JSON.stringify({ err: 'HTTP ' + r.status });
  const j = JSON.parse(rt);

  let plan = j.plan_type || (sj.account && sj.account.planType) || '';
  if (plan) plan = plan.charAt(0).toUpperCase() + plan.slice(1);
  const label = (sec) => {
    if (!sec) return ko ? '한도' : 'Limit';
    if (sec <= 86400) { const hr = Math.round(sec / 3600); return ko ? hr + '시간' : hr + '-hour'; }
    const d = Math.round(sec / 86400);
    if (d === 7) return ko ? '주간' : 'Weekly';
    return ko ? d + '일' : d + '-day';
  };
  const rows = [];
  const rl = j.rate_limit || {};
  for (const w of [rl.primary_window, rl.secondary_window]) {
    if (!w || typeof w.used_percent !== 'number') continue;
    let reset = 0;
    if (w.reset_at) reset = w.reset_at * 1000;
    else if (w.reset_after_seconds) reset = Date.now() + w.reset_after_seconds * 1000;
    rows.push({ label: label(w.limit_window_seconds), pct: w.used_percent, reset: reset });
  }
  return JSON.stringify({ ok: true, plan: plan, rows: rows });
})()
