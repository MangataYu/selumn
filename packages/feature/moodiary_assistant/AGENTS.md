# moodiary_assistant: assistant conventions

Dart owns prompts, retrieval, memory and permissions; Rust/rig adapts provider protocols and executes the tool loop. Keep rig dependencies pinned rather than tracking `main`.

## ChatGPT subscription providers

ChatGPT subscription providers use the distinct `chatgpt-subscription` protocol. `ChatGptProviderAuth` owns a `moodiary_chatgpt` session per provider; registrations, pending PKCE and rotating credentials live only in `ISecureKVStorage`, never in provider rows or `llm_key_` records. Readiness uses `hasCredentials`; inference, title generation and compaction resolve a fresh token with `getAccessToken`. The Android settings page supports manual loopback callback recovery. Its account model catalog replaces the saved slug list and never falls back to models.dev.

Rust's `llm/siwc.rs` adapts Rig's Responses request to the public subscription endpoint: full history, `store:false`, `stream:true`, namespaced local tools, and encrypted reasoning replay. It strips unsupported sampling/output-limit fields, rejects redirects and retries, and accepts a missing MIME only through the same strict SSE guard. Only `response.completed` with status `completed` succeeds. Tool execution and approval remain in the existing Rig loop. A silent connection is bounded by 30-second connect, 60-second idle and 180-second total timeouts; cancelling the UI does not add a separate FRB cancellation signal.

## Prompts and memory

- Keep `buildStableSystemPrompt` deterministic for identical inputs, including the permission mode; its bytes form the provider cache prefix. Preserve guardrails above user notes.
- Keep volatile turn context out of the stable prompt. Retrieve saved facts through `recallMemory` instead of injecting them into the prompt.
- When memory is disabled, remove memory tools from the allowed set, use the memory-off retrieval policy and omit the fact count from turn context.
- Standing preferences belong in user-written notes. Diary text must not enter `memories`, and saved facts must not enter the diary vector index.

## Tools and approval

- Keep the 10 active batch tools in `AssistantToolRegistry`; the four retired category tools retain their ids and summaries for history but are excluded from model registration, settings and execution.
- A tag filter uses the repository's keyword/date path, including descendants, and explicitly reports that semantic search was not run because the vector index has no tag metadata.
- Tool renames need entries in `renamedAssistantToolIds` so persisted chat history remains readable.
- Follow the UI's write paths: recycle-bin deletion uses `show: false`, content changes re-extract media, and replacing tags removes corresponding inline marks so deleted tags cannot return. Retired `categoryId` inputs fail instead of silently changing categories.
- Determine permission tiers from call arguments, including all batch items. Diary content replacement is destructive; moving an entry to the recycle bin is reversible. Preserve the confirmation behavior of `AssistantPermissionMode`.
- Only the exact bridge verdict `run` authorizes execution. Declines and bridge errors must skip the tool and return a skipped result to the model.
- Resolve pending `ToolApprovalGate` requests as declined on stop, disposal or timeout. A reply entered while approval is pending declines that call and queues the reply until the run ends.
- Keep tool execution sequential while the approval UI supports only one pending card; do not enable `tool_concurrency` without changing that contract.

## Streaming and errors

- Measure context length from the last completion turn's input tokens, not aggregate run usage. Preserve the Continue action for replies truncated by the length limit.
- Keep tool-history records distinct from user content; replay raw results only for tools whose `replayResult` permits it.
- Repair invalid tool names against the turn's allowed tools. Keep retries within rig's invalid-tool-call budget, and preserve `TurnDiscarded` handling so rejected-turn deltas disappear from the UI.
- Preserve structured error codes across the Rust/Dart bridge. Map codes to localized UI messages; never classify errors by matching English message text.
