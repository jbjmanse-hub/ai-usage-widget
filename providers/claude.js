// @name Claude
// @color #D97757
// @home https://claude.ai/
// @host https://claude.ai/api/organizations
// @login https://claude.ai/login
// Claude 구독의 5시간 / 주간 사용 한도를 표시합니다.
(async () => {
  const isHtml = (t) => /<!doctype|<html/i.test(t || '');
  const H = { 'Accept': 'application/json', 'anthropic-client-platform': 'web_claude_ai' };
  const get = async (u) => {
    const r = await fetch(u, { credentials: 'include', headers: H });
    return { s: r.status, t: await r.text() };
  };

  const o = await get('/api/organizations');
  if ((o.s === 403 || o.s === 503) && isHtml(o.t)) return JSON.stringify({ cf: true });
  if (o.s === 401 || o.s === 403) return JSON.stringify({ login: true, why: 'organizations ' + o.s });
  if (o.s !== 200) return JSON.stringify({ err: 'HTTP ' + o.s });
  let orgs;
  try { orgs = JSON.parse(o.t); } catch (e) { return JSON.stringify(isHtml(o.t) ? { cf: true } : { login: true, why: 'org parse' }); }
  if (!Array.isArray(orgs) || orgs.length === 0) return JSON.stringify({ login: true, why: 'no org' });

  const org = orgs.find(x => (x.capabilities || []).includes('chat')) || orgs[0];
  const caps = org.capabilities || [];
  const plan = caps.includes('claude_max') ? 'Max' : (caps.includes('claude_pro') ? 'Pro' : '');

  const u = await get('/api/organizations/' + org.uuid + '/usage');
  if ((u.s === 403 || u.s === 503) && isHtml(u.t)) return JSON.stringify({ cf: true });
  if (u.s === 401 || u.s === 403) return JSON.stringify({ login: true, why: 'usage ' + u.s });
  if (u.s !== 200) return JSON.stringify({ err: 'HTTP ' + u.s });
  const j = JSON.parse(u.t);

  const names = { five_hour: '5시간', seven_day: '주간 (전체)', seven_day_opus: '주간 (Opus)', seven_day_sonnet: '주간 (Sonnet)' };
  const rows = [];
  for (const k of Object.keys(names)) {
    const w = j[k];
    if (!w || typeof w.utilization !== 'number') continue;
    rows.push({ label: names[k], pct: w.utilization, reset: w.resets_at ? Date.parse(w.resets_at) : 0 });
  }
  return JSON.stringify({ ok: true, plan: plan, rows: rows });
})()
