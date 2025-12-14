# Weakness-Focused Scheduler Plan

## Overview

Create a new scheduler mode that prioritizes sequences the user has historically struggled with, while still providing short-term reinforcement via the existing Spaced Mistakes system.

## Terminology

- **Asking**: Each time a sequence (identified by seed) is presented to the user
- **First attempt**: The user's initial playthrough of an asking, before any replays
- **First-attempt failure**: The user made at least one mistake during their first attempt at an asking (requiring replay)
- **Weakness**: A sequence (seed) that has a high rate of first-attempt failures across multiple askings

## Goals

1. **Historical weakness focus**: Prioritize sequences (by seed) that have the highest first-attempt failure count
2. **Weighted selection**: Weight sequences with multiple first-attempt failures more heavily than single failures
3. **Short-term reinforcement**: Integrate with Spaced Mistakes logic so immediate mistakes still get re-asked with clearance distances
4. **Code reuse**: Compose with existing `SpacedMistakeScheduler` rather than duplicating it

## Data Model

### Existing Schema (No New Tables Needed)

First-attempt failures can be derived from existing tables:

- `melody_sequence`: Each row represents one asking of a sequence (id, seed, settingsSnapshotId)
- `note_attempt`: Each row represents one note played (sequenceId, isCorrect)

**Key insight**: If ANY `note_attempt` row for a given `sequenceId` has `isCorrect = 0`, that asking was a first-attempt failure. This is because mistakes only occur on the first attempt - replays continue until perfect.

### Weakness Query Logic

1. For each `melody_sequence`, check if it has any `note_attempt` with `isCorrect = 0`
2. Group by seed (and settings) to aggregate across multiple askings of the same sequence
3. Count first-attempt failures per seed
4. Return seeds ordered by failure count descending

This is similar to the existing `firstTryAccuracy` query in `StatsRepository`, but aggregated by seed rather than counting overall success rate.

## Architecture

### New Components

#### 1. `WeaknessFocusedScheduler`
**Path**: `MIDITrainer/Services/Scheduling/WeaknessFocusedScheduler.swift`

Implements `QuestionScheduler` protocol. Composes with `SpacedMistakeScheduler` for short-term reinforcement.

**Behavior**:
1. First, check if the composed `SpacedMistakeScheduler` has a due re-ask → return it (immediate reinforcement takes priority)
2. Otherwise, query for historical weaknesses and select one using weighted random selection
3. If no weaknesses exist, return fresh question

#### 2. New Method in `StatsRepository`
**Path**: `MIDITrainer/Persistence/Repositories/StatsRepository.swift`

Add method: `topWeaknesses(for settings: PracticeSettingsSnapshot, limit: Int) -> [WeaknessEntry]`

Returns seeds with the most first-attempt failures for the given settings, ordered by failure count descending.

#### 3. `WeaknessEntry` Model
**Path**: `MIDITrainer/Persistence/Repositories/StatsRepository.swift` (or separate file)

Properties:
- `seed: UInt64` - The sequence seed
- `timesAsked: Int` - How many times this seed was asked
- `firstAttemptFailures: Int` - How many askings resulted in first-attempt failure

### Selection Algorithm

**Weighted random selection** where weight = `firstAttemptFailures` count.

A sequence with 5 first-attempt failures is 5x more likely to be selected than one with 1 failure.

### Integration with Spaced Mistakes

The scheduler composes with `SpacedMistakeScheduler`:

1. **Immediate mistakes**: When user fails a sequence, it goes into the spaced queue for short-term reinforcement (3, 6, 9... questions later)
2. **Historical weaknesses**: When no spaced re-ask is due, select from historical weakness pool
3. **Outcome recording**: Delegate to the composed `SpacedMistakeScheduler`; no additional recording needed since we query existing `note_attempt` data

### Mode Registration

#### Update `SchedulerMode`
**Path**: `MIDITrainer/Domain/Practice/SchedulerMode.swift`

Add case: `weaknessFocused`

#### Update `SchedulingCoordinator`
**Path**: `MIDITrainer/Services/Scheduling/SchedulingCoordinator.swift`

Create `WeaknessFocusedScheduler` when mode is `.weaknessFocused`, passing in:
- A `SpacedMistakeScheduler` instance (for composition)
- Access to `StatsRepository` (for weakness queries)

## Implementation Steps

### Phase 1: Repository Query
1. Add `WeaknessEntry` struct
2. Implement `topWeaknesses(for:limit:)` in `StatsRepository`

### Phase 2: Scheduler Implementation
3. Create `WeaknessFocusedScheduler` implementing `QuestionScheduler`
4. Implement weighted selection
5. Compose with `SpacedMistakeScheduler`

### Phase 3: Integration
6. Add `weaknessFocused` case to `SchedulerMode`
7. Update `SchedulingCoordinator` to create the new scheduler

### Phase 4: Testing
8. Unit tests for `topWeaknesses` query
9. Unit tests for weighted selection
10. Integration tests for full scheduler flow

## Acceptance Criteria

1. Sequences with higher first-attempt failure counts appear more frequently
2. A sequence failed 5 times is 5x more likely to appear than one failed once
3. Immediate mistakes still follow spaced repetition (3, 6, 9... clearance)
4. Only weaknesses matching current settings are considered
5. Falls back to fresh questions if no weaknesses exist
6. No new database tables required

## Open Questions

1. **Minimum failures**: Should we require N first-attempt failures before considering a sequence a "weakness"? (Proposed: 1)
2. **Mix ratio**: Should there be a configurable ratio of weakness vs fresh questions? (e.g., 80% weakness, 20% fresh)
3. **UI feedback**: Should we show users which sequences are their "top weaknesses"?
