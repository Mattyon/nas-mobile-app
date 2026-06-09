# NAS App — Feature Reference

Complete list of everything the app and gateway can do.

---

## App (Flutter / Android)

### Authentication
- Username + password login against Authelia `users_database.yml`
- JWT tokens with 12-hour TTL, auto-refresh on 401
- **Remember me** — stores credentials encrypted for 365 days (renewable on each use)
- **Biometric login** — fingerprint / face unlock on app open (if device supports it)
- Roles: `user` (read + download), `admin` (full access), **`superadmin`** (`ai_access: true` flag in YAML — only superadmins can grant this to others)
- SharedPreferences keys persisted on login: `username` (login username), `displayName` (display name from API, falls back to username), `isSuperadmin` (bool from `is_superadmin` login response); all cleared on logout

### Search
- Full-text search across movies and TV shows via Radarr/Sonarr lookup — returns both in a single unified list (no type toggle)
- Each result tile shows a colored type badge: teal pill for Movie, purple pill for TV
- Shows poster thumbnail, title, year, overview; tapping a tile opens the full Item Detail screen
- **Czech localization** — Czech title displayed when app language is set to Čeština
  - Sources: Radarr/Sonarr `alternateTitles` → TMDb API → Wikidata SPARQL (no key needed)
  - Covers both TVDb-mapped and TMDb-mapped TV shows (e.g. HIMYM via P4983)
  - Search re-runs automatically on language switch and passes `lang=cs` to the API
- Per-language on-disk indicators: EN and CS flag chips on each tile show which language versions are in the library; when both are present, a green "In library" label replaces the download button
- Download button shows a circular progress spinner and is disabled while the grab request is in-flight (prevents duplicate submissions)
- Loading spinner shown while waiting for results (no blank/false "no results")

### Download (Grab)
- **Two-step download flow**: (1) language picker (English or Czech audio — app language is pre-selected and listed first), then (2) quality tier picker
- **Czech audio fallback**: if the gateway returns `no_czech_audio: true`, an alert dialog offers to download in English at the same quality tier instead
- On-disk flags (`on_disk_en`, `on_disk_cs`) returned by the grab API are applied to the UI immediately — no reload needed
- **Grab progress dialog**: a non-dismissible modal shown while the grab is in-flight, cycling through four stage messages every 1.6 s — "Fetching torrents" → "Checking torrent databases" → "Picking the best release" → "Starting the download" — dismissed automatically on completion or error
- 4 quality tiers selectable per title:
  | Tier | Description |
  |------|-------------|
  | Fast | Quickest reliable download, any resolution |
  | Balanced | 1080p preferred, sane file size |
  | Best | Highest quality, BluRay/Remux preferred |
  | 🇨🇿 Czech audio | Balanced quality, prefers Czech-dubbed releases |
- Movies: heuristic ranking → Ollama re-ranking of top 8 candidates → Radarr grab
- TV shows (English): Sonarr `SeriesSearch` for all monitored episodes
- **TV shows (Czech)**: Prowlarr direct search for season/series packs on sktorrent.eu → Ollama picks best → added directly to qBittorrent; Sonarr `DownloadedEpisodesScan` triggered on completion
  - Czech TV packs are typically complete-series archives that Sonarr's episode-level search never finds; Prowlarr direct search is required
  - Ollama selects the best candidate (prefers complete packs, dual CZ+EN audio, higher seeders)
  - Background monitor polls qBittorrent until download finishes, then triggers Sonarr import and sends a push notification
  - Duplicate add protection: if a Czech pack for the same series is already downloading, reattaches the monitor instead of adding a duplicate
  - Timestamp-based torrent hash lookup: records timestamp before add, picks the torrent with `added_on ≥ timestamp` — unaffected by torrent internal name vs. Prowlarr title mismatches
- English and Czech flags are tracked independently per item; English flag is never cleared by a Czech grab attempt
- Grab registry: records requested tier per item for post-download quality checks

### Downloads Screen
- **Active** tab: downloading + queued torrents, sorted by qBittorrent priority
  - ▲/▼ buttons per tile for priority adjustment (optimistic update + 5s timer pause to prevent snap-back)
  - Red stop button on the left of each tile — confirmation dialog → removes torrent + all partial files, cleans up Radarr/Sonarr queue records (season packs handled via bulk delete of all queue items)
  - Human-readable state labels (e.g. "Stalled — no peers" instead of raw `stalledDL`)
  - Per-tile: name, progress bar, speed (MB/s), ETA, state
- **Finished** tab: seeding/completed/paused torrents
  - Actively seeding torrents (`uploading`, `forcedUP`, `stalledUP`) show upload speed (↑ MB/s) and share ratio instead of DL speed + ETA
  - API fields used: `upspeed_mbs`, `ratio` (added alongside existing `dlspeed_mbs`)
- Speed bar at bottom: global download + upload in MB/s (matches qBittorrent display; API response keys: `dl_mbs`, `up_mbs`)
- Pull-to-refresh on both tabs; auto-refresh every 1 second
- Search/filter within the downloads list

### Item Detail View
- Full-screen detail opened by tapping any search result or library item
- `SliverAppBar` with TMDb backdrop image + gradient overlay; back button with `black54` circle background (visible on any poster color)
- Poster, year, rating (TMDb), runtime, genre chips
- Country of origin flags, network, status (movie/series)
- Language chips + 2-step download picker (language → quality tier)
- Expandable/collapsible overview — threshold 220 characters (`Show more / Show less`)
- Genre chips capped at 6; director credit line (movies only)
- Cast horizontal scroll — circular actor photos with name label; capped at 15 members; falls back to initials avatar when no profile image is available
- TV: season accordion — tap a season to expand episodes with color-coded quality dots (green = 1080p+, amber = 720p, red = SD)
- Download flow raises a Czech audio fallback dialog if no Czech release is found, offering English download as an alternative

### Library
- List view of all fully imported movies and TV shows — shows poster thumbnail, title, year, size (GB), and on-disk status
- Tap → full detail view with all metadata (same as search)
- Admin-only delete from detail view (removes files from disk)
- Search within library

### Notifications Bell (AppBar)
- Bell icon with red badge showing unread count (capped at 9+; clears when panel is opened)
- Tapping the bell opens a bottom sheet and automatically marks all as read (`POST /notifications/read`)
- "Clear all" button dismisses all notifications
- Timestamps shown right-aligned in each row: "now" (<1 min), "5m" (<1 h), "2h" (<24 h), "3d" (<7 d), "8.6." (older)
- Receives: download complete, quality alerts, new episodes found, download failures
- **In-app system notifications** — two Android notification channels:
  - `downloads`: fires when a torrent completes (works in foreground + background)
  - `nas_alerts`: fires for gateway alerts (health, quality, new episodes) detected on each 60 s poll
  - Only genuinely new notifications trigger system alerts (baseline is set silently on first launch poll)
  - Up to 3 new notifications are surfaced per poll cycle
  - SharedPreferences key `last_notif_id` (int) persists the highest seen notification ID across launches to prevent duplicate alerts
- **Background notifications (WorkManager)** — periodic ~15-min task runs even when the app is fully killed:
  - Polls `/notifications` using raw HTTP (no Dio dependency in the isolate)
  - Re-authenticates automatically if the JWT is expired (uses stored remember-me credentials)
  - Fires system bar notifications for any new items found; reads `app_lang` from SharedPreferences to fire Czech or English text

### Admin Features (admins group only)
| Feature | Access |
|---------|--------|
| Media Sessions | View active streams from Plex + Jellyfin; each tile shows source badge (PLEX / JELLYFIN), last-seen relative timestamp (e.g. "3m ago"), and a red terminate button; sessions idle >300 s show grey icons/progress bar and an orange "stale" badge; auto-refreshes every 3 s; empty-state message when no sessions are active |
| Speed Limits | Set qBittorrent download/upload caps (Mbit/s) |
| Pause / Resume all | One-tap pause or resume all torrents |
| User Management | Create, edit, delete users; set admin role; superadmins also see an "AI access" toggle |
| Speed Test | Ookla speedtest (~30 s); shows download, upload, ping, ISP, server |
| Health Check | Shows disk/DB health report; manual re-run button; color-coded issues/warnings; stalled cards show an amber **"N items"** badge and the AI Fix button becomes **"AI Fix (N)"** when multiple episodes of the same show are grouped |
| Check New Episodes | Manual trigger for the daily new-episode scan (all users) |

### Superadmin Features (ai_access flag only)
| Feature | Description |
|---------|-------------|
| AI Chats | List of named conversations, each stored server-side in SQLite |
| New chat | Create a named conversation |
| Chat rename / delete | Long-press (or ⋮ menu) any chat to rename or delete |
| Chat history | All messages loaded from the NAS on open — consistent across devices |
| Send message | Full Ollama tool-calling loop; push notification sent on LLM reply |
| Grant AI access | Only a superadmin can toggle AI access for another user |

### Help / Connect Screen
Accessible via the **?** icon in the AppBar (visible from the main tabs). Step-by-step guides for connecting any device to Jellyfin.

**Home Network tab** — uses local IP:
- Smart TV (Samsung, LG): App Store → search "Jellyfin" → Add server → local address
- Phone / tablet (Android, iOS): install Jellyfin → Add server → local address
- Browser: open local address directly

**Anywhere tab** — uses Cloudflare Tunnel:
- Info note: "No VPN or special setup needed — works on any device, anywhere in the world."
- Same TV / phone / browser steps using the Cloudflare Tunnel Jellyfin URL (`https://jellyfin.mattyzem.com`)
- NAS mobile app server URL card: `https://nas.mattyzem.com`

Both tabs include a **Jellyfin app download card** with direct links to Google Play (Android) and the App Store (iOS).

### UI / UX
- Dark mode by default, toggle in hamburger menu
- Hamburger menu header: shows the logged-in user's display name (bold) and role ("admin" or "user") as a non-tappable item at the top of every menu
- **Kill app** option at the bottom of the hamburger menu (shown in red, separated by a divider) — calls `exit(0)` for a clean shutdown
- Czech / English language toggle in AppBar
- Theme preference persisted across sessions
- App language preference persisted to SharedPreferences (key: `app_lang`) and restored at startup; background WorkManager uses this key to fire Czech or English system notifications
- **Error + Retry**: Downloads and Library screens show an inline error message with a Retry button if the gateway fetch fails

---

## Gateway (Python / FastAPI)

### Endpoints
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/login` | — | Issue JWT; returns `is_admin`, `is_superadmin`, `displayname` |
| GET | `/search` | user | Search movies/TV; `lang=cs` for Czech titles |
| POST | `/grab` | user | Download a movie or TV series |
| GET | `/downloads` | user | Active qBittorrent torrents |
| GET | `/transfer` | user | Global dl/ul speed in MB/s; response keys: `dl_mbs`, `up_mbs` |
| GET | `/library` | user | Radarr/Sonarr library (includes `tmdbId`, `tvdbId`, `overview`, `type`) |
| DELETE | `/library` | admin | Delete item + files |
| GET | `/detail` | user | Full item metadata (Radarr/Sonarr + TMDb) |
| GET | `/diskspace` | user | Free/total disk space |
| GET | `/plex/sessions` | admin | Active Plex streams (legacy, kept for compatibility) |
| DELETE | `/plex/sessions/{key}` | admin | Kill a Plex session (legacy) |
| DELETE | `/downloads/{hash}` | user | Cancel torrent + remove partial files, clean Radarr/Sonarr queue |
| POST | `/grab/swap` | user | Blocklist a stalled torrent and grab the next-best alternative |
| POST | `/health/resolve` | admin | AI auto-fix a stalled or broken item (Ollama tool-calling loop) |
| POST | `/notifications/read` | user | Mark all notifications as read |
| GET | `/sessions` | admin | Active streams from Plex + Jellyfin; each item has `source: "plex"\|"jellyfin"` |
| DELETE | `/sessions/{source}/{key}` | admin | Kill a session on plex or jellyfin |
| GET | `/qbt/limits` | admin | Current speed limits |
| POST | `/qbt/limits` | admin | Set speed limits |
| POST | `/qbt/pause` | admin | Pause all torrents |
| POST | `/qbt/resume` | admin | Resume all torrents |
| POST | `/qbt/reorder` | user | Move torrent up/down in queue |
| POST | `/webhook/{source}` | — | Radarr/Sonarr import webhooks |
| POST | `/chat` | superadmin | Legacy single-turn Ollama LLM chat (stateless) |
| GET | `/ai/chats` | superadmin | List all conversations for the current user |
| POST | `/ai/chats` | superadmin | Create a new named conversation |
| GET | `/ai/chats/{id}` | superadmin | Get chat metadata + full message history |
| PATCH | `/ai/chats/{id}` | superadmin | Rename a conversation |
| DELETE | `/ai/chats/{id}` | superadmin | Delete a conversation and all its messages |
| POST | `/ai/chats/{id}/message` | superadmin | Send a message; runs Ollama tool-loop; pushes ntfy on completion |
| GET | `/speedtest` | admin | Ookla speedtest |
| GET | `/notifications` | user | Stored notifications (newest first) |
| POST | `/notifications/clear` | user | Clear all notifications |
| POST | `/cron/new-episodes` | user | Manual trigger for new-episode check |
| GET | `/health/report` | user | Last health check report |
| POST | `/health/check` | admin | Manual trigger for disk/DB health check |
| GET/PUT/POST/DELETE | `/users/...` | admin | User management; `is_ai_access` field settable by superadmin only |
| GET | `/health` | — | Gateway liveness check |

### Automation
- **Quality audit** (on every import webhook): Ollama evaluates whether the downloaded quality matches the tier the user requested. Sends a "⚠️ Quality alert" notification if the quality is poor (e.g., got HDTV 720p for a "best" grab).
- **Daily new-episode CRON** (3 AM Europe/Prague): Queries Sonarr for monitored episodes that aired in the last 7 days with no file. Triggers `SeriesSearch` for affected shows. Ollama generates a friendly notification summary. Sends "📺 New episodes downloading" notification.
- **Daily health check CRON** (4 AM Europe/Prague): Checks Sonarr/Radarr DB state against actual files on disk, detects missing files, suspiciously small files, not-imported downloads, and qBittorrent errors. Stores report in memory; admin-only `POST /health/check` endpoint for manual trigger. Report accessible via `GET /health/report`.
- **Webhook-driven notifications**: Radarr/Sonarr fire webhooks on grab/import/failure. Gateway stores them in-memory and pushes to ntfy.
- **TV notification debounce**: per-series 45-second timer batches multiple episode-import webhooks into one notification (e.g. "The Office (2005) — S02E01–E06 (6 episodes) ready to watch") instead of one push per episode.
- **Stall detection**: `_check_series_grab_async` distinguishes stalled (no progress) from actively downloading torrents. Sends a "⚠️ Stalled" ntfy push and records a notification if all queue items for a series are stalled.
- **Stall recovery on restart**: `_recover_stalled_grabs()` runs 5 minutes after gateway startup, re-scans series added in the last 35 minutes with all-stalled queues (handles the case where the daemon thread was killed by a container restart).
- **Czech artifact cleanup**: on every gateway startup, `_cleanup_all_czech_artifacts()` scans Sonarr for any `__Czech Auto Grab__` custom formats and `__Czech Temp N__` quality profiles left over from interrupted grab attempts, reverts affected series to their original profile, and deletes them. Also runs at the start of each Czech grab to prevent conflicts.
- **Bilingual notifications (EN + CS)**: every `_store_notification` call asks Ollama to translate the title and body to Czech. The in-memory notification stores both `title`/`body` (English) and `title_cs`/`body_cs` (Czech). The ntfy push includes both languages in the body (`English body\nCzech body`). The in-app bell shows the language that matches the current app language setting. Falls back silently to English-only when Ollama is unavailable.

### Persistence
- **AI chat history** stored in SQLite (`/app/data/ai_chats.db`, mounted from `./ai-gateway/data` on the host). Schema: `chats` (id, username, title, has_unread, created_at, updated_at) + `messages` (id, chat_id, role, content, ts). Conversations survive gateway restarts and are accessible from any device.

### Ranking
- Heuristic score: resolution + source + HDR + seeders + size penalty + indexer trust
- Tier modifiers: fast (speed/size), balanced (1080p fit), best (highest quality)
- Czech audio bonus: +1500 for explicit Czech, +400 for multi-audio releases
- Ollama re-ranking for balanced/best tiers (top 8 candidates)

### Torrent Sources
| Indexer | Type | Focus |
|---------|------|-------|
| YTS | Public | Movies, well-seeded |
| The Pirate Bay | Public | General |
| EZTV | Public | TV shows |
| LimeTorrents | Public | General |
| 1337x | Public | General |
| **Sk-CzTorrent** (sktorrent.eu) | Semi-private | Czech/Slovak movies & TV |

Sk-CzTorrent credentials are stored in `.env` (gitignored). The gateway auto-registers the indexer in Prowlarr on startup — Sonarr and Radarr then search it automatically. Sk-CzTorrent releases receive:
- **+600** indexer trust bonus (curated semi-private tracker, accurate seeder counts)
- **+800** Czech audio bonus for any tier when `prefer_czech=True` (on top of language-tag bonuses)

### Czech Title Sources (in priority order)
1. Radarr/Sonarr `alternateTitles` (language.id=25 or languageCode="cs")
2. TMDb API `/3/movie/{id}?language=cs-CZ` (requires `TMDB_API_KEY`)
3. Wikidata SPARQL — 3 parallel queries:
   - P4280 (TheTVDB ID) for TV shows
   - P4983 (TMDb TV series ID) for TV shows not in P4280
   - P4947 (TMDb movie ID) for movies

---

## Setup: Cloudflare Tunnel (remote access)

Exposes the gateway and Jellyfin over HTTPS to the internet — no port forwarding, works behind any ISP/CGNAT, free.

**One-time setup:**
1. Create a free account at [cloudflare.com](https://cloudflare.com) and add your domain (or use a free `*.trycloudflare.com` subdomain for testing).
2. Go to **Zero Trust → Networks → Tunnels → Create a tunnel** → name it e.g. `nas`.
3. Copy the tunnel token shown on screen.
4. Paste it into `~/Desktop/nas/.env`:
   ```
   CLOUDFLARE_TUNNEL_TOKEN=<paste token here>
   ```
5. Start the tunnel: `docker compose up -d cloudflared`
6. Back in the Cloudflare dashboard, go to **Public Hostnames** and add two routes:
   | Subdomain | Domain | Service |
   |-----------|--------|---------|
   | `nas` | yourdomain.com | `http://ai-gateway:8000` |
   | `jellyfin` | yourdomain.com | `http://jellyfin:8096` |
7. Update the default server URL in the mobile app login screen to `https://nas.yourdomain.com`.

Once done:
- Mobile app works anywhere without Tailscale: `https://nas.yourdomain.com`
- Jellyfin works on TVs and any browser anywhere: `https://jellyfin.yourdomain.com`
- Both services keep their own authentication — nothing is publicly open.

---

## Setup: Jellyfin API Key

Jellyfin runs in Docker (no apt install needed — the Docker image handles all dependencies).

**First-time setup:**
1. Start the container: `docker compose up -d jellyfin`
2. Open `http://<NAS-IP>:8096` and complete the setup wizard (create admin account, add `/data/media` as a library)
3. Go to **Dashboard → API Keys** (or `http://<NAS-IP>:8096/web/#/apikeys`)
4. Click **+** to create a new key — name it e.g. `nas-gateway`
5. Copy the key and add it to `~/Desktop/nas/.env`:
   ```
   JELLYFIN_API_KEY=<paste key here>
   ```
6. Restart the gateway: `docker compose up -d ai-gateway`

Jellyfin sessions will now appear in the app's **Media sessions** screen alongside Plex sessions. If `JELLYFIN_API_KEY` is empty, Jellyfin sessions are silently skipped (Plex sessions still show normally).

---

## Known Gaps / TODOs

- **S03, S09E03 import**: Season 3 and S09E03 files are in the torrent folder but not imported by Sonarr. Need Sonarr Manual Import or a forced rescan.
- **S11 episodes**: Only 5/22 episodes of Season 11 are in the library; 17 are missing entirely. Re-grab needed.
- **S11E16 / S11E19**: SD quality (HDTV x264-LOL, ~178–226 MB). Should be replaced with 1080p.
- **S12E03**: 720p instead of 1080p like the rest of the season. Should be re-grabbed at best quality.
- **Sonarr auto-search**: Disabled by default in gateway (to avoid unwanted automatic downloads). New-episode CRON handles this at 3 AM.
- **ntfy push**: Users need the ntfy Android app subscribed to the `nas-alerts` topic to receive push notifications when the NAS app is in the background.
