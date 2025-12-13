# plans/007_replay_incorrect_sequences.md

## Goal

Let the user browse and replay sequences where they made mistakes, so they can target weak spots.

## Requirements

- Allow the user to build a **practice session** from the most recent X incorrect sequences (unique by sequence), where X is user-selectable.
- Surface metadata for the candidate pool to confirm what’s being drilled:
  - key + scale
  - timestamp/session
  - total notes vs number of mistakes
- Session behavior:
  - Collect the most recent X sequences that had mistakes; dedupe by sequence ID.
  - Maintain an in-memory bucket; randomly choose one sequence to quiz.
  - If the user answers a sequence **correctly on the first attempt** for every note, remove it from the bucket.
  - Continue quizzing randomly from the remaining bucket until empty.
- Provide a way to start/end this “incorrect sequences” practice session and to adjust X.
- Replay uses the stored melody exactly as originally generated (no regeneration); normal practice loop semantics apply (await correct input per note; log new attempts).

## Architecture notes

- Add a repository/query that returns sequences with mistakes, joined to counts of incorrect attempts.
- Expose this data via a feature model; avoid SQL in Views.
- Reuse the existing playback scheduler and practice engine to execute a stored sequence (no new scheduling logic).

## Acceptance criteria

- UI allows selecting “last X incorrect sequences” (user chooses X) and starting a session.
- Session quizzing randomly picks from that bucket; sequences drop out once answered perfectly on first attempt.
- Sequences use their original BPM/rhythm/pitches.
- New attempts from these drills persist as normal; bucket is built from most recent incorrect sequences.
