# nas-app

Flutter mobile client (Android first; iOS later from the same codebase) for the NAS
**AI gateway**. Talks to the gateway over **Cloudflare Tunnel** (default) or **Tailscale** — both are supported.

## Features
- **Login** against the gateway (`/login`) → JWT; role-aware (admin / superadmin).
  The gateway throttles repeated failures, and the app tells them apart: a 429
  shows how long to wait rather than the same "Login failed" as a wrong password.
- **Biometric login** — fingerprint/face unlock on app open (with remember-me).
- **Search** movies/TV — resolves localized/**Czech** titles (e.g. *Hvězdný prach* → Stardust).
- **Item detail** — TMDb backdrop, cast, download picker, and a **season list for every
  show**, not only ones in the library. Tap a season for its episodes (still, title, air
  date, runtime, rating, synopsis), tap an episode for the full detail. Library shows add
  downloaded/total per season and a quality dot per episode; Czech falls back to English
  per field where TMDb has no translation.
- **Artwork is cached to disk** (`cached_network_image`), so posters, backdrops and
  cast photos are fetched once rather than on every cold start.
- **Lists request a list-sized poster.** The gateway returns `poster_thumb` (~40 KB)
  next to the full-size `poster`; rows use the former, the detail screen's full-bleed
  hero the latter. Measured: the library list went from 4480 KB of cached images to
  376 KB, while opening a title still pulls the 1.2 MB original.
- **Download** at **Fast / Balanced / Best / Czech audio** quality (AI/heuristic picks the release; goes through Radarr/Sonarr so it's imported, renamed, and subtitled).
- **Downloads** tab — live progress / speed / ETA / state; drag to reorder; cancel with stop button.
- **Library** tab — grid view; admins can delete a title from disk. Filter to titles
  held in **Czech** or **English** (🇨🇿 / 🇬🇧 chips); the choice is remembered across
  app restarts, for people who only ever want to know what exists in one language.
- **Admin features** — media sessions (Plex + Jellyfin), speed limits, user management, speedtest, health check.
- **Superadmin features** — AI chat (multi-conversation, server-side history; requires `ai_access` flag).
- **English + Čeština** UI with an in-app toggle.
- **Notifications** — bell badge with unread count; timestamps; system bar notifications while foregrounded, backgrounded, or killed (WorkManager 15-min poll).
- **Help / Connect screen** — step-by-step Jellyfin setup for TV, phone, and browser on both local network and remote (Cloudflare Tunnel / Tailscale).

## Configure
On the login screen the **Gateway URL** is pre-set to `https://nas.mattyzem.com` (Cloudflare Tunnel — works on any network, no VPN needed). To use your own domain or a Tailscale IP instead, tap the URL field and change it.

## Build / run
Requires the Flutter SDK + Android toolchain (JDK 17 + Android SDK), or just Android Studio.

```bash
flutter pub get
flutter analyze            # static check
flutter test               # unit tests
flutter build apk --debug  # -> build/app/outputs/flutter-apk/app-debug.apk
# install on a connected phone:
flutter install            # or: adb install build/app/outputs/flutter-apk/app-debug.apk
```

For a smaller, optimized build use `flutter build apk --release` (needs a signing config
for Play, but a release APK can be sideloaded as-is).

## Web version (iPhone without the App Store)

The same code builds for the browser, and the NAS gateway serves it at
**`https://nas.mattyzem.com/app/`** (same origin as the API, so no CORS). On an iPhone:
open it in Safari → Share → **Add to Home Screen**; it then opens full-screen with its
own icon, like an app. No Apple developer account involved.

Build and publish **on the NAS** (the repo is cloned at `/mnt/cache/appdata/nas-mobile-app`):

```bash
scripts/build_web.sh            # analyze + all tests + build + publish
scripts/build_web.sh --no-test  # build + publish only
```

It runs Flutter 3.47.6 (SDK in `/mnt/cache/appdata/flutter-sdk`) in a throwaway
Ubuntu 24.04 container — Debian 12 made `flutter_tester` segfault mid-suite — builds
with `--base-href /app/`, and swaps the result into the gateway's `config/webapp` in one
move, so a failed build never leaves half an app online.

What differs on the web (`kIsWeb`):

- **No Android notifications, WorkManager or foreground service.** Instead the menu has
  **Notifications on this device** (Web Push: `web/push.js`, `web/push-sw.js`,
  `lib/web_push*.dart`; the gateway's `web_push.py` sends). On an iPhone it works only in
  the app added to the Home Screen, and the dialog says so. Flutter's own service worker
  is not registered (`web/flutter_bootstrap.js`): it would take the `/app/` scope over.
- **No Face ID / fingerprint, and the password is never stored** in the browser; only
  the login token is kept. When it expires, sign in again.
- **TMDb goes through the gateway** (`GET /tmdb/...`, key server-side). This is true on
  Android too now: a web bundle is public, so the app no longer ships the TMDb key at
  all (`test/tmdb_test.dart` guards that).

Cloudflare sets `Cache-Control: max-age=14400` on `.js` files regardless of what the
gateway sends (zone setting *Browser Cache TTL*), and phones kept running the previous
`main.dart.js` for hours, reloads included. So the build script names the entry points
by content: `index.html` (always fresh) loads `flutter_bootstrap.js?v=<hash>`, which
loads `main.<hash>.dart.js` — new code, new names, nothing stale to reuse.

## Releasing to Google Play

`scripts/play_publish.py` drives the Google Play Developer API directly. Chosen over
fastlane because that would pull a whole Ruby toolchain in for one task.

```bash
scripts/.venv/bin/python scripts/play_publish.py check     # credentials + what is live
scripts/.venv/bin/python scripts/play_publish.py release   # bump + build + upload
```

| Command | Does |
|---|---|
| `check` | Verifies credentials, prints the versionCode live on each track, and says whether the local one is free. Uploads nothing. |
| `bump [--by N]` | Moves the **version one release on and** the versionCode (`1.1.0+16` → `1.1.1+17`; `1.1.9` → `1.2.0`, see below). `--by` only skips versionCodes — the version always moves by exactly one release, however many codes were burnt. |
| `build` | `flutter build appbundle --release` |
| `upload` | Uploads the `.aab` and assigns it to a track. |
| `release` | All three, in order. |

Options: `--track internal\|alpha\|beta\|production` (default **internal**),
`--notes "…"`, `--rollout 0.1` for a staged rollout, `--dry-run`, `--yes`.

### Version numbers: patch 0–9, then the next minor

Every release moves the version by one, and the patch stays a single digit:
`1.1.1`, `1.1.2` … `1.1.9`, then `1.2.0`, `1.2.1` … `1.2.9`, then `1.3.0`. The minor
therefore counts groups of ten releases. `bump` (and so `release`) applies this
itself (`next_semver()` in `play_publish.py`); a patch already past 9 from before the
rule rolls over on its next release. The major is never moved by the tool — that is a
deliberate manual edit of `pubspec.yaml`. The versionCode after `+` is separate and
just climbs by one per upload. (Scheme set by the owner on 2026-10-04.)

### Why the patch version moves every release

The semver is what a person sees — in the Store listing, and in the "new version
available" push the gateway sends. Holding it at `1.1.0` across builds made that push
read "Version 1.1.0 is available" for `+15` and then identically again for `+16`,
which is indistinguishable from a duplicate notification for a version you already
have. So `bump` moves both numbers.

### Telling users a new version exists

Play notifies nobody when a build goes out, and the app has no update check, so after
a successful upload the publisher asks the NAS gateway to broadcast "a new version is
available" to every user — in Czech or English, whichever each person's app is set to.

The gateway holds the delay (default 300 s), not this script, so the laptop can be
closed right after a release. Play needs those few minutes before it actually serves
the new build; announcing at commit time points people at a version it will not give
them yet.

```bash
export NAS_GATEWAY_URL=http://nas:8000    # LAN/Tailscale — /internal/* is blocked at the edge
export WATCHDOG_TOKEN=…                   # same shared secret scripts/watchdog.sh uses
```

Without both, the release still succeeds and simply says no announcement was sent.
`--no-announce` skips it; `--announce-delay SECONDS` overrides the gateway's default.
It is sent once per versionCode, so re-running the publisher or promoting the same
build to another track will not notify anyone twice.

**Guards.** Production needs `--track production` *and* `--yes` — a release is
visible within minutes and can only be superseded, never withdrawn. A versionCode
already on Play is refused *before* the upload starts, because Play rejects
duplicates only after receiving all ~56 MB.

### One-time setup (manual — Google has no API for granting API access)

Play Console's old **Setup → API access** page no longer exists — Google removed it,
and the developer account is no longer linked to a Cloud project at all. Access now
comes only from inviting the service account as a Play Console user (step 3).

1. [console.cloud.google.com](https://console.cloud.google.com) → create a project.
   It stays empty; it exists only to own the service account.
2. In that project: enable
   [androidpublisher.googleapis.com](https://console.cloud.google.com/apis/library/androidpublisher.googleapis.com),
   then **IAM & Admin → Service Accounts → Create** (no Cloud roles needed) →
   **Keys → Add key → JSON**. Download.
3. Play Console → **Users and permissions → Invite new users**, paste the service
   account email, and under *App permissions* add `mattyzem.nas` with *Release to
   testing tracks* (and *Release to production* if wanted). Propagation takes a few
   minutes.
4. Store the JSON outside the repo and point the tool at it:
   ```bash
   chmod 600 ~/.config/play/nas-app.json
   export PLAY_SERVICE_ACCOUNT_JSON=~/.config/play/nas-app.json
   ```

`play_publish.py check` prints these steps itself if credentials are missing. The app
must already exist on Play with one manual upload — the API publishes releases but
cannot create a listing.

> iOS is **not** set up and cannot use this tool — see [ROADMAP.md](ROADMAP.md).

## Project layout
- `lib/main.dart` — UI: auth gate, login, Search / Downloads / Library / Admin / Help screens.
- `lib/detail.dart` — Item detail screen (TMDb backdrop, cast, season list, download picker).
- `lib/season.dart` — Season screen, episode sheet, and the TMDb + Sonarr season/episode merge.
- `lib/api.dart` — gateway client (Dio) + token storage + biometric/remember-me auth; TMDb via the gateway's `/tmdb` proxy.
- `lib/i18n.dart` — English/Czech strings, `tr()`, `LangAware` mixin, language toggle.
