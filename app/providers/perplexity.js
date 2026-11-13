// @name Perplexity
// @color #20B8CD
// @home https://www.perplexity.ai/
// @host https://www.perplexity.ai/robots.txt
// @login https://www.perplexity.ai/
// Shows the remaining uses (Research, Labs, ...) of a Perplexity subscription.
(async () => {
  const ko = (typeof LANG !== 'undefined' && LANG === 'ko');
  const isHtml = (t) => /<!doctype|<html/i.test(t || '');
  const get = async (u) => {
    const r = await fetch(u, { credentials: 'include', headers: { 'Accept': 'application/json' } });
    return { s: r.status, t: await r.text() };
  };

  // sign-in check
  const s = await get('/api/auth/session');
  if (s.s === 403 && isHtml(s.t)) return JSON.stringify({ cf: true });
  let sess = null;
  try { sess = JSON.parse(s.t); } catch (e) { if (isHtml(s.t)) return JSON.stringify({ cf: true }); }
  if (!sess || !sess.user) return JSON.stringify({ login: true, why: 'no session user' });

  // remaining uses
  const r = await get('/rest/rate-limit/all');
  if (r.s === 403 && isHtml(r.t)) return JSON.stringify({ cf: true });
  if (r.s === 401 || r.s === 403) return JSON.stringify({ login: true, why: 'rate-limit ' + r.s });
  if (r.s !== 200) return JSON.stringify({ err: 'HTTP ' + r.s });
  const j = JSON.parse(r.t);

  const names = ko
    ? { pro: 'Pro 검색', pro_search: 'Pro 검색', research: 'Research (심층 연구)', agentic_research: 'Research (심층 연구)', labs: 'Labs', image: '이미지 생성' }
    : { pro: 'Pro search', pro_search: 'Pro search', research: 'Research', agentic_research: 'Research', labs: 'Labs', image: 'Image generation' };
  const leftText = (n) => ko ? '남음 ' + n + '회' : n + ' left';
  const rows = [];
  const seen = {};
  for (const k of Object.keys(j)) {
    const m = /^remaining_(.+)$/.exec(k);
    if (!m || typeof j[k] !== 'number') continue;
    const key = m[1];
    const label = names[key] || key.replace(/_/g, ' ');
    if (seen[label]) continue;
    seen[label] = true;
    const total = j['total_' + key] || j[key + '_limit'] || j['limit_' + key];
    if (typeof total === 'number' && total > 0) rows.push({ label: label, pct: (total - j[k]) / total * 100, reset: 0 });
    else rows.push({ label: label, value: leftText(j[k]) });
  }

  // plan name (ignored on failure)
  let plan = '';
  try {
    const u = await get('/rest/user/settings');
    const us = JSON.parse(u.t);
    plan = us.subscription_tier || us.subscription_status || '';
    if (plan === 'active') plan = 'Pro';
    if (plan) plan = String(plan).charAt(0).toUpperCase() + String(plan).slice(1);
  } catch (e) {}
  return JSON.stringify({ ok: true, plan: plan, rows: rows });
})()
