# plans/007_replay_incorrect_sequences.md

## Goal

Let the user browse and replay sequences where they made mistakes, so they can target weak spots.

## Requirements

- Surface a list of past sequences that include at least one incorrect attempt.
- Show lightweight metadata per sequence to help choose what to replay:
  - key + scale
  - timestamp/session
  - total notes vs number of mistakes
- Provide a “Replay” action that routes the saved melody back through the existing playback flow (respecting stored BPM and rhythm).
- Replay uses the stored melody exactly as originally generated (no regeneration).
- Keep practice loop semantics: after replay, app waits for correct input for each note and logs new attempts to the same persistence model.

## Architecture notes

- Add a repository/query that returns sequences with mistakes, joined to counts of incorrect attempts.
- Expose this data via a feature model; avoid SQL in Views.
- Reuse the existing playback scheduler and practice engine to execute a stored sequence (no new scheduling logic).

## Acceptance criteria

- UI lists sequences that contain mistakes with key/scale, timestamp, and mistake count.
- Tapping “Replay” plays the stored sequence and enters the usual awaiting-input flow.
- Replayed sequences use their original BPM/rhythm and pitch content.
- New attempts from replays are persisted alongside prior attempts.
