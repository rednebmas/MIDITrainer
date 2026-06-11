# Adaptive Practice Mode

A scheduler mode (`SchedulerMode.adaptive`) that keeps practice near a
user-set target accuracy and remediates failures with 2-note fragment drills
instead of grinding full melodies. Shipped June 2026.

## Motivation

Analysis of 6 months of practice history (Dec 2025–Jun 2026) showed half of
practiced notes were interval types at ≤56% first-guess accuracy (ascending
leaps >P4 at 23%, near the 14% guessing floor), a 26% re-ask pass rate, and
queue items stuck for ~110 days with ~7 failures each. The escalating
clearance design re-served exactly what the user failed, at full difficulty,
indefinitely. Learning research (Wilson et al. 2019 "85% rule", challenge
point framework) puts the productive zone well above where that queue sat.

## Behavior

- **Target accuracy slider** (65–95%, default 70%): a thermostat
  (`DifficultyDial`) tracks rolling first-guess accuracy over the last 100
  notes and steers a difficulty dial — harder when running hot, easier when
  cold.
- **Difficulty-targeted fresh questions**: candidate seeds are sampled,
  generated, scored by `MelodyAccuracyPredictor` (per-interval first-guess
  accuracy smoothed toward leap-size priors), and the closest to the dial is
  served. The chosen seed persists, so failures re-ask the identical melody.
- **Fragment drills**: a melody failed on the first guess spawns 2-note
  drills — the transition into each missed note (index ≥ 1), stored
  key-relative (degree + octave) so drills transpose with key changes.
  Drills clear after 3 consecutive first-guess passes with ≥2 other
  questions between repeats; failures reset the streak. Identical degree
  transitions deduplicate and clear together. Labeled e.g.
  "↑P4 drill from Dark Horse".
- **Fragments gate the melody**: the failed melody's re-ask waits until its
  fragments clear, then arrives as a "rescue" one clearance gap later.
  Passing the rescue is the only way out of the queue — melodies are never
  retired, and clearance never escalates in this mode.
- **Immediate drills** (toggle, default off): when on, a failed melody's
  fragments are asked right after it completes, before spaced rotation.

## Question priority

1. Immediate drills (toggle on only)
2. Due spaced fragments (FIFO)
3. Rescue re-asks (ungated, waited one clearance gap)
4. Fresh melody at the dial

## Data

- `fragment_queue` table (migration v8), `FragmentQueueRepository`.
- Parents reuse `mistake_queue`; gating is derived from fragment rows
  referencing `parentMistakeId`.
- Fragment questions persist as `melody_sequence` rows with
  `sourceId = 'fragment'` and their attempts flow into `note_attempt`, so
  interval stats improve from drills (filter them out via sourceId).
- Difficulty model reads first-guess-only stats (first attempt per
  melody_note), 90-day recency window with all-time fallback.

## Tuning constants

All in `AdaptiveTuning` (Services/Scheduling/Adaptive/): dial step/deadband/
window, candidate count, clear streak, fragment spacing, smoothing priors,
stats recency.

## Acceptance criteria (verified by tests)

- Failed fresh melody queues parent + fragments; index-0-only failures queue
  an ungated parent. (`AdaptiveSchedulerTests`)
- Streak-3 clears a fragment; the last clear arms the rescue; rescue pass
  deletes the parent; rescue failure re-gates with no escalation.
- Fragments transpose to the current key at ask time.
- End-to-end: a due fragment plays as a real 2-note question through
  PracticeEngine, records attempts, and advances the streak.
  (`AdaptiveFragmentIntegrationTests`)
- Scheduler mode changes apply without app relaunch (coordinator now
  subscribes to the settings store — previously broken for all modes).
