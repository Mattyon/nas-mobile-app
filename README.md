# nas-app

Flutter mobile client (Android first; iOS later from the same codebase) for the NAS
**AI gateway**. Talks to the gateway over **Tailscale** — no public exposure.

## Features
- **Login** against the gateway (`/login`) → JWT; role-aware (admin vs user).
- **Search** movies/TV — resolves localized/**Czech** titles (e.g. *Hvězdný prach* → Stardust).
- **Download** with one tap at **Fast / Balanced / Best** quality (AI/heuristic picks the release; grab goes through Radarr/Sonarr so it's imported, renamed, and subtitled).
- **Downloads** tab — live progress / speed / state.
- **Library** tab — searchable; **admins** can delete a title from disk.
- **English + Čeština** UI with an in-app toggle.
- Push "ready to watch" notifications via the self-hosted **ntfy** app (subscribe to
  `http://<tailnet-ip>:8090/nas-alerts`).

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
- `lib/main.dart` — UI: auth gate, login, Search / Downloads / Library screens.
- `lib/api.dart` — gateway client (dio) + token storage.
- `lib/i18n.dart` — English/Czech strings + `tr()` + language toggle.
