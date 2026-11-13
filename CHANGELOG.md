# Changelog

## v1.1.0 — 2026-11-14

### Added
- **Single-file installer** `AIUsageWidget-Setup.cmd`. It installs to `%LOCALAPPDATA%\AIUsageWidget\app` and adds desktop and Start menu shortcuts with the app icon. Running a newer installer updates the app and keeps sign-ins.
- **Language option** (Auto / 한국어 / English). Menus, messages and the labels from each service follow the selected language.
- **Help** and **Uninstall…** menu items.
- English README; the Korean README moved to `README.ko.md`.
- Install note: on PCs with Smart App Control, unblock the downloaded setup file (Properties → Unblock) before running it.

### Changed
- File names are now in English (`docs/guide.*.txt`, `docs/adding-ai-tools.*.txt`, `providers/unavailable.json`).
- Widget files moved into the `app/` folder.
- Shortcuts are named **AI Usage Widget**.

## v1.0.0 — 2026-11-13

First public release.

- Shows subscription usage for **ChatGPT** (Codex limits), **Claude**, **Cursor**, **Perplexity** and **Grok**.
- Sign in inside the widget with an embedded browser (WebView2); no API keys.
- Sign-ins persist across restarts; the session is extended every 12 hours; a tray notification appears when a sign-in expires.
- Tells a real sign-out apart from a Cloudflare security check and retries automatically.
- Only ChatGPT and Claude are shown by default; other services are opt-in from **Show AI**.
- Gemini, GitHub Copilot and Microsoft Copilot are listed greyed out with the reason they are unavailable.
- Sign out of all services or one service at a time.
- Refresh button, "Loading…" indicator, always on top, opacity, start with Windows, tray icon.
- AI services are plain `.js` provider files, so new ones can be added without changing the widget.
- Runs on PCs with Smart App Control enabled (only Microsoft-signed DLLs are bundled).
