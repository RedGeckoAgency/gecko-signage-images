# Changelog

All notable changes to the Gecko Signage platform are documented in this file.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Image releases are tagged as `v<major>.<minor>.<patch>`.

## [Unreleased]

### Added

- Smart pi-gen caching for faster local builds (`CLEAN_BUILD`, `CONTINUE` support) — ADR-007
- Dashboard submodule (`dashboard/`) for reference alongside agent code — ADR-008
- `.context/` knowledge base with architecture, decisions, standards, security, roadmap, runbooks
- CHANGELOG.md
- Automated test suite for device agent (`gecko/tests/`)

### Fixed

- Config template fallback used directory check instead of file check in `build-local.sh`
