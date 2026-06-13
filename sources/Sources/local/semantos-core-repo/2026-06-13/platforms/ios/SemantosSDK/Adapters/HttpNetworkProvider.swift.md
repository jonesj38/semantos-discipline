---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/ios/SemantosSDK/Adapters/HttpNetworkProvider.swift
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.988531+00:00
---

# platforms/ios/SemantosSDK/Adapters/HttpNetworkProvider.swift

```swift
// HttpNetworkProvider.swift — Network operations via URLSession
// Phase 30F: Real HTTP client with configurable endpoint, timeout, and retry.

import Foundation

public final class HttpNetworkProvider: NetworkProvider {

    private let baseURL: URL
    private let session: URLSession
    private let maxRetries: Int
    private let retryDelay: TimeInterval

    /// Initialize the network provider.
    /// - Parameters:
    ///   - baseURL: Base URL of the Semantos network endpoint
    ///   - timeoutInterval: Request timeout in seconds (default: 30)
    ///   - maxRetries: Maximum retry attempts on transient failures (default: 3)
    ///   - retryDelay: Base delay between retries in seconds, with exponential backoff (default: 1.0)
    public init(baseURL: URL,
                timeoutInterval: TimeInterval = 30,
                maxRetries: Int = 3,
                retryDelay: TimeInterval = 1.0) {
        self.baseURL = baseURL
        self.maxRetries = maxRetries
        self.retryDelay = retryDelay

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeoutInterval
        config.timeoutIntervalForResource = timeoutInterval * 2
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)
    }

    // MARK: - NetworkProvider Protocol

    public func publish(objectJSON: UnsafeBufferPointer<UInt8>) -> Int32 {
        let jsonData = Data(objectJSON)

        let semaphore = DispatchSemaphore(value: 0)
        var resultCode: Int32 = -10

        let url = baseURL.appendingPathComponent("publish")
        performRequest(url: url, method: "POST", body: jsonData) { result in
            switch result {
            case .success:
                resultCode = 0
            case .failure:
                resultCode = -10
            }
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + 60)
        return resultCode
    }

    public func resolve(queryJSON: UnsafeBufferPointer<UInt8>,
                        into buffer: UnsafeMutableBufferPointer<UInt8>) -> (Int32, Int) {
        let jsonData = Data(queryJSON)

        let semaphore = DispatchSemaphore(value: 0)
        var resultCode: Int32 = -10
        var responseData = Data()

        let url = baseURL.appendingPathComponent("resolve")
        performRequest(url: url, method: "POST", body: jsonData) { result in
            switch result {
            case .success(let data):
                responseData = data
                resultCode = 0
            case .failure:
                resultCode = -1
            }
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + 60)

        guard resultCode == 0 else { return (resultCode, 0) }

        guard responseData.count <= buffer.count else {
            return (-6, responseData.count) // SEMANTOS_ERR_BUFFER_TOO_SMALL
        }

        responseData.withUnsafeBytes { src in
            if let base = src.baseAddress {
                buffer.baseAddress!.initialize(
                    from: base.assumingMemoryBound(to: UInt8.self),
                    count: responseData.count
                )
            }
        }
        return (0, responseData.count)
    }

    // MARK: - Public Convenience API

    /// Publish a JSON object to the network asynchronously.
    public func publish(json: Data, completion: @escaping (Result<Void, Error>) -> Void) {
        let url = baseURL.appendingPathComponent("publish")
        performRequest(url: url, method: "POST", body: json) { result in
            completion(result.map { _ in () })
        }
    }

    /// Resolve a query against the network asynchronously.
    public func resolve(query: Data, completion: @escaping (Result<Data, Error>) -> Void) {
        let url = baseURL.appendingPathComponent("resolve")
        performRequest(url: url, method: "POST", body: query, completion: completion)
    }

    // MARK: - HTTP Client

    private func performRequest(url: URL, method: String, body: Data?,
                                 attempt: Int = 0,
                                 completion: @escaping (Result<Data, Error>) -> Void) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("SemantosSDK/30F", forHTTPHeaderField: "User-Agent")
        request.httpBody = body

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else {
                completion(.failure(NetworkProviderError.cancelled))
                return
            }

            if let error = error {
                if self.isRetryable(error: error) && attempt < self.maxRetries {
                    let delay = self.retryDelay * pow(2.0, Double(attempt))
                    DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                        self.performRequest(url: url, method: method, body: body,
                                           attempt: attempt + 1, completion: completion)
                    }
                    return
                }
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(NetworkProviderError.invalidResponse))
                return
            }

            // Retry on 5xx server errors
            if httpResponse.statusCode >= 500 && attempt < self.maxRetries {
                let delay = self.retryDelay * pow(2.0, Double(attempt))
                DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                    self.performRequest(url: url, method: method, body: body,
                                       attempt: attempt + 1, completion: completion)
                }
                return
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                completion(.failure(NetworkProviderError.httpError(httpResponse.statusCode)))
                return
            }

            completion(.success(data ?? Data()))
        }
        task.resume()
    }

    private func isRetryable(error: Error) -> Bool {
        let nsError = error as NSError
        let retryableCodes: Set<Int> = [
            NSURLErrorTimedOut,
            NSURLErrorCannotFindHost,
            NSURLErrorCannotConnectToHost,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorNotConnectedToInternet,
        ]
        return retryableCodes.contains(nsError.code)
    }
}

public enum NetworkProviderError: Error, LocalizedError {
    case invalidResponse
    case httpError(Int)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:      return "Invalid HTTP response"
        case .httpError(let code):  return "HTTP error \(code)"
        case .cancelled:            return "Request cancelled"
        }
    }
}

```
