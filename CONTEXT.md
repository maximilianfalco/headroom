# Headroom

Shows how much of a Claude or Codex plan is left, and how much is expected to be left when each limit resets.

## Language

**Limit**:
One cap on the plan, with a percent used and an optional reset time. The session, the week, and each per-model window are limits. Codex reports which limits exist; a missing limit is not a zero-percent limit.
_Avoid_: bucket, cap, quota

**Window**:
The span of time a limit counts over, from its last reset to its next one. Use Codex's returned duration: its primary window can be weekly, and either window can be absent.

**Reset**:
The moment a limit's window ends and its percent drops back toward zero.

**Sample**:
One reading of a limit's percent, taken on one poll.

**Projection**:
The percent a limit is expected to reach when its window ends.
_Avoid_: prediction, forecast, estimate

**Burn rate**:
New tokens per minute across the local session window so far. Codex uses the last five hours when no five-hour plan window is active. Cache reads stay separate.
