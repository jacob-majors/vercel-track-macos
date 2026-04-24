import Foundation

enum ProviderKind: String, CaseIterable, Identifiable {
    case vercel
    case github

    var id: String { rawValue }
    var title: String {
        switch self {
        case .vercel: "Vercel"
        case .github: "GitHub"
        }
    }
}

enum ProviderMode {
    case mock
    case live
}

enum DeploymentStatus: String {
    case building
    case queued
    case running
    case ready
    case completed
    case error
    case unknown

    var label: String {
        switch self {
        case .building: "Building"
        case .queued: "Queued"
        case .running: "Running"
        case .ready: "Ready"
        case .completed: "Succeeded"
        case .error: "Failed"
        case .unknown: "Unknown"
        }
    }
}

struct DeploymentItem: Identifiable, Hashable {
    let id: String
    let provider: ProviderKind
    let project: String
    let repo: String?
    let branch: String
    let commitMessage: String
    let status: DeploymentStatus
    let statusLabel: String
    let createdAt: Date
    let updatedAt: Date
    let creator: String
    let previewURL: URL?
    let externalURL: URL?
    let workflowName: String?
    let failureReason: String?
}

struct ProviderSnapshot {
    let kind: ProviderKind
    let mode: ProviderMode
    let notice: String
    let items: [DeploymentItem]
}

struct AppSnapshot {
    let updatedAt: Date
    let providers: [ProviderKind: ProviderSnapshot]
}
