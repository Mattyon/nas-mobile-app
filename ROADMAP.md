# NAS App — Roadmap

## Done

### Session 1 (context window 1)
- [x] Drag-to-reorder downloads for priority management
- [x] AI chat screen (admin-only) — local Ollama, tool-calling (search/download/list/diskspace/library)
- [x] Speed test screen (admin-only) — Ookla via speedtest-cli
- [x] Czech title localization fix (HIMYM: uses P4983/TMDb path in Wikidata, not P4280/TVDb)
- [x] Czech audio download tier (4th option in quality picker, +1500 scoring bonus)
- [x] Search loading spinner (no false "no results" while waiting)
- [x] Speed display units fix: MB/s throughout (was Mbit/s, 10× wrong)
- [x] Priority reorder: ▲/▼ buttons with optimistic update + 5 s timer pause (replaces broken drag)
- [x] State labels: human-readable ("Stalled — no peers" etc.)

### Session 2
- [x] Post-download quality audit: Ollama checks resolution/source vs. requested tier; sends notification if poor
- [x] Daily new-episode CRON at 3 AM: checks Sonarr for recently-aired missing episodes, auto-downloads, notifies
- [x] In-app notification bell: bell icon with badge in AppBar, bottom-sheet list, clear-all, 60 s polling
- [x] ntfy integration: all notifications also pushed to ntfy topic for background push
- [x] Manual "Check new episodes" trigger in hamburger menu (all users)
- [x] Grab registry: records requested tier per item so quality check knows what was expected
- [x] FEATURES.md + ROADMAP.md documentation
- [x] Daily health check CRON at 4 AM: disk/DB comparison (missing files, small files, not-imported torrents, qBT errors)
- [x] Health Check screen in app (admin-only): color-coded issues/warnings, manual run button, last-run timestamp
- [x] Sk-CzTorrent (sktorrent.eu) integration: gateway auto-registers in Prowlarr on startup; +600 trust + +800 Czech audio bonus in ranking

### Session 3
- [x] **Item detail view**: full-screen detail on tap — TMDb backdrop SliverAppBar, genre chips, cast scroll, season accordion with quality dots, expandable overview, director, 2-step language→quality download picker
- [x] **Back button visibility fix**: black54 circular background on back icon so it's visible on white backdrops
- [x] **TV download stall detection**: `_check_series_grab_async` now distinguishes stalled from actively downloading; pushes ntfy alert for stalled series
- [x] **Stall recovery on gateway restart**: `_recover_stalled_grabs()` rescans recently-added series with all-stalled queues 5 min after startup
- [x] **TV notification debounce**: 45-second per-series timer batches episode import webhooks into one grouped notification (e.g. "S02E01–E06, 6 episodes")
- [x] **qBittorrent healthcheck hardening**: healthcheck now verifies `tun0` exists (catches namespace loss after gluetun restart) — autoheal triggers a container restart automatically
- [x] **Superadmin role** (`ai_access: true` in Authelia YAML): JWT carries the claim; only superadmins can grant the flag to others via user management
- [x] **AI chat history** — SQLite on NAS (`/app/data/ai_chats.db`): schema for named multi-conversation sessions with full message persistence
- [x] **`AiChatsListScreen`**: list all conversations, create/rename/delete; navigates into per-chat screen
- [x] **`AiChatScreen` rewrite**: takes `chatId`, loads full history from server on open, sends via `POST /ai/chats/{id}/message`
- [x] **New gateway AI endpoints**: `GET/POST /ai/chats`, `GET/PATCH/DELETE /ai/chats/{id}`, `POST /ai/chats/{id}/message` (full tool-loop + ntfy push on completion)
- [x] **AI menu gated on superadmin**: AI Chats only appears in the hamburger for users with `ai_access`
- [x] **User management AI toggle**: admins see users' `is_ai_access` state; only superadmins can change it
- [x] Library endpoint enriched: now returns `tmdbId`, `tvdbId`, `overview`, `type` so the detail view can open from library items

## Pending / Backlog

### Library fixes (Two and a Half Men)
- [ ] Sonarr Manual Import for S03 (51 GB downloaded but not imported)
- [ ] Fix S09E03 import (file exists in torrent folder, not in library)
- [ ] Re-grab S11E16 and S11E19 (SD HDTV quality, should be 1080p)
- [ ] Re-grab S12E03 (720p, rest of season is 1080p BluRay)
- [ ] Download missing S11 episodes (E01–E03, E05–E08, E10–E11, E13–E15, E18, E20–E21)

### Features to consider
- [ ] Per-episode re-grab from the detail / library screen
- [ ] Notification read/unread tracking per user (currently global clear)
- [ ] ntfy subscription QR code / setup guide in the app
- [ ] Subtitle language preference (Czech subtitles via Bazarr)
- [ ] Download history / completed log
- [ ] Disk usage breakdown by show / movie
- [ ] Scheduled maintenance window (pause downloads during sleep hours)
- [ ] Multiple quality profiles per user (e.g., guest always gets Fast)
- [ ] AI chat: rename on first message (auto-title from content)
