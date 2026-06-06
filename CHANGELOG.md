# Changelog

All notable changes to the Gecko Signage platform are documented in this file.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Image releases are tagged as `v<major>.<minor>.<patch>`.

## [Unreleased]

## [v0.2.1]

### Security

- (functions) Added `assertOrgMember` checks to all org-scoped media callables (`generateMediaUploadUrl`, `addMedia`, `listMedia`, `updateMedia`, `deleteMedia`, `replaceMedia`, `isFilenameUnique`), closing a cross-tenant gap where any signed-in user could read/write/delete another org's media by passing a different `orgId`
- (functions) `getUserByEmail` now requires authentication + a `superadmin` claim and returns only minimal identity fields; previously it had no auth check and returned the full user document to any caller

### Changed

- (dashboard) Tightened the typography scale to professional values to remove the "zoomed-in" feel: page titles 28→24px, prominent text 15→16px; added `--font-size-lh` (18px) subsection rung; global buttons repointed from `lg` to `md` (14px)
- (dashboard) Migrated ~566 hardcoded `px` font-sizes across 55 CSS modules to the `--font-size-*` design tokens, rounding each down to the nearest rung (marketing/landing styles untouched)
- (dashboard) Migrated remaining `rem`-based font-sizes (51 across 19 files) and inline TSX `fontSize` values (11 across 6 files) to the design tokens, rounding the rendered size down to the nearest rung
- (dashboard) Replaced `font-size: var(--spacing-*)` misuse (12 occurrences in 7 files, incl. `DashboardPageHeader.css`) with the equal `--font-size-*` token — no visual change, correct token semantics

### Fixed

- (agent) WiFi scan fallback no longer returns fabricated `TestNetwork1/2/3` entries when no networks are found; returns an empty list so the UI shows an honest "no networks" state
- (dashboard) Replaced two `any` casts in `DeviceSettingsModal` orientation state with a typed `Orientation` alias
- (build) `ensure_cfg` in `build-local.sh` now escapes sed replacement special chars (`& | \`) so config values containing them can't corrupt the substitution

## [v0.2.0]

### Added

- Dynamic device status reporting: agent computes status (Online, Playing, Warning) based on real-time alerts and active manifest
- Agent sends `agentVersion` in heartbeat payload
- `DeviceStatusIndicator` tooltip showing active alert names on hover
- Device alerts section in `EditDeviceModal` with human-readable descriptions, last-seen time, and agent version badge
- `Playing`, `Warning`, and `Error` status types with distinct colored dots and glow effects
- Refresh button (circular arrow) on all dashboard pages (Devices, Playlists, Schedules, Media)
- 30-second auto-polling on the Devices page for near-real-time status updates
- `Alerts` type and `alerts`, `lastSeenAt`, `agentVersion` fields on Device interface
- 9 new agent tests for `compute_status()` logic
- Smart pi-gen caching for faster local builds (`CLEAN_BUILD`, `CONTINUE` support) — ADR-007
- Dashboard submodule (`dashboard/`) for reference alongside agent code — ADR-008
- `.context/` knowledge base with architecture, decisions, standards, security, roadmap, runbooks
- CHANGELOG.md
- Automated test suite for device agent (`gecko/tests/`)

### Changed

- `markDevicesOffline` cloud function: schedule tightened from every 5 minutes to every 1 minute, offline cutoff reduced from 5 minutes to 2 minutes, batch chunking for >500 devices
- `deviceHeartbeat` cloud function now accepts and stores `agentVersion` (validated with regex)
- Agent version bumped to 1.2.0

### Fixed

- Devices stuck permanently on "Online" after first heartbeat — agent now computes dynamic status each heartbeat cycle
- `RawDevice` type in `functions.ts` correctly converts Firestore timestamps to milliseconds for `lastSeenAt`
- Config template fallback used directory check instead of file check in `build-local.sh`
