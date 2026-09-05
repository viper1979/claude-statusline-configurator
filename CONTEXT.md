# ccstatusline

Renders Claude Code's session payload as a configurable status line. The vocabulary
below covers the concepts that are easy to confuse because several of them count
tokens and several of them talk about caching.

## Language

**Payload**:
The JSON object Claude Code pipes to the status line once per render. The single
source of truth for every field; anything not in it is either derived or detected.
_Avoid_: Input, session data, stdin JSON

**Field**:
One configured entry in a status line — a payload key plus its data type, format
and colors. A field is a rendering decision; a payload key is data.
_Avoid_: Item, element, column

**Derived Field**:
A value the status line computes itself and injects into the payload before
rendering, because Claude Code does not report it directly.
_Avoid_: Computed field, virtual field

**Render Context**:
Everything the status line derives from the configuration once per render in order to
render any Field: the active theme's colors and thresholds, the per-field theme lookup,
the known payload keys, and the new-fields logging settings. One value per render, built
before the first Field is rendered and never changed while rendering.
_Avoid_: Theme context, render settings, script scope, globals

## Model behavior

**Effort Level**:
The reasoning depth of the current turn — `low`, `medium`, `high`, `xhigh` or
`max`. Read exclusively from the payload's `effort.level`, never from
`settings.json`: Claude Code resolves the per-model `modelSettings.<model>.effortLevel`
against the global `effortLevel` fallback and reports only the resolved value,
including mid-session `/effort` changes. The key is absent when the active model
has no effort parameter, which renders as an empty field.
_Avoid_: Reasoning effort, thinking level, reading it from settings

## Tokens and caching

**Context Window**:
The token budget of the current session — how much of the model's window is filled
and how much remains. About *capacity*.
_Avoid_: Context, window size

**Prompt Cache**:
Anthropic's caching of a stable prompt prefix across requests. About *reuse* of
tokens, not capacity. A separate concept from Context Window even though both
count tokens.
_Avoid_: Cache, context cache

**Cache Hit Ratio**:
The share of input tokens served from the prompt cache. Reported natively by
Claude Code as `prompt_cache.hit_ratio`, a value between 0 and 1; the status line
displays it as a percentage. The canonical term.
_Avoid_: Hit rate, cache efficiency

**Cache Efficiency**:
The status line's own earlier name for Cache Hit Ratio, computed as
`cache_read_input_tokens / total_input_tokens * 100` before Claude Code reported
the value itself. Deprecated: it survives only so existing configurations keep
working, and is now fed from Cache Hit Ratio.
_Avoid_: Using it in new work — use Cache Hit Ratio

## Workspace

**Worktree**:
A git worktree Claude Code is operating in, distinct from the original checkout
the session started from. The payload reports the worktree's branch; the status
line falls back to detecting the branch itself when the payload omits it.
_Avoid_: Branch, checkout

**Scratchpad Dir**:
The per-session temporary directory Claude Code provides for throwaway files.
Not part of the user's project.
_Avoid_: Temp dir, working directory
