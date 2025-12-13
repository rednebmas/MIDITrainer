# plans/004_stats_queries_and_graphs.md

## Goal

Provide graph-ready stats that identify systematic inaccuracies by scale degree, interval, and note index; support per-key and aggregated views.

## Requirements

### Queries
Must support at least:
- Mistake rate by **expected scale degree**
- Expected degree → guessed degree counts (confusion-style)
- Mistake rate by **expected interval**
- Expected interval → guessed interval counts
- Mistake rate by **note index in melody**
- Filters:
  - Per key+scale (exact context)
  - Aggregated across all keys/scales
  - Optional: time range (nice-to-have; can be “all time” first)

### UI
- Stats screen shows at least:
  - degree mistakes distribution
  - interval mistakes distribution
  - note-index mistakes distribution
- Provide a toggle: “All Keys” vs “Current Key”
- Use Swift Charts initially.

### Performance
- Queries should be fast on-device; ensure indexes used by the chosen query shapes.

## Suggested files (non-binding)

- `Features/Stats/StatsView.swift`
- `Features/Stats/StatsModel.swift`
- `Domain/Stats/StatSeries.swift` (graph-ready)
- `Persistence/Repositories/StatsRepository.swift`

## Acceptance criteria

- After generating some practice data, Stats shows the three distributions.
- Toggle between “All Keys” and “Current Key” updates graphs.
- No SQL in Views; StatsModel only calls repository methods.
- Add one integration test with a small fixture DB verifying at least one aggregation query.
