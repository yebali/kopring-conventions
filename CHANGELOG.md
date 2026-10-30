# Changelog

Rule identifiers added, changed, removed or renumbered, newest first. A consuming project checks this list when it updates the skill, because its own rule document overrides the skill by identifier.

## 2026-10-30

- **Renumbered** `CTL-30` → `CTL-32` (Response carries only the fields the frontend reads). `CTL-30` is a consuming project's own rule and stays a gap.
- **Changed** `CTL-32`: scoped to Responses consumed only by the web frontend; an unused field is removed directly, without a deprecation phase, and the frontend developers are told.
- **Changed** `CTL-31`: time-relative values (`isExpired`) and policy calculations stay in the Response; the shared `PaginationResponse` keeps its page metadata.
- **Changed** `REP-34`: a time-relative judgement is a method taking the time (`isExpiredAt(now)`), not a getter reading the clock.
- **Added** `CTL-31`, `CTL-32` (as `CTL-30`), `REP-34`.
