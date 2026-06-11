"""Load and transform MIDITrainer practice history from the app's SQLite DB.

Key concepts derived from the app's mechanics (PracticeEngine/ScoringService):
- The user keeps guessing a note until correct, so attempts at one noteIndex
  repeat until isCorrect=1. "First guess" = the first attempt at a note.
- After an imperfect playthrough the melody replays under the same sequenceId;
  a drop in noteIndex marks a new playthrough.
- A melody is identified by its generation seed. The same seed recurs when the
  mistake queue re-asks a failed melody and when the song library re-samples a
  phrase, so ask_no counts how many times that exact melody has been asked.
"""

import sqlite3

import pandas as pd

PACIFIC = "America/Los_Angeles"

ATTEMPT_SQL = """
SELECT a.sequenceId, a.noteIndexInMelody AS noteIndex,
       a.expectedInterval, a.expectedScaleDegree,
       a.isCorrect, a.timestamp,
       s.seed, s.sourceName, s.sessionId
FROM note_attempt a
JOIN melody_sequence s ON s.id = a.sequenceId
WHERE a.melodyNoteId IS NOT NULL
ORDER BY a.sequenceId, a.timestamp
"""


def load_attempts(db_path: str) -> pd.DataFrame:
    with sqlite3.connect(db_path) as conn:
        df = pd.read_sql_query(ATTEMPT_SQL, conn)
    when = pd.to_datetime(df["timestamp"], unit="s", utc=True)
    df["when"] = when.dt.tz_convert(PACIFIC).dt.tz_localize(None)
    df["source"] = df["sourceName"].isna().map(
        {True: "random melodies", False: "real songs"}
    )
    mark_playthroughs(df)
    mark_ask_number(df)
    return df


def mark_playthroughs(df: pd.DataFrame) -> None:
    prev = df.groupby("sequenceId")["noteIndex"].shift()
    restart = df["noteIndex"] < prev.fillna(df["noteIndex"])
    df["playthrough"] = restart.groupby(df["sequenceId"]).cumsum()
    df["guess"] = df.groupby(["sequenceId", "playthrough", "noteIndex"]).cumcount()


def mark_ask_number(df: pd.DataFrame) -> None:
    seqs = (
        df.groupby("sequenceId")
        .agg(seed=("seed", "first"), session=("sessionId", "first"),
             start=("timestamp", "min"))
        .sort_values("start")
        .reset_index()
        .set_index("sequenceId")
    )
    seqs["ask_no"] = seqs.groupby("seed").cumcount()
    prev_session = seqs.groupby("seed")["session"].shift()
    kind = pd.Series("cross-session", index=seqs.index)
    kind[seqs["session"] == prev_session] = "same-session"
    kind[seqs["ask_no"] == 0] = "novel"
    df["ask_no"] = df["sequenceId"].map(seqs["ask_no"]).fillna(0)
    df["repeat_kind"] = df["sequenceId"].map(kind)


def first_guesses(df: pd.DataFrame) -> pd.DataFrame:
    """First guess at each note on the first playthrough of each melody."""
    return df[(df["playthrough"] == 0) & (df["guess"] == 0)]


def melody_stats(df: pd.DataFrame) -> pd.DataFrame:
    """Per melody ask: was the first playthrough perfect, guesses per note."""
    pt0 = df[df["playthrough"] == 0]
    per_seq = pt0.groupby("sequenceId").agg(
        when=("when", "min"),
        source=("source", "first"),
        notes=("noteIndex", "nunique"),
        attempts=("noteIndex", "size"),
        first_correct=("isCorrect", lambda s: s[pt0.loc[s.index, "guess"] == 0].mean()),
    )
    per_seq["perfect"] = per_seq["first_correct"] == 1.0
    per_seq["guesses_per_note"] = per_seq["attempts"] / per_seq["notes"]
    return per_seq.reset_index()


def interval_bucket(semitones: pd.Series) -> pd.Series:
    mag = semitones.abs()
    size = pd.cut(mag, [-0.5, 0.5, 2, 4, 12], labels=["same", "step", "skip", "leap"])
    direction = semitones.map(lambda s: "↑" if s > 0 else ("↓" if s < 0 else ""))
    return direction.str.cat(size.astype(str))


def adjusted_accuracy(firsts: pd.DataFrame, group_key) -> pd.DataFrame:
    """Accuracy per group, standardized to the global difficulty mix.

    Difficulty cells are interval bucket × novel/same-session repeat/
    cross-session repeat, so a period that asks harder intervals or more
    review melodies is compared apples-to-apples.
    """
    f = firsts.dropna(subset=["expectedInterval"]).copy()
    f["cell"] = interval_bucket(f["expectedInterval"]) + "|" + f["repeat_kind"]
    mix = f["cell"].value_counts(normalize=True)
    rows = []
    for key, sub in f.groupby(group_key):
        cells = sub.groupby("cell")["isCorrect"].agg(["mean", "count"])
        cells = cells[cells["count"] >= 10]
        w = mix[cells.index]
        rows.append({"key": key, "raw": sub["isCorrect"].mean(),
                     "adjusted": (cells["mean"] * w).sum() / w.sum(),
                     "n": len(sub)})
    return pd.DataFrame(rows)


def response_times(df: pd.DataFrame, max_dt: float = 20.0) -> pd.DataFrame:
    """Seconds between consecutive correct notes, both right on the first try.

    Restricted to adjacent notes inside the first playthrough so the gap
    measures recognition speed, not replay playback or retries.
    """
    c = df[(df["playthrough"] == 0) & (df["isCorrect"] == 1)].sort_values(
        ["sequenceId", "noteIndex"]
    )
    grp = c.groupby("sequenceId")
    dt = c["timestamp"] - grp["timestamp"].shift()
    adjacent = c["noteIndex"] == grp["noteIndex"].shift() + 1
    clean = adjacent & (c["guess"] == 0) & dt.between(0.05, max_dt)
    return c[clean].assign(dt=dt[clean])
