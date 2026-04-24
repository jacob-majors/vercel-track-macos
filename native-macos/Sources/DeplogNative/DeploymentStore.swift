import AppKit
import Foundation

@MainActor
final class DeploymentStore: ObservableObject {
    @Published var snapshot = SnapshotFactory.mockSnapshot()
    @Published var provider: ProviderKind = .vercel
    @Published var selectedItem: DeploymentItem?

    private let service = DeploymentService()
    private var refreshTask: Task<Void, Never>?

    func start() async {
        await refresh()
        if refreshTask == nil {
            refreshTask = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(5))
                    await refresh()
                }
            }
        }
    }

    func refresh() async {
        snapshot = await service.fetchSnapshot()

        if let selectedItem {
            let items = snapshot.providers[provider]?.items ?? []
            self.selectedItem = items.first(where: { $0.id == selectedItem.id })
        }
    }

    func open(_ url: URL?) {
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }

    deinit {
        refreshTask?.cancel()
    }
}

enum SnapshotFactory {
    static func mockSnapshot(now: Date = .now) -> AppSnapshot {
        func ago(minutes: Int) -> Date {
            now.addingTimeInterval(TimeInterval(-minutes * 60))
        }

        let vercelItems = [
            DeploymentItem(
                id: "v1",
                provider: .vercel,
                project: "Deplog Web",
                repo: "deplog-web",
                branch: "main",
                commitMessage: "Polish deployment status filters",
                status: .building,
                statusLabel: "Building...",
                createdAt: ago(minutes: 2),
                updatedAt: ago(minutes: 1),
                creator: "Jacob",
                previewURL: URL(string: "https://deplog-web.vercel.app"),
                externalURL: URL(string: "https://vercel.com/dashboard"),
                workflowName: nil,
                failureReason: nil
            ),
            DeploymentItem(
                id: "v2",
                provider: .vercel,
                project: "Marketing Site",
                repo: "marketing-site",
                branch: "staging",
                commitMessage: "Fix deployment summary layout",
                status: .ready,
                statusLabel: "Ready",
                createdAt: ago(minutes: 18),
                updatedAt: ago(minutes: 18),
                creator: "Ava",
                previewURL: URL(string: "https://marketing-site.vercel.app"),
                externalURL: URL(string: "https://vercel.com/dashboard"),
                workflowName: nil,
                failureReason: nil
            ),
            DeploymentItem(
                id: "v3",
                provider: .vercel,
                project: "Client Portal",
                repo: "client-portal",
                branch: "release",
                commitMessage: "Prepare billing fixes for release",
                status: .error,
                statusLabel: "Failed",
                createdAt: ago(minutes: 47),
                updatedAt: ago(minutes: 45),
                creator: "Mia",
                previewURL: URL(string: "https://client-portal.vercel.app"),
                externalURL: URL(string: "https://vercel.com/dashboard"),
                workflowName: nil,
                failureReason: "Build failed because the billing environment variable STRIPE_SECRET_KEY was missing during the production build."
            )
        ]

        let githubItems = [
            DeploymentItem(
                id: "g1",
                provider: .github,
                project: "Deplog Web",
                repo: "jacobmajors/deplog-web",
                branch: "main",
                commitMessage: "Deploy Preview",
                status: .running,
                statusLabel: "Running now",
                createdAt: ago(minutes: 3),
                updatedAt: ago(minutes: 1),
                creator: "jacobmajors",
                previewURL: nil,
                externalURL: URL(string: "https://github.com"),
                workflowName: "Deploy Preview",
                failureReason: nil
            ),
            DeploymentItem(
                id: "g2",
                provider: .github,
                project: "Client Portal",
                repo: "jacobmajors/client-portal",
                branch: "release",
                commitMessage: "CI",
                status: .completed,
                statusLabel: "Succeeded",
                createdAt: ago(minutes: 12),
                updatedAt: ago(minutes: 12),
                creator: "jacobmajors",
                previewURL: nil,
                externalURL: URL(string: "https://github.com"),
                workflowName: "CI",
                failureReason: nil
            )
        ]

        return AppSnapshot(
            updatedAt: now,
            providers: [
                .vercel: ProviderSnapshot(kind: .vercel, mode: .mock, notice: "Mock mode. Add VERCEL_TOKEN to load live deployments.", items: vercelItems),
                .github: ProviderSnapshot(kind: .github, mode: .mock, notice: "Mock mode. Add GITHUB_TOKEN and GITHUB_REPOS to load live workflow runs.", items: githubItems)
            ]
        )
    }
}

struct DeploymentService {
    func fetchSnapshot() async -> AppSnapshot {
        let env = Dotenv.load()
        async let vercel = fetchVercel(env: env)
        async let github = fetchGitHub(env: env)
        let vercelSnapshot = await vercel
        let githubSnapshot = await github

        let result = AppSnapshot(
            updatedAt: .now,
            providers: [
                .vercel: vercelSnapshot,
                .github: githubSnapshot
            ]
        )

        return result
    }

    private func fetchVercel(env: [String: String]) async -> ProviderSnapshot {
        guard let token = env["VERCEL_TOKEN"], !token.isEmpty else {
            return SnapshotFactory.mockSnapshot().providers[.vercel]!
        }

        do {
            var components = URLComponents(string: "https://api.vercel.com/v6/deployments")!
            var queryItems = [URLQueryItem(name: "limit", value: "12")]

            if let teamId = env["VERCEL_TEAM_ID"], !teamId.isEmpty {
                queryItems.append(.init(name: "teamId", value: teamId))
            }

            if let projectIds = env["VERCEL_PROJECT_IDS"], !projectIds.isEmpty {
                queryItems.append(.init(name: "projectIds", value: projectIds))
            }

            components.queryItems = queryItems

            var request = URLRequest(url: components.url!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                throw URLError(.badServerResponse)
            }

            let payload = try JSONDecoder().decode(VercelResponse.self, from: data)
            let items = payload.deployments.map { deployment in
                let state = normalizeVercelStatus(deployment.state)
                let createdAt = deployment.createdAt.flatMap(Self.dateFromEpochMillis) ?? .now
                let updatedAt = deployment.readyStateAt.flatMap(Self.dateFromEpochMillis) ?? createdAt
                return DeploymentItem(
                    id: deployment.uid ?? UUID().uuidString,
                    provider: .vercel,
                    project: deployment.name ?? deployment.project?.name ?? "Unnamed project",
                    repo: deployment.name,
                    branch: deployment.meta?.githubCommitRef ?? deployment.meta?.gitlabCommitRef ?? "unknown",
                    commitMessage: deployment.meta?.githubCommitMessage ?? deployment.meta?.githubCommitSubject ?? deployment.name ?? "Untitled deployment",
                    status: state.status,
                    statusLabel: state.status == .building ? "Building..." : state.label,
                    createdAt: createdAt,
                    updatedAt: updatedAt,
                    creator: deployment.creator?.username ?? deployment.creator?.email ?? "Unknown",
                    previewURL: deployment.url.flatMap { URL(string: "https://\($0)") },
                    externalURL: deployment.inspectorUrl.flatMap(URL.init(string:)) ?? deployment.url.flatMap { URL(string: "https://\($0)") },
                    workflowName: nil,
                    failureReason: deployment.meta?.githubCommitMessage == nil && state.status == .error ? "Vercel reported this deployment as failed. Open the deployment in Vercel for detailed logs." : nil
                )
            }

            return ProviderSnapshot(
                kind: .vercel,
                mode: .live,
                notice: "Connected to Vercel.",
                items: items.sorted(by: { $0.updatedAt > $1.updatedAt })
            )
        } catch {
            var fallback = SnapshotFactory.mockSnapshot().providers[.vercel]!
            fallback = ProviderSnapshot(kind: fallback.kind, mode: .mock, notice: "Vercel failed. Showing mock data.", items: fallback.items)
            return fallback
        }
    }

    private func fetchGitHub(env: [String: String]) async -> ProviderSnapshot {
        guard let token = env["GITHUB_TOKEN"], !token.isEmpty else {
            return SnapshotFactory.mockSnapshot().providers[.github]!
        }

        let configuredRepos = env["GITHUB_REPOS", default: ""]
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        do {
            let repos = configuredRepos.isEmpty ? try await fetchAccessibleGitHubRepos(token: token) : configuredRepos
            guard !repos.isEmpty else {
                throw URLError(.resourceUnavailable)
            }

            var items: [DeploymentItem] = []

            for repo in repos {
                let parts = repo.split(separator: "/", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { continue }

                var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(parts[0])/\(parts[1])/actions/runs?per_page=5")!)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                request.setValue("DeplogNative", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                    throw URLError(.badServerResponse)
                }

                let payload = try JSONDecoder().decode(GitHubRunsResponse.self, from: data)
                items += payload.workflowRuns.map { run in
                    let normalized = normalizeGitHubStatus(status: run.status, conclusion: run.conclusion)
                    let createdAt = ISO8601DateFormatter().date(from: run.createdAt ?? "") ?? .now
                    let updatedAt = ISO8601DateFormatter().date(from: run.updatedAt ?? "") ?? createdAt
                    return DeploymentItem(
                        id: String(run.id),
                        provider: .github,
                        project: parts[1],
                        repo: repo,
                        branch: run.headBranch ?? "unknown",
                        commitMessage: run.displayTitle ?? run.name ?? "Workflow run",
                        status: normalized.status,
                        statusLabel: normalized.status == .running ? "Running now" : normalized.label,
                        createdAt: createdAt,
                        updatedAt: updatedAt,
                        creator: run.actor?.login ?? "Unknown",
                        previewURL: nil,
                        externalURL: run.htmlUrl.flatMap(URL.init(string:)),
                        workflowName: run.name,
                        failureReason: normalized.status == .error ? "GitHub marked this workflow run as failed. Open the run on GitHub to inspect the failing step logs." : nil
                    )
                }
            }

            return ProviderSnapshot(
                kind: .github,
                mode: .live,
                notice: configuredRepos.isEmpty ? "Connected to GitHub Actions across all accessible repositories." : "Connected to GitHub Actions.",
                items: items.sorted(by: { $0.updatedAt > $1.updatedAt })
            )
        } catch {
            var fallback = SnapshotFactory.mockSnapshot().providers[.github]!
            fallback = ProviderSnapshot(kind: fallback.kind, mode: .mock, notice: "GitHub failed. Showing mock data.", items: fallback.items)
            return fallback
        }
    }

    private func fetchAccessibleGitHubRepos(token: String) async throws -> [String] {
        var repos: [String] = []

        for page in 1...10 {
            var request = URLRequest(url: URL(string: "https://api.github.com/user/repos?per_page=100&page=\(page)&affiliation=owner,collaborator,organization_member&sort=updated")!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("DeplogNative", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                throw URLError(.badServerResponse)
            }

            let payload = try JSONDecoder().decode([GitHubRepository].self, from: data)
            if payload.isEmpty {
                break
            }

            repos += payload.compactMap(\.fullName)

            if payload.count < 100 {
                break
            }
        }

        return Array(Set(repos)).sorted()
    }

    private static func dateFromEpochMillis(_ value: Double) -> Date {
        Date(timeIntervalSince1970: value / 1000)
    }

    private func normalizeVercelStatus(_ state: String?) -> (status: DeploymentStatus, label: String) {
        switch (state ?? "").uppercased() {
        case "BUILDING": (.building, "Building")
        case "READY": (.ready, "Ready")
        case "ERROR", "CANCELED": (.error, "Failed")
        case "QUEUED", "INITIALIZING": (.queued, "Queued")
        default: (.unknown, "Unknown")
        }
    }

    private func normalizeGitHubStatus(status: String?, conclusion: String?) -> (status: DeploymentStatus, label: String) {
        if status == "in_progress" || status == "queued" {
            return (.running, "Running")
        }
        if conclusion == "success" {
            return (.completed, "Succeeded")
        }
        if ["failure", "cancelled", "timed_out"].contains(conclusion ?? "") {
            return (.error, "Failed")
        }
        return (.unknown, "Unknown")
    }
}

enum Dotenv {
    static func load() -> [String: String] {
        var values = ProcessInfo.processInfo.environment
        let current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let candidateURLs = [
            current.appendingPathComponent(".env"),
            current.deletingLastPathComponent().appendingPathComponent(".env")
        ]

        guard
            let envURL = candidateURLs.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
            let data = try? String(contentsOf: envURL, encoding: .utf8)
        else {
            return values
        }

        for line in data.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), let index = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[..<index]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: index)...]).trimmingCharacters(in: .whitespaces)
            values[key] = value.replacingOccurrences(of: "\"", with: "")
        }

        return values
    }
}

private struct VercelResponse: Decodable {
    let deployments: [VercelDeployment]
}

private struct VercelDeployment: Decodable {
    struct ProjectInfo: Decodable {
        let name: String?
    }

    struct Creator: Decodable {
        let username: String?
        let email: String?
    }

    struct Meta: Decodable {
        let githubCommitRef: String?
        let gitlabCommitRef: String?
        let githubCommitMessage: String?
        let githubCommitSubject: String?
    }

    let uid: String?
    let name: String?
    let state: String?
    let createdAt: Double?
    let readyStateAt: Double?
    let url: String?
    let inspectorUrl: String?
    let project: ProjectInfo?
    let creator: Creator?
    let meta: Meta?
}

private struct GitHubRunsResponse: Decodable {
    let workflowRuns: [GitHubWorkflowRun]

    enum CodingKeys: String, CodingKey {
        case workflowRuns = "workflow_runs"
    }
}

private struct GitHubWorkflowRun: Decodable {
    struct Actor: Decodable {
        let login: String?
    }

    let id: Int
    let name: String?
    let displayTitle: String?
    let status: String?
    let conclusion: String?
    let headBranch: String?
    let createdAt: String?
    let updatedAt: String?
    let htmlUrl: String?
    let actor: Actor?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case displayTitle = "display_title"
        case status
        case conclusion
        case headBranch = "head_branch"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case htmlUrl = "html_url"
        case actor
    }
}

private struct GitHubRepository: Decodable {
    let fullName: String?

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
    }
}
