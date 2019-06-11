import Foundation
import AVFoundation

fileprivate extension URL {
    
    func withScheme(_ scheme: String) -> URL? {
        var components = URLComponents(url: self, resolvingAgainstBaseURL: false)
        components?.scheme = scheme
        return components?.url
    }
    
}

@objc protocol CachingPlayerItemDelegate {
    
    /// Is called when the media file is fully downloaded.
    @objc optional func playerItem(_ playerItem: CachingPlayerItem, didFinishDownloadingData data: Data)
    
    /// Is called every time a new portion of data is received.
    @objc optional func playerItem(_ playerItem: CachingPlayerItem, didDownloadBytesSoFar bytesDownloaded: Int, outOf bytesExpected: Int)
    
    /// Is called after initial prebuffering is finished, means
    /// we are ready to play.
    @objc optional func playerItemReadyToPlay(_ playerItem: CachingPlayerItem)
    
    /// Is called when the data being downloaded did not arrive in time to
    /// continue playback.
    @objc optional func playerItemPlaybackStalled(_ playerItem: CachingPlayerItem)
    
    /// Is called on downloading error.
    @objc optional func playerItem(_ playerItem: CachingPlayerItem, downloadingFailedWith error: Error)
    
    /// - BufferMode: disk
    
    /// Invoked every time a new chunk of data is available for caching
    @objc optional func playerItem(_ playerItem: CachingPlayerItem, hasDataAvailableForCaching data: Data, bytesDownloaded: Int, outOf bytesExpected: Int, didCache: (() -> Void)?, didFailCaching: (() -> Void)?)
    
    /// Invoked to request data to be provided to the asset data request
    @objc optional func playerItem(_ playerItem: CachingPlayerItem, needsStreamingData startByte: Int, endByte: Int) -> Data?
    
}

enum BufferMode {
    case memory
    case disk
}

open class CachingPlayerItem: AVPlayerItem {
    
    // Provides the opportunity to avoid loading potentially large amounts of data into memory
    // Requires that the following methods are implemented by the CachingPlayerItemDelegate object
    
    // - playerItem(_ playerItem:hasDataAvailableForCaching:bytesDownloaded:outOf:didCache:didFailCaching:)
    // - playerItem(_ playerItem:needsStreamingData:endByte: Int) -> Data?
    
    // Provide your own implementation of the first method in order to progressively cache the downloading resource to disk
    // Provide your own implementation of the second method in order to read and provide the data requested for streaming directly from the partially cached file
    
    // maxBufferSize is set to 1MB by default (it can be customized) - specifies the largest amount of data to be read from the cached resource and loaded to memory
    class DiskBufferResourceLoaderDelegate: ResourceLoaderDelegate {
        let maxBufferSize: Int
        
        init(maxBufferSize: Int = 1048576) {
            self.maxBufferSize = maxBufferSize
        }
        
        var totalBytesSize: Int = 0
        var bytesDownloadedSoFar: Int = 0
        var bytesCachedSoFar: Int = 0
        
        override func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            totalBytesSize = Int(dataTask.countOfBytesExpectedToReceive)
            super.urlSession(session, dataTask: dataTask, didReceive: response, completionHandler: completionHandler)
        }
        
        override func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            processPendingRequests()
            bytesDownloadedSoFar += data.count
            
            // Every new chunk of data downloaded is made available for caching
            owner?.delegate?.playerItem?(owner!, hasDataAvailableForCaching: data, bytesDownloaded: bytesDownloadedSoFar, outOf: totalBytesSize, didCache: {
                self.bytesCachedSoFar += data.count
            }, didFailCaching: {
                // If there's an error caching the data, we don't have a reliable data source anymore - cancel dataTask
                dataTask.cancel()
            })
            
        }
        
        override func haveEnoughDataToFulfillRequest(_ dataRequest: AVAssetResourceLoadingDataRequest) -> Bool {
            let requestedOffset = Int(dataRequest.requestedOffset)
            let requestedLength = dataRequest.requestedLength
            let currentOffset = Int(dataRequest.currentOffset)
            
            // Is there enough data cached to fulfill the request?
            guard bytesCachedSoFar > currentOffset else { return false }
            
            // The amount of bytes to load in memory and provide to the request is the smallest possible
            // In any case it's never bigger than maxBufferSize
            let bytesToRespond = min(bytesCachedSoFar - currentOffset, requestedLength, maxBufferSize)
            
            let firstByte = currentOffset
            let lastByte = currentOffset + bytesToRespond
            
            // Read data from disk and provide it to the dataRequest
            guard let data = owner?.delegate?.playerItem?(owner!, needsStreamingData: firstByte, endByte: lastByte) else { return false }
            dataRequest.respond(with: data)
            
            return bytesCachedSoFar >= requestedLength + requestedOffset
        }
        
        func didCompleteDownload() -> Bool {
            return (bytesCachedSoFar == bytesDownloadedSoFar) && (bytesCachedSoFar == totalBytesSize)
        }
    }
    
    class ResourceLoaderDelegate: NSObject, AVAssetResourceLoaderDelegate, URLSessionDelegate, URLSessionDataDelegate, URLSessionTaskDelegate {
        
        var playingFromData = false
        var mimeType: String? // is required when playing from Data
        var session: URLSession?
        var mediaData: Data?
        var response: URLResponse?
        var pendingRequests = Set<AVAssetResourceLoadingRequest>()
        weak var owner: CachingPlayerItem?
        
        func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
            
            if playingFromData {
                
                // Nothing to load.
                
            } else if session == nil {
                
                // If we're playing from a url, we need to download the file.
                // We start loading the file on first request only.
                guard let initialUrl = owner?.url else {
                    fatalError("internal inconsistency")
                }

                startDataRequest(with: initialUrl)
            }
            
            pendingRequests.insert(loadingRequest)
            processPendingRequests()
            return true
            
        }
        
        func startDataRequest(with url: URL) {
            let configuration = URLSessionConfiguration.default
            configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            
            session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            var request = URLRequest(url: url)
            
            // some servers may send the wrong Content-Length value for “Content-Encoding: gzip” content
            let headers = ["Accept-Encoding" : "*/*"]
            request.allHTTPHeaderFields = headers
            
            let task = session?.dataTask(with: request)
            task?.resume()
        }
        
        func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
            pendingRequests.remove(loadingRequest)
        }
        
        // MARK: URLSession delegate
        
        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            mediaData?.append(data)
            processPendingRequests()
            owner?.delegate?.playerItem?(owner!, didDownloadBytesSoFar: mediaData!.count, outOf: Int(dataTask.countOfBytesExpectedToReceive))
        }
        
        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            completionHandler(Foundation.URLSession.ResponseDisposition.allow)
            mediaData = Data()
            self.response = response
            processPendingRequests()
        }
        
        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            if let errorUnwrapped = error {
                owner?.delegate?.playerItem?(owner!, downloadingFailedWith: errorUnwrapped)
                return
            }
            processPendingRequests()
            owner?.delegate?.playerItem?(owner!, didFinishDownloadingData: mediaData!)
        }
        
        // MARK: -
        
        func processPendingRequests() {
            
            // get all fullfilled requests
            let requestsFulfilled = Set<AVAssetResourceLoadingRequest>(pendingRequests.compactMap {
                self.fillInContentInformationRequest($0.contentInformationRequest)
                if self.haveEnoughDataToFulfillRequest($0.dataRequest!) {
                    $0.finishLoading()
                    return $0
                }
                return nil
            })
        
            // remove fulfilled requests from pending requests
            _ = requestsFulfilled.map { self.pendingRequests.remove($0) }

        }
        
        func fillInContentInformationRequest(_ contentInformationRequest: AVAssetResourceLoadingContentInformationRequest?) {
            
            // if we play from Data we make no url requests, therefore we have no responses, so we need to fill in contentInformationRequest manually
            if playingFromData {
                contentInformationRequest?.contentType = self.mimeType
                contentInformationRequest?.contentLength = Int64(mediaData!.count)
                contentInformationRequest?.isByteRangeAccessSupported = true
                return
            }
            
            guard let responseUnwrapped = response else {
                // have no response from the server yet
                return
            }
            
            contentInformationRequest?.contentType = responseUnwrapped.mimeType
            contentInformationRequest?.contentLength = responseUnwrapped.expectedContentLength
            contentInformationRequest?.isByteRangeAccessSupported = true
            
        }
        
        func haveEnoughDataToFulfillRequest(_ dataRequest: AVAssetResourceLoadingDataRequest) -> Bool {
            
            let requestedOffset = Int(dataRequest.requestedOffset)
            let requestedLength = dataRequest.requestedLength
            let currentOffset = Int(dataRequest.currentOffset)
            
            guard let songDataUnwrapped = mediaData,
                songDataUnwrapped.count > currentOffset else {
                // Don't have any data at all for this request.
                return false
            }
            
            let bytesToRespond = min(songDataUnwrapped.count - currentOffset, requestedLength)
            let dataToRespond = songDataUnwrapped.subdata(in: Range(uncheckedBounds: (currentOffset, currentOffset + bytesToRespond)))
            dataRequest.respond(with: dataToRespond)
            
            return songDataUnwrapped.count >= requestedLength + requestedOffset
            
        }
        
        deinit {
            session?.invalidateAndCancel()
        }
        
    }
    
    fileprivate let resourceLoaderDelegate: ResourceLoaderDelegate
    fileprivate let url: URL
    fileprivate let initialScheme: String?
    fileprivate var customFileExtension: String?
    fileprivate let bufferMode: BufferMode
    
    weak var delegate: CachingPlayerItemDelegate?
    
    open func download() {
        if resourceLoaderDelegate.session == nil {
            resourceLoaderDelegate.startDataRequest(with: url)
        }
    }
    
    private let cachingPlayerItemScheme = "cachingPlayerItemScheme"
    
    /// Is used for playing remote files.
    convenience init(url: URL) {
        self.init(url: url, customFileExtension: nil)
    }
    
    /// Override/append custom file extension to URL path.
    /// This is required for the player to work correctly with the intended file type.
    init(url: URL, customFileExtension: String?, bufferMode: BufferMode = .memory, maxBufferSize: Int? = nil) {
        
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let scheme = components.scheme,
            var urlWithCustomScheme = url.withScheme(cachingPlayerItemScheme) else {
            fatalError("Urls without a scheme are not supported")
        }
        
        self.url = url
        self.initialScheme = scheme
        self.bufferMode = bufferMode
        
        if let ext = customFileExtension {
            urlWithCustomScheme.deletePathExtension()
            urlWithCustomScheme.appendPathExtension(ext)
            self.customFileExtension = ext
        }
        
        switch bufferMode {
        case .disk:
            if let customBufferSize = maxBufferSize {
                resourceLoaderDelegate = DiskBufferResourceLoaderDelegate(maxBufferSize: customBufferSize)
            } else {
                resourceLoaderDelegate = DiskBufferResourceLoaderDelegate()
            }
        case .memory:
            resourceLoaderDelegate = ResourceLoaderDelegate()
        }
        
        let asset = AVURLAsset(url: urlWithCustomScheme)
        asset.resourceLoader.setDelegate(resourceLoaderDelegate, queue: DispatchQueue.main)
        super.init(asset: asset, automaticallyLoadedAssetKeys: nil)
        
        resourceLoaderDelegate.owner = self
        
        addObserver(self, forKeyPath: "status", options: NSKeyValueObservingOptions.new, context: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(playbackStalledHandler), name:NSNotification.Name.AVPlayerItemPlaybackStalled, object: self)
        
    }
    
    /// Is used for playing from Data.
    init(data: Data, mimeType: String, fileExtension: String) {
        
        guard let fakeUrl = URL(string: cachingPlayerItemScheme + "://whatever/file.\(fileExtension)") else {
            fatalError("internal inconsistency")
        }
        
        self.url = fakeUrl
        self.initialScheme = nil
        self.bufferMode = .memory
        
        resourceLoaderDelegate = ResourceLoaderDelegate()
        
        resourceLoaderDelegate.mediaData = data
        resourceLoaderDelegate.playingFromData = true
        resourceLoaderDelegate.mimeType = mimeType
        
        let asset = AVURLAsset(url: fakeUrl)
        asset.resourceLoader.setDelegate(resourceLoaderDelegate, queue: DispatchQueue.main)
        super.init(asset: asset, automaticallyLoadedAssetKeys: nil)
        resourceLoaderDelegate.owner = self
        
        addObserver(self, forKeyPath: "status", options: NSKeyValueObservingOptions.new, context: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(playbackStalledHandler), name:NSNotification.Name.AVPlayerItemPlaybackStalled, object: self)
        
    }
    
    // MARK: KVO
    
    override open func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        delegate?.playerItemReadyToPlay?(self)
    }
    
    // MARK: Notification hanlers
    
    @objc func playbackStalledHandler() {
        delegate?.playerItemPlaybackStalled?(self)
    }

    // MARK: -
    
    override init(asset: AVAsset, automaticallyLoadedAssetKeys: [String]?) {
        fatalError("not implemented")
    }
    
    deinit {
        // If an item gets deallocated before it was completely downloaded it means the download was cancelled
        // We may want to notify it - e.g. to clear a partially cached file
        if bufferMode == .disk, let resourceDelegate = resourceLoaderDelegate as? DiskBufferResourceLoaderDelegate, !resourceDelegate.didCompleteDownload() {
            let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled, userInfo: nil)
            self.delegate?.playerItem?(self, downloadingFailedWith: error)
        }
        NotificationCenter.default.removeObserver(self)
        removeObserver(self, forKeyPath: "status")
        resourceLoaderDelegate.session?.invalidateAndCancel()
    }
    
}
