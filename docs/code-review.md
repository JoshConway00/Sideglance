# Sideglance publication review

## Privacy

The publishable source contains no developer account, personal task ID, private business context, home-directory path, credentials, captured chat logs or user preference exports. Test email addresses use example.com and fixture data is synthetic. Build outputs and local state/credential exports are ignored by Git.

Historical development snapshots and identifying commit metadata were excluded from the clean publication repository. A private rollback copy is stored outside this project. Do not upload that backup.

A pattern scan is a useful check, not a guarantee against every possible secret. Review future additions, especially images, data files and generated artifacts, before publishing.

## macOS portability

- Apple Silicon-only executable: arm64; minimum macOS 14.0 in the compiler target and application metadata.
- Apple Intelligence is optional, weak-linked and gated by macOS version and model availability.
- User-relative data and settings; absolute CODEX_HOME is honoured when provided in the launch environment.
- Numbered Codex state databases are discovered; optional name, project, archive, source and sort columns are handled.
- Standard, user-local and registered application discovery; task links use the registered Codex handler.
- No fixed task, account, email recipient, project folder or AI model is required on first launch.
- Build caches are private per-build temporary directories, cleaned after builds.
- Tests use synthetic temporary data and need no personal task or signed-in account.

## Verification

The build runs parser, state, process, custom data-home and database compatibility tests. Inspect the arm64 binary with lipo and its deployment target with vtool. These checks do not replace testing on a second Apple Silicon Mac or macOS 14. Intel Macs are not supported.

Codex remains an external dependency with evolving internal log/database formats. A compatible installation and ChatGPT sign-in are required only for Codex summaries. Download distribution still needs developer signing/notarization. This review did not push or publish changes. Remote-tracking branches existed locally; any history already on a remote requires a separate cleanup.
