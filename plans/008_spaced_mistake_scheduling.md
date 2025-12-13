# plans/008_spaced_mistake_scheduling.md

## Goal

Introduce a configurable scheduling system that reinforces incorrect sequences by re-asking them after spaced intervals, while allowing users to opt into simpler random scheduling.

## Requirements

- Queue every sequence that contains an incorrect attempt.
- Base scheduling flow (default “Spaced mistakes” mode):
  - When a sequence is answered incorrectly, add it to the queue with an initial clearance distance of 1 question.
  - After finishing that incorrect sequence, immediately ask a new (fresh) question.
  - After the fresh question, re-ask the queued incorrect sequence.
  - If answered correctly on that re-ask, remove it from the queue.
  - Future re-asks: require the current clearance distance’s intervening fresh questions before asking it again.
    - If answered incorrectly on a re-ask, multiply its minimum clearance distance by 3 (1 → 3 → 9 → …), reset its counter, and requeue.
  - A sequence is cleared when answered correctly on its due re-ask (at whatever minimum distance it currently holds).
  - The queue operates on a first-in, first-out basis.
- Support alternative scheduler modes:
  - “Spaced mistakes” (above).
  - “Random” (no reinforcement; just new questions).
  - Future-friendly: allow adding other schedulers later (e.g., “repeat until correct”).
- Tracking:
  - In-memory queue only (do not persist for now; could be reconstructed from attempts later).
  - Persist user’s selected scheduler mode.
- UX:
  - Toggle to choose scheduler mode.
  - Show when a “due mistake” question is coming up (e.g., “Re-ask pending in N”).
  - Allow clearing the queue manually.
  - Add scheduler selection to Settings.

## Architecture notes

- Add a scheduling coordinator that owns:
  - the queue of “mistake sequences” with their clearance distance and remaining-intervening-count
  - logic to decide whether the next question should be fresh or a due mistake sequence
  - a simple API that returns the next question (fresh or queued) for the practice engine to present
- Persist scheduling state in existing SQLite (new table or fields) so queues survive relaunch.
- Scheduler should expose a small protocol so alternate modes can be plugged in (spaced vs random).

## Acceptance criteria

- With “Spaced mistakes” enabled: an incorrect sequence is re-asked after one fresh question; if correct, it reappears after 3 questions; if correct again, after 9, etc.; if incorrect, it stays at its current distance and repeats after that many questions; cleared when correct at distance ≥ 3.
- With “Random” enabled: no reinforcement queue is used; only fresh questions are asked.
- User can switch modes; selection persists.
- Queue survives app relaunch and can be cleared manually.
