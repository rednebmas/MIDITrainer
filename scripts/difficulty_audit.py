"""Audit practice difficulty: where do first-guess error rates sit relative to
the productive-learning zone, and is the mistake queue clearing or grinding?

Usage: difficulty_audit.py <miditrainer.sqlite>
"""

import sqlite3
import sys

import pandas as pd

from history_data import first_guesses, interval_bucket, load_attempts

df = load_attempts(sys.argv[1])
firsts = first_guesses(df)
recent = firsts[firsts["when"] >= firsts["when"].max() - pd.Timedelta(days=60)]

print("=== last 60 days: share of practiced notes by difficulty zone ===")
f = recent.dropna(subset=["expectedInterval"]).copy()
f["bucket"] = interval_bucket(f["expectedInterval"])
by_bucket = f.groupby("bucket")["isCorrect"].agg(["mean", "count"])
by_bucket["share"] = by_bucket["count"] / by_bucket["count"].sum()
print(by_bucket.sort_values("mean").round(3).to_string())

zones = pd.cut(f.groupby("bucket")["isCorrect"].transform("mean"),
               [0, 0.5, 0.7, 0.9, 1.0],
               labels=["near-chance (<50%)", "hard (50-70%)",
                       "productive (70-90%)", "easy (>90%)"])
print("\nshare of notes by zone of their interval type:")
print(f.groupby(zones)["isCorrect"].agg(share="count").div(len(f)).round(3).to_string())

print("\n=== melody-level: first-playthrough outcome ===")
pt0 = df[df["playthrough"] == 0]
perfect = pt0[pt0["guess"] == 0].groupby("sequenceId")["isCorrect"].all()
seq_kind = df.groupby("sequenceId")[["repeat_kind", "when"]].first()
seq = seq_kind.join(perfect.rename("perfect"))
recent_seq = seq[seq["when"] >= seq["when"].max() - pd.Timedelta(days=60)]
print("perfect rate by ask type (last 60 days):")
print(recent_seq.groupby("repeat_kind")["perfect"].agg(["mean", "count"]).round(3).to_string())

print("\n=== mistake queue state (current DB) ===")
conn = sqlite3.connect(sys.argv[1])
q = pd.read_sql_query(
    "SELECT totalFailures, currentClearanceDistance, questionsSinceQueued, "
    "queuedAt FROM mistake_queue", conn)
q["queued_days_ago"] = (pd.Timestamp.now() - pd.to_datetime(q["queuedAt"], unit="s")).dt.days
print(f"items queued: {len(q)}")
print(q[["totalFailures", "currentClearanceDistance", "queued_days_ago"]]
      .describe().loc[["mean", "50%", "max"]].round(1).to_string())
