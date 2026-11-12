# Architecture

## UI
- Components read design tokens, never literal colours or sizes.
- Every visible string goes through `t("key")` against the backend's translation catalog.
