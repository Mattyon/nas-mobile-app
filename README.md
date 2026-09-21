# nas-app

Flutter mobile client (Android first; iOS later from the same codebase) for the NAS
**AI gateway**. Talks to the gateway over **Cloudflare Tunnel** (default) or **Tailscale** — both are supported.

## Features
- **Login** against the gateway (`/login`) → JWT; role-aware (admin / superadmin).
- **Biometric login** — fingerprint/face unlock on app open (with remember-me).
- **Search** movies/TV — resolves localized/**Czech** titles (e.g. *Hvězdný prach* → Stardust).
- **Item detail** — TMDb backdrop, cast, seasons with episode quality dots, download picker.
- **Download** at **Fast / Balanced / Best / Czech audio** quality (AI/heuristic picks the release; goes through Radarr/Sonarr so it's imported, renamed, and subtitled).
- **Downloads** tab — live progress / speed / ETA / state; drag to reorder; cancel with stop button.
- **Library** tab — grid view; admins can delete a title from disk.
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
| `bump [--by N]` | Increments the `+N` versionCode in `pubspec.yaml`. |
| `build` | `flutter build appbundle --release` |
| `upload` | Uploads the `.aab` and assigns it to a track. |
| `release` | All three, in order. |

Options: `--track internal\|alpha\|beta\|production` (default **internal**),
`--notes "…"`, `--rollout 0.1` for a staged rollout, `--dry-run`, `--yes`.

**Guards.** Production needs `--track production` *and* `--yes` — a release is
visible within minutes and can only be superseded, never withdrawn. A versionCode
already on Play is refused *before* the upload starts, because Play rejects
duplicates only after receiving all ~56 MB.

### One-time setup (manual — Google has no API for granting API access)

1. Play Console → **Setup → API access**, link a Google Cloud project.
2. That project → **IAM & Admin → Service Accounts → Create**. No Cloud roles needed.
3. On it: **Keys → Add key → JSON**. Download.
4. Play Console → **Users and permissions → Invite user**, paste the service account
   email, grant *Release to testing tracks* (and *Release to production* if wanted)
   for `mattyzem.nas`. Propagation takes a few minutes.
5. Store the JSON outside the repo and point the tool at it:
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
- `lib/detail.dart` — Item detail screen (TMDb backdrop, cast, seasons, download picker).
- `lib/api.dart` — gateway client (Dio) + token storage + biometric/remember-me auth.
- `lib/i18n.dart` — English/Czech strings, `tr()`, `LangAware` mixin, language toggle.
