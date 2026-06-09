import Foundation
import QuillRSCoreShim
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor public protocol DownloadSessionDelegate {
    func downloadSession(_ downloadSession: DownloadSession, conditionalGetInfoFor url: URL) -> HTTPConditionalGetInfo?
    func downloadSession(_ downloadSession: DownloadSession, didReceiveResponse url: URL)
    func downloadSession(_ downloadSession: DownloadSession, didSkip url: URL, reason: String)
    func downloadSession(_ downloadSession: DownloadSession, downloadDidComplete url: URL, response: URLResponse?, data: Data, error: NSError?)
    func downloadSession(_ downloadSession: DownloadSession, shouldContinueAfterReceivingData data: Data, url: URL) -> Bool
    func downloadSession(_ downloadSession: DownloadSession, httpError statusCode: Int, url: URL)
    func downloadSessionDidComplete(_ downloadSession: DownloadSession)
}

@MainActor public final class DownloadSession: ProgressInfoReporter {
    private let delegate: DownloadSessionDelegate
    private let urlSession: URLSession
    private var tasks = [Task<Void, Never>]()
    private var completedCount = 0
    private var totalCount = 0

    public var progressInfo = ProgressInfo() {
        didSet {
            if progressInfo != oldValue {
                postProgressInfoDidChangeNotification()
            }
        }
    }

    public init(delegate: DownloadSessionDelegate) {
        self.delegate = delegate

        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 15
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpMaximumConnectionsPerHost = 1
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        if let headers = UserAgent.headers() {
            configuration.httpAdditionalHeaders = headers
        }
        urlSession = URLSession(configuration: configuration)
    }

    deinit {
        urlSession.invalidateAndCancel()
    }

    public func cancelAll() {
        for task in tasks {
            task.cancel()
        }
        tasks.removeAll()
        progressInfo = ProgressInfo(numberOfTasks: totalCount, numberCompleted: completedCount, numberRemaining: 0)
    }

    public func download(_ urls: Set<URL>) {
        cancelAll()
        completedCount = 0
        totalCount = urls.count
        progressInfo = ProgressInfo(numberOfTasks: totalCount, numberCompleted: 0, numberRemaining: totalCount)

        guard !urls.isEmpty else {
            delegate.downloadSessionDidComplete(self)
            return
        }

        for url in urls {
            tasks.append(Task { [weak self] in
                guard let self else { return }
                await self.downloadOne(url)
            })
        }
    }

    private func downloadOne(_ url: URL) async {
        let request = URLRequest(url: url)

        do {
            let (data, response) = try await urlSession.data(for: request)
            await MainActor.run {
                guard !Task.isCancelled else { return }
                delegate.downloadSession(self, didReceiveResponse: url)
                if let httpResponse = response as? HTTPURLResponse, !httpResponse.statusIsOK {
                    delegate.downloadSession(self, httpError: httpResponse.statusCode, url: url)
                } else if delegate.downloadSession(self, shouldContinueAfterReceivingData: data, url: url) {
                    delegate.downloadSession(self, downloadDidComplete: url, response: response, data: data, error: nil)
                } else {
                    delegate.downloadSession(self, didSkip: url, reason: "Skipped")
                }
                completeOne()
            }
        } catch {
            await MainActor.run {
                guard !Task.isCancelled else { return }
                delegate.downloadSession(self, downloadDidComplete: url, response: nil, data: Data(), error: error as NSError)
                completeOne()
            }
        }
    }

    private func completeOne() {
        completedCount += 1
        let remaining = max(0, totalCount - completedCount)
        progressInfo = ProgressInfo(numberOfTasks: totalCount, numberCompleted: completedCount, numberRemaining: remaining)
        if remaining == 0 {
            delegate.downloadSessionDidComplete(self)
        }
    }
}
