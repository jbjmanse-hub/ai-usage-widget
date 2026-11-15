# AI Usage Widget

**English** | [한국어](README.ko.md)

A small Windows desktop widget that shows the **remaining usage of your AI subscriptions** — ChatGPT, Claude, Cursor, Perplexity and Grok.
It refreshes every minute and shows when each limit resets.

- **One portable file, no installation.** Uses only what ships with Windows 10/11 (PowerShell and WebView2). About 0.5 MB.
- **No API keys.** Sign in to each service inside the widget, the same way you do in a browser.
- **Works with Smart App Control.** The bundled DLLs are the official, Microsoft-signed WebView2 files.
- **Korean and English.** Follows your Windows language, or pick one from the menu.

> ⚠️ This is not an official product of OpenAI, Anthropic or any other company.
> It reads usage from the internal endpoints the sites use for their own usage pages, so it may stop working without notice when a site changes.

---

## Supported services

| Service | What is shown |
|---|---|
| **ChatGPT** | Codex usage limits (5-hour / weekly), plan |
| **Claude** | 5-hour and weekly limits (all models / Opus / Sonnet), plan |
| **Cursor** | Included usage of the current billing cycle (e.g. $12.88 / $20), on-demand usage |
| **Perplexity** | Remaining uses of Research, Labs, etc. |
| **Grok** | Remaining queries, DeepSearch |

- Only **ChatGPT and Claude** are shown at first. Turn on the others from right-click → **Show AI**.
- For ChatGPT, the widget shows the **Codex usage limits**. OpenAI does not offer a way to read the regular chat message limit.
- **Gemini, GitHub Copilot and Microsoft Copilot** have no way to read usage with a web sign-in. They are listed **greyed out with the reason** and cannot be selected.

---

## Download

Get one of these from [Releases](https://github.com/jbjmanse-hub/ai-usage-widget/releases/latest):

| File | What it does |
|---|---|
| **`AIUsageWidget.cmd`** (recommended) | **Portable.** Double-click to run the widget. Nothing is installed and no shortcuts are created; keep the file wherever you like and run it again any time. |
| `AIUsageWidget-Setup.cmd` | **Installer.** Adds an **AI Usage Widget** icon to your desktop and Start menu, then you can delete the file. |

1. **Right-click the downloaded file → Properties → check "Unblock" → OK.**
   Windows marks downloaded files, and on PCs with Smart App Control a downloaded `.cmd` file is blocked until you do this. The file is not code-signed, which is why Windows is careful.
2. Double-click it. If **"Windows protected your PC"** appears, click **More info → Run anyway**.
3. The widget appears at the top right of the screen. Click **[Sign in]** for each service and sign in as usual.

Running the file again while the widget is hidden brings it back on screen.

> The portable file unpacks the program quietly to `%LOCALAPPDATA%\AIUsageWidget\app` the first time, because Windows can only load the WebView2 files from disk. Sign-ins are stored in the same folder, so they stay on the PC.

**Update:** run the newer file (unblock it first in the same way). Sign-ins and settings are kept.

**Remove:** right-click the widget → **Uninstall…**. The program files, any shortcuts and all saved sign-in data are removed. Then delete the `.cmd` file.

---

## Using the widget

| Action | Result |
|---|---|
| ⟳ button (top right) | Refresh now |
| Drag | Move the widget (position is remembered) |
| Right-click | Full menu |
| Click the tray icon | Hide / show the widget |
| Right-click the tray icon | Same menu as right-click |

**Right-click menu:** Refresh now · Sign in ▸ · Show AI ▸ · Always on top · Opacity ▸ · Language ▸ · Start with Windows · Create desktop shortcut · Hide/show widget · Sign out of all · Sign out ▸ · Help · Uninstall… · Exit

**Bar colors:** green (plenty left) → yellow (60%+ used) → red (85%+ used)

---

## Sign-in and privacy

- You type your password into the service's **real sign-in page**. The widget never stores or sends your password anywhere.
- Sign-in cookies are stored only on your PC in `%LOCALAPPDATA%\AIUsageWidget`, separate from Chrome or Edge.
- Sign-ins survive restarts, reboots and updates. The widget visits each site every 12 hours to keep the session alive. If a site still signs you out, a tray notification appears.
- **Sign out of all** removes everything at once; **Sign out ▸** removes a single service, including the Google, Microsoft or other account you used to sign in to it.

---

## How it works

1. The widget keeps one hidden browser (WebView2) per service, all sharing one local profile.
2. On start it opens each site's home page once to pass security checks such as Cloudflare.
3. It runs a small script inside the signed-in site. The script calls the same internal endpoint the site's own usage page uses.
4. The result is drawn as bars with reset times.

It tells a real sign-out apart from a blocked security check, and retries automatically in the second case.

---

## Adding an AI service (for developers)

Each service is **one `.js` file** in `app/providers/`. Settings go in comments at the top:

```js
// @name    My AI Tool                      ← name on the widget (required)
// @host    https://example.com/robots.txt  ← a light page on the same site, kept open while fetching (required)
// @home    https://example.com/            ← home page, opened to pass security checks (optional)
// @login   https://example.com/login       ← opened by the [Sign in] button (optional)
// @color   #8AB4F8                         ← title color (optional)
// @domains example.com auth.example.com    ← cookie domains removed on sign-out (optional)
```

The script runs inside the signed-in site (so `fetch()` sends the cookies). `LANG` is `'ko'` or `'en'`. Return one of these as a **JSON string**:

```js
{ ok: true, plan: 'Pro', rows: [ { label: '5-hour', pct: 37, reset: 1735660800000 } ] }  // pct = % used, reset = ms timestamp
{ ok: true, rows: [ { label: 'Research', value: '12 left' } ] }                         // a value without a bar
{ login: true }    // sign-in required
{ cf: true }       // a security check page came back (the widget opens the home page and retries)
{ err: 'message' } // error
```

- Put your own files in `%LOCALAPPDATA%\AIUsageWidget\providers`. They are kept across updates.
- Then right-click → **Show AI → Reload AI tools**.
- Files starting with `_` are ignored. See `app/providers/_template.js`.

> Provider files run code inside your signed-in sites. Only add files from sources you trust.

---

## Building from source

```powershell
powershell -ExecutionPolicy Bypass -File build.ps1
```

This packs `app/` into `dist/AIUsageWidget.cmd` (portable) and `dist/AIUsageWidget-Setup.cmd` (installer): a small cmd/PowerShell launcher followed by the base64-encoded app zip.
To run without installing, run `app/AIUsageWidget.ps1` with `powershell -STA -ExecutionPolicy Bypass -File app\AIUsageWidget.ps1`.

```
app/
  AIUsageWidget.ps1   the widget (PowerShell + WPF)
  app.ico             icon
  providers/          one script per AI service, unavailable.json (greyed-out services)
  docs/               guide and adding-ai-tools, in Korean (.ko) and English (.en)
  lib/                Microsoft WebView2 SDK files (signed by Microsoft)
installer/            header.cmd + portable.ps1 / installer.ps1 used by build.ps1
build.ps1             builds the two single-file releases
```

---

## Troubleshooting

| Problem | Fix |
|---|---|
| "Smart App Control blocked…" | Right-click the downloaded file → Properties → check **Unblock** → OK, then run it again |
| "Windows protected your PC" | Click **More info → Run anyway** |
| "Sign-in required" keeps showing | The site signed you out; sign in again |
| It signs in to the wrong account (e.g. personal instead of work) | In the sign-in window, click **Use another account**, or right-click → **Sign out ▸** the service, then sign in again |
| "Failed to load" or other errors | The site may have changed. Check `%LOCALAPPDATA%\AIUsageWidget\error.log` and open an issue |
| The widget disappeared | Click the tray icon |

---

## Requirements

- Windows 10 or 11 (x64 / ARM64)
- Microsoft Edge WebView2 Runtime (preinstalled on Windows 11)

## License

[MIT License](LICENSE). The files in `app/lib/` are part of the Microsoft Edge WebView2 SDK and are distributed under Microsoft's own license; they are not covered by the MIT License (see [app/lib/NOTICE.txt](app/lib/NOTICE.txt)).

See [CHANGELOG.md](CHANGELOG.md) for the version history.
