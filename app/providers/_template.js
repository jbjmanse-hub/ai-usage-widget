// ─────────────────────────────────────────────────────────────
//  새 AI 도구 추가용 예시 파일
//  1) 이 파일을 복사해서 이름을 바꾸세요. 예: mytool.js
//     (이름이 _ 로 시작하는 파일은 무시됩니다)
//  2) 아래 @항목과 스크립트를 그 도구에 맞게 고치세요.
//  3) 위젯 우클릭 → [AI 도구 목록 다시 불러오기]
// ─────────────────────────────────────────────────────────────
//
// @name 내 AI 도구
//      위젯에 표시될 이름 (필수)
// @color #8AB4F8
//      제목 색상 (선택)
// @host https://example.com/api/me
//      사용량을 조회할 때 열어둘 주소. 이 사이트 안에서 아래 스크립트가 실행됩니다 (필수)
// @home https://example.com/
//      사이트 메인 페이지. 시작할 때 한 번 열어 보안 확인을 통과합니다 (선택, 기본값: host의 첫 페이지)
// @login https://example.com/login
//      [로그인] 버튼을 눌렀을 때 열 주소 (선택, 기본값: home)
//
// 스크립트는 로그인된 사이트 안에서 실행되므로 fetch()에 로그인 쿠키가 자동으로 붙습니다.
// 마지막에 아래 중 하나를 JSON 문자열로 돌려주면 됩니다.
//   성공:          { ok: true, plan: 'Pro', rows: [ { label: '하루', pct: 42, reset: 1735660800000 } ] }
//                  pct   = 사용한 비율(0~100)
//                  reset = 한도가 초기화되는 시각 (밀리초 타임스탬프, 모르면 0)
//   로그인 필요:   { login: true }
//   오류:          { err: '표시할 메시지' }
//   보안확인 필요: { cf: true }     (Cloudflare 확인 페이지가 돌아왔을 때)
//
// 사이트가 사용량을 어느 주소에서 주는지는 브라우저 F12 → Network 탭에서
// 사용량 화면을 열 때 오가는 요청을 보면 찾을 수 있습니다.
(async () => {
  const r = await fetch('/api/usage', { credentials: 'include', headers: { 'Accept': 'application/json' } });
  if (r.status === 401 || r.status === 403) return JSON.stringify({ login: true });
  if (r.status !== 200) return JSON.stringify({ err: 'HTTP ' + r.status });
  const j = await r.json();

  // ↓ 응답 모양에 맞게 고치세요
  const used = j.used, limit = j.limit;
  return JSON.stringify({
    ok: true,
    plan: j.plan || '',
    rows: [ { label: '이번 달', pct: limit ? used / limit * 100 : 0, reset: j.reset_at ? Date.parse(j.reset_at) : 0 } ]
  });
})()
