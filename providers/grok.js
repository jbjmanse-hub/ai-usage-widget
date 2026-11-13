// @name Grok
// @color #E7E9EA
// @home https://grok.com/
// @host https://grok.com/robots.txt
// @login https://grok.com/
// @domains grok.com x.ai
// Grok의 남은 질문 수를 표시합니다.
(async () => {
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
    if (sec < 86400) return Math.round(sec / 3600) + '시간';
    const d = Math.round(sec / 86400);
    return d === 7 ? '주간' : d + '일';
  };
  const row = (name, j) => {
    const total = Number(j.totalQueries || 0), left = Number(j.remainingQueries);
    if (isNaN(left)) return null;
    const w = win(j.windowSizeSeconds);
    const label = name + (w ? ' (' + w + ')' : '');
    const reset = j.waitTimeSeconds ? Date.now() + j.waitTimeSeconds * 1000 : 0;
    if (total > 0) return { label: label + '  ' + left + ' / ' + total + '회', pct: (total - left) / total * 100, reset: reset };
    return { label: label, value: '남음 ' + left + '회' };
  };

  const rows = [];
  let lastErr = null;
  // 기본 질문: 최신 모델 이름부터 시도
  for (const model of ['grok-4', 'grok-3']) {
    const a = await ask('DEFAULT', model);
    if (a.cf || a.login) return JSON.stringify(a);
    if (a.j) { const r = row('질문', a.j); if (r) { rows.push(r); break; } }
    else lastErr = a.err;
  }
  // 심층 검색 (지원하지 않으면 건너뜀)
  for (const kind of ['DEEPSEARCH', 'REASONING']) {
    const a = await ask(kind, 'grok-3');
    if (a.j) { const r = row(kind === 'DEEPSEARCH' ? 'DeepSearch' : '추론 모드', a.j); if (r) rows.push(r); }
  }
  if (rows.length === 0 && lastErr) return JSON.stringify({ err: 'HTTP ' + lastErr });
  return JSON.stringify({ ok: true, plan: '', rows: rows });
})()
