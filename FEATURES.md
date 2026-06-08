# NAS App — Feature Reference

Complete list of everything the app and gateway can do.

---

## App (Flutter / Android)

### Authentication
- Username + password login against Authelia `users_database.yml`
- JWT tokens with 12-hour TTL, auto-refresh on 401
- **Remember me** — stores credentials encrypted for 365 days (renewable on each use)
- **Biometric login** — fingerprint / face unlock on app open (if device supports it)
- Roles: `user` (read + download) and `admin` (full access)

### Search
- Full-text search across movies and TV shows via Radarr/Sonarr lookup
- Shows poster, year, overview, on-disk badge
- **Czech localization** — Czech title displayed when app language is set to Čeština
  - Sources: Radarr/Sonarr `alternateTitles` → TMDb API → Wikidata SPARQL (no key needed)
  - Covers both TVDb-mapped and TMDb-mapped TV shows (e.g. HIMYM via P4983)
- Loading spinner shown while waiting for results (no blank/false "no results")

### Download (Grab)
- 4 quality tiers selectable per title:
  | Tier | Description |
  |------|-------------|
  | Fast | Quickest reliable download, any resolution |
  | Balanced | 1080p preferred, sane file size |
  | Best | Highest quality, BluRay/Remux preferred |
  | 🇨🇿 Czech audio | Balanced quality, prefers Czech-dubbed releases |
- Movies: heuristic ranking → Ollama re-ranking of top 8 candidates → Radarr grab
- TV shows: Sonarr `SeriesSearch` for all monitored episodes
- Grab registry: records requested tier per item for post-download quality checks

### Downloads Screen
- **Active** tab: downloading + queued torrents, sorted by qBittorrent priority
  - ▲/▼ buttons per tile for priority adjustment (optimistic update + 5s timer pause to prevent snap-back)
  - Human-readable state labels (e.g. "Stalled — no peers" instead of raw `stalledDL`)
  - Per-tile: name, progress bar, speed (MB/s), ETA, state
- **Finished** tab: seeding/completed torrents
- Speed bar at bottom: global download + upload in MB/s (matches qBittorrent display)
- Pull-to-refresh on both tabs; auto-refresh every 1 second
- Search/filter within the downloads list

### Library
- Grid view of all fully imported movies and TV shows
- Tap → show details + delete option (admin only, deletes files from disk)
- Search within library

### Notifications Bell (AppBar)
- Bell icon with red badge showing unread count
- Polls gateway every 60 seconds
- Tap to open bottom sheet with notification list
- "Clear all" button to dismiss
- Receives: download complete, quality alerts, new episodes found, download failures

### Admin Features (admins group only)
| Feature | Access |
|---------|--------|
| Plex Sessions | View active streams, kill a session |
| Speed Limits | Set qBittorrent download/upload caps (Mbit/s) |
| Pause / Resume all | One-tap pause or resume all torrents |
| User Management | Create, edit, delete users; set admin role |
| AI Assistant | Chat with local Ollama LLM; can search/download/check status |
| Speed Test | Ookla speedtest (~30 s); shows download, upload, ping, ISP, server |
| Health Check | Shows disk/DB health report; manual re-run button; color-coded issues/warnings |
| Check New Episodes | Manual trigger for the daily new-episode scan (all users) |

### UI / UX
- Dark mode by default, toggle in hamburger menu
- Czech / English language toggle in AppBar
- Theme preference persisted across sessions

---

## Gateway (Python / FastAPI)

### Endpoints
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/login` | — | Issue JWT |
| GET | `/search` | user | Search movies/TV; `lang=cs` for Czech titles |
| POST | `/grab` | user | Download a movie or TV series |
| GET | `/downloads` | user | Active qBittorrent torrents |
| GET | `/transfer` | user | Global dl/ul speed in MB/s |
| GET | `/library` | user | Radarr/Sonarr library |
| DELETE | `/library` | admin | Delete item + files |
| GET | `/diskspace` | user | Free/total disk space |
| GET | `/plex/sessions` | admin | Active Plex streams |
| DELETE | `/plex/sessions/{key}` | admin | Kill a Plex session |
| GET | `/qbt/limits` | admin | Current speed limits |
| POST | `/qbt/limits` | admin | Set speed limits |
| POST | `/qbt/pause` | admin | Pause all torrents |
| POST | `/qbt/resume` | admin | Resume all torrents |
| POST | `/qbt/reorder` | user | Move torrent up/down in queue |
| POST | `/webhook/{source}` | — | Radarr/Sonarr import webhooks |
| POST | `/chat` | user | Ollama LLM chat with NAS tool-calling |
| GET | `/speedtest` | admin | Ookla speedtest |
| GET | `/notifications` | user | Stored notifications (newest first) |
| POST | `/notifications/clear` | user | Clear all notifications |
| POST | `/cron/new-episodes` | user | Manual trigger for new-episode check |
| GET | `/health/report` | user | Last health check report |
| POST | `/health/check` | admin | Manual trigger for disk/DB health check |
| GET/PUT/POST/DELETE | `/users/...` | admin | User management |
| GET | `/health` | — | Gateway liveness check |

### Automation
- **Quality audit** (on every import webhook): Ollama evaluates whether the downloaded quality matches the tier the user requested. Sends a "⚠️ Quality alert" notification if the quality is poor (e.g., got HDTV 720p for a "best" grab).
- **Daily new-episode CRON** (3 AM Europe/Prague): Queries Sonarr for monitored episodes that aired in the last 7 days with no file. Triggers `SeriesSearch` for affected shows. Ollama generates a friendly notification summary. Sends "📺 New episodes downloading" notification.
- **Daily health check CRON** (4 AM Europe/Prague): Checks Sonarr/Radarr DB state against actual files on disk, detects missing files, suspiciously small files, not-imported downloads, and qBittorrent errors. Stores report in memory; admin-only `POST /health/check` endpoint for manual trigger. Report accessible via `GET /health/report`.
- **Webhook-driven notifications**: Radarr/Sonarr fire webhooks on grab/import/failure. Gateway stores them in-memory and pushes to ntfy.

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

## Known Gaps / TODOs

- **S03, S09E03 import**: Season 3 and S09E03 files are in the torrent folder but not imported by Sonarr. Need Sonarr Manual Import or a forced rescan.
- **S11 episodes**: Only 5/22 episodes of Season 11 are in the library; 17 are missing entirely. Re-grab needed.
- **S11E16 / S11E19**: SD quality (HDTV x264-LOL, ~178–226 MB). Should be replaced with 1080p.
- **S12E03**: 720p instead of 1080p like the rest of the season. Should be re-grabbed at best quality.
- **Sonarr auto-search**: Disabled by default in gateway (to avoid unwanted automatic downloads). New-episode CRON handles this at 3 AM.
- **ntfy push**: Users need the ntfy Android app subscribed to the `nas-alerts` topic to receive push notifications when the NAS app is in the background.
