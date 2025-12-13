import Foundation
import SQLite3

/// Repository responsible for clearing persisted practice history.
/// Clears attempts, sequences, sessions, snapshots, and the mistake queue.
final class HistoryRepository {
    private let db: Database

    init(db: Database) {
        self.db = db
    }

    func resetHistory() throws {
        try db.readWrite { handle in
            // Clear tables that store practice history and scheduling state.
            try Database.execute(statement: "DELETE FROM note_attempt;", db: handle)
            try Database.execute(statement: "DELETE FROM melody_note;", db: handle)
            try Database.execute(statement: "DELETE FROM melody_sequence;", db: handle)
            try Database.execute(statement: "DELETE FROM practice_session;", db: handle)
            try Database.execute(statement: "DELETE FROM settings_snapshot;", db: handle)
            try Database.execute(statement: "DELETE FROM mistake_queue;", db: handle)
        }
    }
}
