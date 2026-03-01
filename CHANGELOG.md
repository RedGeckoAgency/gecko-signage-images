# Changelog

All notable changes to the Gecko Signage platform are documented in this file.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Image releases are tagged as `v<major>.<minor>.<patch>`.

## [Unreleased]

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
