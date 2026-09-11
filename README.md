# Sideglance

A small native macOS overlay for following local Codex activity. It shows one persistent dark notification card that updates as the chat progresses, with a coloured live status indicator, bold request title and softer summary text. The × dismisses a card and the chevron opens its Codex task. Outside those controls, clicks pass through. Full retained messages are available in Recent updates.

## Build and run

Run `./build.sh`, then open `build/Sideglance.app`. Building and running the tests requires an Apple Silicon Mac, Xcode command-line tools and an SDK containing Foundation Models (macOS 26 or newer SDK). The compiler and app metadata both target macOS 14. Apple Intelligence is optional and requires macOS 26 and an eligible Mac with its model ready.

The build creates an Apple Silicon-only (arm64) app, signs it locally, and runs separate offline regression tests. The tests use synthetic data and do not require a Codex account or personal task. The application does not include the test suite. This is a development build, not a notarized distribution package; macOS 14 runtime and cross-machine installation still require verification.

On first launch, a setup window opens with a simulated notification feed. Choose a starting local Codex chat (or choose later), then adjust display/position or drag the sample, set width, text size, background opacity and AI provider/model. Play/Pause and Replay control synthetic examples without AI requests. Save & finish applies settings and remembers the position; Cancel restores the prior frame and leaves settings unchanged. Reopen this window with **Set up Sideglance…** in the menu. Then choose a task through **Switch task** in the menu-bar menu. A valid saved task is restored on later launches. If none is available, Sideglance asks you to choose one rather than watching a developer-specific task.

## Controls

The menu-bar icon provides task selection, Open task, Recent updates, overlay visibility/positioning, pause and settings. Settings include summary provider, text size, background opacity, message lifetime, adaptive reading time, repeated-error grouping, optional input-request sound and launch at login.

The notification stays visible until dismissed, including after completion. New updates replace its contents instead of stacking cards. A completion badge fades after ten seconds; the menu-bar completion indicator stays until new activity. Positioning mode lets you drag/resize the overlay. Positions are stored per display; the old single-window position is used only for initial migration.

## Summaries and privacy

**Apple Intelligence** is the default summary provider and processes text on device. If it is unavailable, the card shows a summary-unavailable status and the original messages remain in Recent updates.

**Codex · uses subscription allowance** is opt-in under **Settings → Summary provider**. It sends bounded request/progress text to OpenAI using a compatible local Codex installation signed in with ChatGPT. Short follow-ups can include the preceding written response as context. It consumes Codex allowance; it is not ordinary ChatGPT chat usage or a zero-usage option. A regular ChatGPT installation alone is not sufficient.

Codex requests use temporary sessions (`--ephemeral`), read-only mode, disabled shell tools/apps/memories/web search, and ignore user configuration. By default no model is forced: Codex chooses its default model. A compatible model name can optionally be configured in setup. The app checks required flags and ChatGPT sign-in before requesting a summary. Model availability is checked by the request and reported as a compatibility failure if unavailable. Credentials are neither copied nor stored by Sideglance. API-key overrides are removed from its helper environment.

Only recent activity is eligible for automatic summaries. Opening an expired historical task does not automatically trigger inference. **Retry summaries · uses selected provider** explicitly refreshes the current labels, including historical ones, and is limited to once every five seconds. There are no automatic retries for an unchanged failed request. Switching task/provider or disabling titles cancels pending work. A summary request times out after 45 seconds; the local compatibility/sign-in checks each allow ten seconds.

Identical bounded inputs are cached in memory with eviction at 100 entries. Temporary output files have private permissions and are removed after requests. At most 20 timestamped, safe error categories are retained in local preferences; raw responses, monitored text and credentials are not retained as diagnostics. Errors distinguish installation, compatibility, sign-in, allowance, timeout and invalid output. There is no automatic cloud fallback from Apple Intelligence.

## Data and integration limits

The activity reader opens Codex's local database and session logs read-only. It scans for new log segments every two seconds and reads appended records every 250 milliseconds. It displays written messages, available reasoning summaries and generic tool activity, never raw reasoning, encrypted content, code or raw tool output. For app/browser actions, it reads only the dedicated display title from the known UI tool arguments, showing the title at start and its completion status afterwards.

Initial history reads are bounded to the last 16 MB. Display/history storage retains 250 entries; revision detection retains a 1,000-ID hash window. Very late revisions outside that window may be treated as new. Title dictionaries are pruned to retained entries and active keys. Malformed records are skipped; missing sources show a disconnected state. These local Codex formats are not a stable public integration contract and may change with Codex updates.

Task navigation uses the registered `codex:` handler. Summary executable discovery considers that app, standard application locations, user-local binaries and absolute PATH entries. There is no remote-task or ordinary ChatGPT-conversation connector.

## Feature requests

Choose **Feature request**, enter your request, then choose email or a prepared Codex implementation task. Email opens a draft for you to review and send. No recipient is supplied by default; configure your own address before use.

The Codex route asks for a feature branch, implementation, tests, self-review and a commit ready for a later PR. It does not request pushing, merging or PR creation. Configure the local source folder in Feature request settings when using a downloaded copy. Only feature details are included, not monitored history. Cancelled/failed requests remain as local drafts.

## Verification

`./build.sh` runs parser/tailer checks, selection/history-state checks, bounded-memory checks, summary eligibility, failure classification, executable discovery, and local process timeout/cancellation tests. Run the resulting `build/SideglanceTests` to repeat them.

Optional manual checks:

- `build/Sideglance.app/Contents/MacOS/Sideglance --check TASK_ID`: read the specified local activity log and print counts/state, not message contents.
- `build/Sideglance.app/Contents/MacOS/Sideglance --test-codex-summary`: request a synthetic fictional-button title through Codex. This consumes allowance.

The publication review and verification limits are in `docs/code-review.md`.

## Portability and publication

Paths are resolved relative to the current user, app and checkout. The reader honours an absolute `CODEX_HOME` environment variable when the app is launched with it; otherwise it uses the current user's `.codex` directory. It discovers numbered state databases and tolerates missing optional task columns. Codex's internal formats can still change; unknown schemas may not be supported. GUI apps launched from Finder do not automatically inherit shell environment settings.

Preferences, selected chats, monitor positions and drafts stay in macOS user preferences, outside this repository. No account, recipient, personal project, credentials or task IDs are provided by default. Build products and local state/credential exports are excluded from Git. Scan files before adding screenshots or other new assets.

The application targets macOS 14 or newer. On-device AI additionally requires an eligible Apple Silicon Mac with macOS 26 and Apple Intelligence enabled. Intel Macs are not supported. Compilation does not replace testing on a second Apple Silicon Mac and macOS 14. Download distribution still requires appropriate signing/notarization.

## Output quality logging

Settings → Output quality logging can record actual message content locally for reviewing summarisation. It is off by default. The menu can open the log folder or stop logging and clear both files. Logs live in the current user's `~/Library/Logs/Sideglance/`, outside the source repository. Keep them private: they may contain sensitive text from monitored tasks. Nothing uploads them automatically.

`quality.jsonl` and `quality-previous.jsonl` retain at most 5 MB each, with owner-only file permissions. Each JSON line has a timestamp and event type. Join source and presentation events using task ID, source key, prompt key and entry ID; join model requests/responses/results using request ID. Events contain parsed source messages, contextual/bounded model input, exact instructions, raw model response, accepted label, cache/fallback information, provider, requested model, reasoning setting and elapsed time. An automatic Codex model is explicitly unresolved; Apple does not expose the system model version. Source messages are decoded displayable text, not full raw Codex JSON, tool payloads or hidden reasoning.

Presentation events capture the text supplied to mounted cards before pixel clipping, plus Markdown/whitespace cleanup and line limits. They are not screenshots or proof that a hidden window was visible. Full source text and model output remain available alongside the compact display text. Logging begins when enabled; no historical model responses can be recovered. Cache hits are recorded as such and may lack a generation record if it predates logging or rotation. Logging failures can be inspected by choosing Open quality logs.

## Live status and grouped summaries

The small status line uses the current source activity directly (for example Running command or Ran command), with local Markdown cleanup and a 48-character limit. Routine tool events never enter activity-summary requests. Without a narrative label, their status is shown once rather than repeated in the body.

Each distinct narrative update is eligible for an AI summary, including a single message. When updates arrive together, only the latest is summarised, with reported results before current or planned work. While generation is pending, the last available summary stays visible. If none is available, a clear status is shown; source text is never cut into an excerpt. Generated summaries containing ellipses are rejected, and summary text wraps without tail truncation. The batch waits two seconds for a burst to settle, with a six-second maximum batching delay during continuous updates. The latest update is bounded to 2,400 characters; older updates cannot displace it in the model input. Tool events and repeated narrative text do not trigger new groups. Task headings are generated separately once per request. Provider changes or an explicit retry may regenerate the last group.

Quality logs identify deterministic live status, local excerpts and generated group summaries separately. Group requests include the member entry IDs and prompt version. The current prompt keeps labels brief, favours current work over completed background steps and treats source content as untrusted data. Model response time is separate from the short batching delay; routine statuses update without waiting for either.

Routine live-status changes update the existing notification card in place and refresh its lifetime. Its body and identity remain stable until a different narrative group or user request arrives; errors remain separate notifications. Dismissing a card also suppresses later routine updates to that same card. Recent updates and quality logs still retain every source event. Presentation logs include the separate live-activity source ID for comparison.

## Reviewing output quality

Choose **Review output quality…** from the menu bar to browse retained notifications. Search original or displayed text, filter for model attempts/local-only records or missing/failed output, and use the list or **Newer / Older** buttons (Command-Up / Command-Down) to move between notifications. Status changes are grouped under the same card; the **Update** picker steps through its recorded versions.

Switch between **Activity summary**, **Task heading** and **Live status** to compare source text with displayed text. **How it changed** distinguishes model-generated labels from local excerpts and task-title fallbacks, shows the recorded model/reasoning and duration, and exposes exact input/instructions/raw output in an expandable section. Each version uses only traces recorded by that point, so later model changes are not applied to earlier displays. Missing/rotated traces are marked instead of guessed.

The viewer reads both retained log files locally. Refresh is manual by default to keep navigation steady; optional **Live refresh** checks every two seconds. The displayed card preview is recorded text, not a screenshot of pixel clipping. No log contents are uploaded by the viewer.

## Contributing and licence

Sideglance is available under the [MIT licence](LICENSE). See [CONTRIBUTING.md](CONTRIBUTING.md) for contributing and [GitHub maintenance](docs/github-maintenance.md) for checks, repository settings and the manual draft-release process.
