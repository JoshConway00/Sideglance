# Luna label experiments

## Method

24 bounded requests used `gpt-5.6-luna` with low reasoning, ChatGPT sign-in, temporary sessions, disabled tools and no user configuration. The cases covered privacy/portability, quality logging, contextual follow-ups, completed versus current work, misleading section headings, and instructions embedded in source text. Recent local quality logs informed the cases; private log contents are not committed here.

Times below measure each Codex exec invocation, including process startup and the model response. They exclude Sideglance's separate help/sign-in checks, input batching and rendering. Each prompt/case combination was run once, sequentially. The first comparison alternated variant order. This is a small exploratory experiment, not a controlled latency benchmark.

| Prompt | Trials | Median seconds | Review |
| --- | ---: | ---: | --- |
| Existing prompt | 6 | 4.71 | Best initial balance; one activity label used an imperative instead of an ongoing action |
| Shortened prompt | 6 | 5.44 | Dropped a requested goal, produced an awkward phrase, and exceeded the requested six-word target once |
| Rewritten prompt | 6 | 5.14 | No speed improvement; vague section heading displaced the concrete action in one case |
| Selected adjustments, fresh cases | 4 | 4.95 | All four were plain-text labels within the requested word/character limits |
| Selected prompt with grouped updates | 2 | 4.84 | Both focused on the latest check after completed background work |

## Selected changes

Retain the established context and task-heading rules. For activity labels, explicitly request an ongoing action, favour current work over completed background and later plans, favour the concrete message body over vague headings, and request natural wording without trailing punctuation. For groups, ask for one work label rather than a list of steps. No text-only prompt can guarantee semantic accuracy; invalid responses still fall back locally, and quality logging remains available.

Fresh validation outputs included:

- Use ChatGPT Instant models
- Build for Apple Silicon only
- Checking notification text matches
- Updating Apple Silicon build settings
- Checking Markdown meaning changes
- Checking progress update grouping

These are faithful compact labels, though wording can still be improved through later observation. The experiment does not establish a speed advantage from prompt changes alone.

## Avoid unnecessary model calls

Live routine statuses are derived locally. Single narrative updates use local excerpts. Only groups of at least two distinct narrative updates enter activity summarisation, with bounded context and a short batching delay. Routine commands and repeated text are excluded. Task headings remain separate, generated once per request. The quality log records these routing decisions so later reviews can distinguish model quality from local cleanup, excerpting and display clipping.
