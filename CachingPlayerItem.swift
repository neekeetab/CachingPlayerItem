//
//  CachingPlayerItem.swift
//  AudioStreamer
//
//  Created by Nikita Belousov on 7/9/16.
//  Copyright © 2016 Nikita Belousov. All rights reserved.
//

import AVFoundation

@objc protocol CachingPlayerItemDelegate {
    
    // called when file is fully downloaded
    @objc optional func playerItem(playerItem: CachingPlayerItem, didFinishDownloadingData data: NSData)
    
    // called every time new portion of data is received
    @objc optional func playerItem(playerItem: CachingPlayerItem, didDownloadBytesSoFar bytesDownloaded: Int, outOf bytesExpected: Int)
    
    // called after prebuffering is finished, so player item is ready to play. Called only once, after initial prebuffering
    @objc optional func playerItemReadyToPlay(playerItem: CachingPlayerItem)
    
    // called when some media did not arrive in time to continue playback
    @objc optional func playerItemDidStopPlayback(playerItem: CachingPlayerItem)
    
    // called when deinit
    @objc optional func playerItemWillDeinit(playerItem: CachingPlayerItem)
    
}

extension URL {
    
    func urlWithCustomScheme(scheme: String) -> URL {
        var components = URLComponents(url: self, resolvingAgainstBaseURL: false)
        components?.scheme = scheme
        return components!.url!
    }
    
}

class CachingPlayerItem: AVPlayerItem {
    
    class ResourceLoaderDelegate: NSObject, AVAssetResourceLoaderDelegate, URLSessionDelegate, URLSessionDataDelegate, URLSessionTaskDelegate {
        
        var playingFromCache = false
        var mimeType: String? // is used if we play from cache (with NSData)
        
        var session: URLSession?
        var songData: NSData?
        var response: URLResponse?
        var pendingRequests = Set<AVAssetResourceLoadingRequest>()
        weak var owner: CachingPlayerItem?
        
        //MARK: AVAssetResourceLoader delegate
        
        func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
            
            if playingFromCache { // if we're playing from cache
                // nothing to do here
            } else if session == nil { // if we're playing from url, we need to download the file
                let interceptedURL = loadingRequest.request.url!.urlWithCustomScheme(scheme: owner!.scheme!)
                startDataRequest(withURL: interceptedURL)
            }
            
            pendingRequests.insert(loadingRequest)
            processPendingRequests()
            return true
        }
        
        func startDataRequest(withURL url: URL) {
            let request = URLRequest(url: url)
            let configuration = URLSessionConfiguration.default
            configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            configuration.timeoutIntervalForRequest = 60.0
            configuration.timeoutIntervalForResource = 120.0
            session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            let task = session?.dataTask(with: request)
            task?.resume()
        }
        
        func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
            pendingRequests.remove(loadingRequest)
        }
        
        //MARK: URLSession delegate
        
        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            (songData as! NSMutableData).append(data)
            processPendingRequests()
            owner?.delegate?.playerItem?(playerItem: owner!, didDownloadBytesSoFar: songData!.length, outOf: Int(dataTask.countOfBytesExpectedToReceive))
        }
        
        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            completionHandler(URLSession.ResponseDisposition.allow)
            songData = NSMutableData()
            self.response = response
            processPendingRequests()
        }
        
        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError err: Error?) {
            if let error = err {
                print(error.localizedDescription)
                return
            }
            processPendingRequests()
            owner?.delegate?.playerItem?(playerItem: owner!, didFinishDownloadingData: songData!)
        }
        
        //MARK:
        
        func processPendingRequests() {
            var requestsCompleted = Set<AVAssetResourceLoadingRequest>()
            for loadingRequest in pendingRequests {
                fillInContentInforation(contentInformationRequest: loadingRequest.contentInformationRequest)
                let didRespondCompletely = respondWithDataForRequest(dataRequest: loadingRequest.dataRequest!)
                if didRespondCompletely {
                    requestsCompleted.insert(loadingRequest)
                    loadingRequest.finishLoading()
                }
            }
            for i in requestsCompleted {
                pendingRequests.remove(i)
            }
        }
        
        func fillInContentInforation(contentInformationRequest: AVAssetResourceLoadingContentInformationRequest?) {
            // if we play from cache we make no url requests, therefore we have no responses, so we need to fill in contentInformationRequest manually
            if playingFromCache {
                contentInformationRequest?.contentType = self.mimeType
                contentInformationRequest?.contentLength = Int64(songData!.length)
                contentInformationRequest?.isByteRangeAccessSupported = true
                return
            }
            
            // have no response from the server yet
            if  response == nil {
                return
            }
            
            let mimeType = response?.mimeType
            contentInformationRequest?.contentType = mimeType
            contentInformationRequest?.contentLength = response!.expectedContentLength
            contentInformationRequest?.isByteRangeAccessSupported = true
        }
        
        func respondWithDataForRequest(dataRequest: AVAssetResourceLoadingDataRequest) -> Bool {
            
            let requestedOffset = Int(dataRequest.requestedOffset)
            let requestedLength = dataRequest.requestedLength
            let startOffset = Int(dataRequest.currentOffset)
            
            // Don't have any data at all for this request
            if songData == nil || songData!.length < startOffset {
                return false
            }
            
            // This is the total data we have from startOffset to whatever has been downloaded so far
            let bytesUnread = songData!.length - Int(startOffset)
            
            // Respond fully or whaterver is available if we can't satisfy the request fully yet
            let bytesToRespond = min(bytesUnread, requestedLength + Int(requestedOffset))
            dataRequest.respond(with: songData!.subdata(with: NSMakeRange(startOffset, bytesToRespond)))
            
            let didRespondFully = songData!.length >= requestedLength + Int(requestedOffset)
            return didRespondFully
            
        }
        
        deinit {
            session?.invalidateAndCancel()
        }
        
    }
    
    private var resourceLoaderDelegate = ResourceLoaderDelegate()
    private var scheme: String?
    private var url: URL!
    
    weak var delegate: CachingPlayerItemDelegate?
    
    // use this initializer to play remote files
    init(url: URL) {
        
        self.url = url
        
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        scheme = components.scheme
        
        let asset = AVURLAsset(url: url)
        asset.resourceLoader.setDelegate(resourceLoaderDelegate, queue: DispatchQueue.main)
        super.init(asset: asset, automaticallyLoadedAssetKeys: nil)
        resourceLoaderDelegate.owner = self
        
        self.addObserver(self, forKeyPath: "status", options: NSKeyValueObservingOptions.new, context: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(didStopHandler), name:NSNotification.Name.AVPlayerItemPlaybackStalled, object: self)
        
    }
    
    // use this initializer to play local files
    init(data: NSData, mimeType: String, fileExtension: String) {
        
        self.url = URL(string: "whatever://whatever/file.\(fileExtension)")
        
        resourceLoaderDelegate.songData = data
        resourceLoaderDelegate.playingFromCache = true
        resourceLoaderDelegate.mimeType = mimeType
        
        let asset = AVURLAsset(url: url)
        asset.resourceLoader.setDelegate(resourceLoaderDelegate, queue: DispatchQueue.main)
        
        super.init(asset: asset, automaticallyLoadedAssetKeys: nil)
        resourceLoaderDelegate.owner = self
        
        self.addObserver(self, forKeyPath: "status", options: NSKeyValueObservingOptions.new, context: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(didStopHandler), name:NSNotification.Name.AVPlayerItemPlaybackStalled, object: self)
        
    }
    
    func download() {
        if resourceLoaderDelegate.session == nil {
            resourceLoaderDelegate.startDataRequest(withURL: url)
        }
    }
    
    override init(asset: AVAsset, automaticallyLoadedAssetKeys: [String]?) {
        fatalError("not implemented")
    }
    
    // MARK: KVO
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        delegate?.playerItemReadyToPlay?(playerItem: self)
    }
    
    // MARK: Notification hanlers
    
    func didStopHandler() {
        delegate?.playerItemDidStopPlayback?(playerItem: self)
    }
    
    // MARK:
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        removeObserver(self, forKeyPath: "status")
        resourceLoaderDelegate.session?.invalidateAndCancel()
        delegate?.playerItemWillDeinit?(playerItem: self)
    }
    
}
