import Foundation

/// The thing a child shows a person in the room (`00_README.md` §3.11 / §3.1).
///
/// A protocol rather than a concrete type because the artefact differs per game — a
/// recording, a tower, a drawing, a replay — and the only shared requirement is that it can
/// be listed, replayed, and optionally exported behind the parental gate.
public protocol Artefact: Identifiable, Sendable {
    var createdAt: Date { get }
    /// Spoken when the artefact is opened, so a non-reader can browse the gallery.
    var spokenSummary: String { get }
}

public protocol ArtefactRecorder {
    associatedtype Recorded: Artefact
    /// Called at the moment the child does the thing worth showing. Never on a timer, and
    /// never for a failure — an artefact is something they chose to make.
    func record() throws -> Recorded
}

/// Export is the one thing in the app that can leave it, so it is gated (`00_README.md` §5.4)
/// and it never uploads: the destination is the system share sheet, which puts the parent in
/// control of where it goes.
public enum ArtefactExportDestination: Sendable {
    case systemShareSheet
}
