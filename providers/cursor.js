// @name Cursor
// @color #9B8AFB
// @home https://cursor.com/
// @host https://cursor.com/robots.txt
// @login https://cursor.com/dashboard
// Cursor 구독의 이번 결제 주기 포함 사용량을 표시합니다.
(async () => {
  const isHtml = (t) => /<!doctype|<html/i.test(t || '');
  const call = async (path, post) => {
    const opt = { credentials: 'include', headers: { 'Accept': 'application/json' } };
    if (post) { opt.method = 'POST'; opt.headers['Content-Type'] = 'application/json'; opt.body = '{}'; }
    const r = await fetch(path, opt);
    const t = await r.text();
    if (r.status === 403 && isHtml(t)) return { cf: true };
    if (r.status === 401 || r.status === 403) return { login: true };
    if (r.status !== 200) return { err: 'HTTP ' + r.status };
    try { return { j: JSON.parse(t) }; } catch (e) { return { login: true }; }
  };
  const money = (c) => '$' + (Number(c || 0) / 100).toFixed(2).replace(/\.00$/, '');
  const toTime = (v) => { if (!v) return 0; const n = Number(v); return isNaN(n) ? (Date.parse(v) || 0) : n; };
  const cap = (s) => s ? String(s).charAt(0).toUpperCase() + String(s).slice(1) : '';

  // 1) 사용량 요약
  const a = await call('/api/usage-summary', false);
  if (a.cf || a.login) return JSON.stringify(a);
  if (a.j && a.j.individualUsage && a.j.individualUsage.plan) {
    const j = a.j, p = j.individualUsage.plan, rows = [];
    const reset = toTime(j.billingCycleEnd);
    if (p.limit > 0 || typeof p.totalPercentUsed === 'number') {
      const pct = (p.limit > 0) ? p.used / p.limit * 100 : p.totalPercentUsed;
      rows.push({ label: '포함 사용량  ' + money(p.used) + ' / ' + money(p.limit), pct: pct, reset: reset });
    }
    const od = j.individualUsage.onDemand;
    if (od && od.enabled && od.limit > 0) {
      rows.push({ label: '추가 사용량  ' + money(od.used) + ' / ' + money(od.limit), pct: od.used / od.limit * 100, reset: reset });
    }
    return JSON.stringify({ ok: true, plan: cap(j.membershipType), rows: rows });
  }

  // 2) 대시보드용 사용량 (다른 형식)
  const b = await call('/api/dashboard/get-current-period-usage', true);
  if (b.cf || b.login) return JSON.stringify(b);
  if (b.err) return JSON.stringify(b);
  const u = b.j.planUsage || {};
  const rows = [];
  const pct = (typeof u.totalPercentUsed === 'number') ? u.totalPercentUsed : (u.limit > 0 ? u.totalSpend / u.limit * 100 : null);
  if (pct !== null) rows.push({ label: '포함 사용량  ' + money(u.totalSpend) + ' / ' + money(u.limit), pct: pct, reset: toTime(b.j.billingCycleEnd) });
  return JSON.stringify({ ok: true, plan: '', rows: rows });
})()
