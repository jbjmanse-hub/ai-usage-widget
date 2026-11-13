// @name Grok
// @color #E7E9EA
// @home https://grok.com/
// @host https://grok.com/robots.txt
// @login https://grok.com/
// @domains grok.com x.ai
// Shows the remaining Grok queries.
(async () => {
  const ko = (typeof LANG !== 'undefined' && LANG === 'ko');
  const L = ko
    ? { q: '질문', deep: 'DeepSearch', reason: '추론 모드', left: (n) => '남음 ' + n + '회', of: (a, b) => a + ' / ' + b + '회' }
    : { q: 'Queries', deep: 'DeepSearch', reason: 'Reasoning', left: (n) => n + ' left', of: (a, b) => a + ' / ' + b };
  const isHtml = (t) => /<!doctype|<html/i.test(t || '');
  const ask = async (kind, model) => {
    const r = await fetch('/rest/rate-limits', {
      method: 'POST', credentials: 'include',
      headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
      body: JSON.stringify({ requestKind: kind, modelName: model })
    });
    const t = await r.text();
    if (r.status === 403 && isHtml(t)) return { cf: true };
    if (r.status === 401 || r.status === 403) return { login: true };
    if (r.status !== 200) return { err: r.status };
    try { return { j: JSON.parse(t) }; } catch (e) { return { err: 'parse' }; }
  };
  const win = (sec) => {
    if (!sec) return '';
    if (sec < 86400) { const h = Math.round(sec / 3600); return ko ? h + '시간' : h + 'h'; }
    const d = Math.round(sec / 86400);
    if (d === 7) return ko ? '주간' : 'weekly';
    return ko ? d + '일' : d + 'd';
  };
  const row = (name, j) => {
    const total = Number(j.totalQueries || 0), left = Number(j.remainingQueries);
    if (isNaN(left)) return null;
    const w = win(j.windowSizeSeconds);
    const label = name + (w ? ' (' + w + ')' : '');
    const reset = j.waitTimeSeconds ? Date.now() + j.waitTimeSeconds * 1000 : 0;
    if (total > 0) return { label: label + '  ' + L.of(left, total), pct: (total - left) / total * 100, reset: reset };
    return { label: label, value: L.left(left) };
  };

  const rows = [];
  let lastErr = null;
  // regular queries: try the newest model name first
  for (const model of ['grok-4', 'grok-3']) {
    const a = await ask('DEFAULT', model);
    if (a.cf || a.login) return JSON.stringify(a);
    if (a.j) { const r = row(L.q, a.j); if (r) { rows.push(r); break; } }
    else lastErr = a.err;
  }
  // deep search / reasoning (skipped when not supported)
  for (const kind of ['DEEPSEARCH', 'REASONING']) {
    const a = await ask(kind, 'grok-3');
    if (a.j) { const r = row(kind === 'DEEPSEARCH' ? L.deep : L.reason, a.j); if (r) rows.push(r); }
  }
  if (rows.length === 0 && lastErr) return JSON.stringify({ err: 'HTTP ' + lastErr });
  return JSON.stringify({ ok: true, plan: '', rows: rows });
})()
