# Headroom

Shows how much of a Claude plan is left, and how much is expected to be left when each limit resets.

## Language

**Limit**:
One cap on the plan, with a percent used and a time it resets. The five hour session, the week, and each per-model week are limits.
_Avoid_: bucket, cap, quota

**Window**:
The span of time a limit counts over, from its last reset to its next one.

**Reset**:
The moment a limit's window ends and its percent drops back toward zero.

**Sample**:
One reading of a limit's percent, taken on one poll.

**Projection**:
The percent a limit is expected to reach when its window ends.
_Avoid_: prediction, forecast, estimate

**Burn rate**:
How fast Claude Code is spending new tokens right now, per minute, read from the local logs.
