import Foundation

/// A fetched email reduced to what detection needs: subject, sender, and body
/// (`isHTML` selects the render path). Built by the mail sources (Gmail API /
/// IMAP) and fed to the detector; carries no attachments or raw MIME.
public struct EmailMessage: Sendable, Equatable {
    public let id: String
    public let account: String
    public let sender: String
    public let subject: String
    public let body: String
    public let isHTML: Bool
    public let receivedAt: Date

    public init(
        id: String,
        account: String,
        sender: String,
        subject: String,
        body: String,
        isHTML: Bool,
        receivedAt: Date
    ) {
        self.id = id
        self.account = account
        self.sender = sender
        self.subject = subject
        self.body = body
        self.isHTML = isHTML
        self.receivedAt = receivedAt
    }
}

public struct DetectedCode: Sendable, Equatable {
    public let code: String
    public let confidence: Double
    public let account: String
    public let sender: String
    public let subject: String
    public let messageID: String
    public let receivedAt: Date
    /// Every signal that fired for this detection, so every decision is traceable.
    public let evidenceTrace: [String]

    // Adversarial contract (a permanent product invariant): the
    // detector PROPOSES, the human DISPOSES. Any consumer of DetectedCode MUST:
    //   * never auto-submit and never auto-fill without an explicit user action;
    //   * always display the code alongside `sender` identity;
    //   * render `confidence < 0.75` with a distinct "unverified" treatment.
    // Every input (styling, keywords, sender name) is attacker-controllable, so
    // these hold regardless of confidence.
    public static let unverifiedThreshold = 0.75
    public var isUnverified: Bool { confidence < DetectedCode.unverifiedThreshold }

    public init(
        code: String,
        confidence: Double,
        account: String,
        sender: String,
        subject: String,
        messageID: String,
        receivedAt: Date,
        evidenceTrace: [String] = []
    ) {
        self.code = code
        self.confidence = confidence
        self.account = account
        self.sender = sender
        self.subject = subject
        self.messageID = messageID
        self.receivedAt = receivedAt
        self.evidenceTrace = evidenceTrace
    }
}

/// A verification / sign-in / magic link found in an email. Same adversarial
/// contract as `DetectedCode`: never open it without an explicit user action,
/// always show `host` and `sender` alongside it, and give `isUnverified` links
/// a distinct treatment. The URL usually carries a live auth token, so it is
/// never logged or persisted.
public struct DetectedLink: Sendable, Equatable {
    public let url: URL
    public let confidence: Double
    public let account: String
    public let sender: String
    public let subject: String
    public let messageID: String
    public let receivedAt: Date
    /// Whether the link's site is the sender's own domain. Lookalike or
    /// redirect hosts (including legitimate click-trackers) read as unverified.
    public let hostMatchesSender: Bool
    /// Every signal that fired for this detection, so every decision is traceable.
    public let evidenceTrace: [String]

    public var host: String { url.host ?? url.absoluteString }
    public var isUnverified: Bool {
        confidence < DetectedCode.unverifiedThreshold || !hostMatchesSender
    }

    public init(
        url: URL,
        confidence: Double,
        account: String,
        sender: String,
        subject: String,
        messageID: String,
        receivedAt: Date,
        hostMatchesSender: Bool,
        evidenceTrace: [String] = []
    ) {
        self.url = url
        self.confidence = confidence
        self.account = account
        self.sender = sender
        self.subject = subject
        self.messageID = messageID
        self.receivedAt = receivedAt
        self.hostMatchesSender = hostMatchesSender
        self.evidenceTrace = evidenceTrace
    }
}
