# nas-app

Flutter mobile client (Android first; iOS later from the same codebase) for the NAS
**AI gateway**. Talks to the gateway over **Tailscale** — no public exposure.

## Features
- **Login** against the gateway (`/login`) → JWT; role-aware (admin / superadmin).
- **Biometric login** — fingerprint/face unlock on app open (with remember-me).
- **Search** movies/TV — resolves localized/**Czech** titles (e.g. *Hvězdný prach* → Stardust).
- **Item detail** — TMDb backdrop, cast, seasons with episode quality dots, download picker.
- **Download** at **Fast / Balanced / Best / Czech audio** quality (AI/heuristic picks the release; goes through Radarr/Sonarr so it's imported, renamed, and subtitled).
- **Downloads** tab — live progress / speed / ETA / state; drag to reorder; cancel with stop button.
- **Library** tab — grid view; admins can delete a title from disk.
- **Admin features** — media sessions (Plex + Jellyfin), speed limits, user management, speedtest, health check, AI chat.
- **English + Čeština** UI with an in-app toggle.
- **Notifications** — bell badge with unread count; timestamps; system bar notifications while foregrounded, backgrounded, or killed (WorkManager 15-min poll).
- **Help / Connect screen** — step-by-step Jellyfin setup for TV, phone, and browser on both local network and remote (Cloudflare Tunnel / Tailscale).

## Configure
On the login screen set **Gateway URL** to the gateway over your tailnet, e.g.
`http://100.91.166.12:8000` (the NAS's Tailscale IP). The phone must have **Tailscale**
installed + connected.

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

## Project layout
- `lib/main.dart` — UI: auth gate, login, Search / Downloads / Library / Admin / Help screens.
- `lib/detail.dart` — Item detail screen (TMDb backdrop, cast, seasons, download picker).
- `lib/api.dart` — gateway client (Dio) + token storage + biometric/remember-me auth.
- `lib/i18n.dart` — English/Czech strings, `tr()`, `LangAware` mixin, language toggle.
