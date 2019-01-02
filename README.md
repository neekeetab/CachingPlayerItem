# CachingPlayerItem #
### Stream and cache media content on your iOS device ###

CachingPlayerItem is a subclass of AVPlayerItem. It allows you to play and cache audio and video files without having to download them twice. You can start playing a remote file immediately, without waiting it to be downloaded completely. Once it is downloaded, you will be given an opportunity to store it for future use. 

## Features ##
- Works with both Swift 4 and 3.
- Playing of both local and remote files is supported. You can also play previously cached files as Data objects straight from the memory.
- Convenient notifications through a delegate mechanism.
- CachingPlayerItem is a subclass of AVPlayerItem with a custom loader. So you still have the power of AVFoundation Framework: for most situations you can treat CachingPayerItem as AVPlayerItem.

## Adding to your project ##
Simply add `CachingPlayerItem.swift` to your project.

## Usage ##
Get a url to file you want to play:
```Swift
let url = URL(string: "https://example.com/audio.mp3")!
```
Instantiate CachingPlayerItem:
```Swift
let playerItem = CachingPlayerItem(url: url)
```
Alternatively, you may want to play from a Data object. In this case, use the following initializer:
```Swift
init(data: Data, mimeType: String, fileExtension: String)
```
For mp3 files, the mimeType is "audio/mpeg". Search for other types. 

Instantiate AVPlayer with the playerItem:
```Swift
player = AVPlayer(playerItem: playerItem)
```
Play it:
```Swift
player.play()
```
**Note: you need to keep a strong reference to your player.**

If you want to cache a file without playing it, or to preload it for future playing, use `download()` method:
```Swift
let playerItem = CachingPlayerItem(url: songURL)
playerItem.download()
```
It's fine to start playing the item while it's being downloaded.

**From Apple docs: It's strongly recommended to set AVPlayer's property `automaticallyWaitsToMinimizeStalling` to `false`. Not doing so can lead to poor startup times for playback and poor recovery from stalls.**


Thus, minimal code required to play a remote audio looks like this:

```Swift
import UIKit
import AVFoundation

class ViewController: UIViewController {

    var player: AVPlayer!
    
    override func viewDidLoad() {
        super.viewDidLoad()
     
        let url = URL(string: "https://example.com/file.mp3")!
        let playerItem = CachingPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)
        player.automaticallyWaitsToMinimizeStalling = false
        player.play()
        
    }

}
```

## CachingPlayerItemDelegate protocol ##
Usually, you want to conform to the CachingPlayerItemDelegate protocol. It gives you 5 handy methods to implement:

```Swift
@objc protocol CachingPlayerItemDelegate {
    
    /// Is called when the media file is fully downloaded.
    @objc optional func playerItem(_ playerItem: CachingPlayerItem, didFinishDownloadingData data: Data)
    
    /// Is called every time a new portion of data is received.
    @objc optional func playerItem(_ playerItem: CachingPlayerItem, didDownloadBytesSoFar bytesDownloaded: Int, outOf bytesExpected: Int)
    
    /// Is called after initial prebuffering is finished, means
    /// we are ready to play.
    @objc optional func playerItemReadyToPlay(_ playerItem: CachingPlayerItem)
    
    /// Is called when the data being downloaded did not arrive in time to
    /// continue the playback.
    @objc optional func playerItemPlaybackStalled(_ playerItem: CachingPlayerItem)
    
    /// Is called on downloading error.
    @objc optional func playerItem(_ playerItem: CachingPlayerItem, downloadingFailedWith error: Error)
    
}
```

**Don't forget to set `delegate` property of the playerItem (e.g. to `self`).** Notice, that all of the methods are optional.

## Demo ##
```Swift
import UIKit
import AVFoundation

class ViewController: UIViewController {

    var player: AVPlayer!
    
    override func viewDidLoad() {
        super.viewDidLoad()
     
        let url = URL(string: "http://www.hochmuth.com/mp3/Tchaikovsky_Nocturne__orch.mp3")!
        let playerItem = CachingPlayerItem(url: url)
        playerItem.delegate = self        
        player = AVPlayer(playerItem: playerItem)
        player.automaticallyWaitsToMinimizeStalling = false
        player.play()
        
    }

}

extension ViewController: CachingPlayerItemDelegate {
    
    func playerItem(_ playerItem: CachingPlayerItem, didFinishDownloadingData data: Data) {
        print("File is downloaded and ready for storing")
    }
    
    func playerItem(_ playerItem: CachingPlayerItem, didDownloadBytesSoFar bytesDownloaded: Int, outOf bytesExpected: Int) {
        print("\(bytesDownloaded)/\(bytesExpected)")
    }
    
    func playerItemPlaybackStalled(_ playerItem: CachingPlayerItem) {
        print("Not enough data for playback. Probably because of the poor network. Wait a bit and try to play later.")
    }
    
    func playerItem(_ playerItem: CachingPlayerItem, downloadingFailedWith error: Error) {
        print(error)
    }
    
}
```

## Known limitations ##
- CachingPlayerItem loads its content sequentially. If you seek to yet not downloaded portion, it waits until data previous to this position is downloaded, and only then starts the playback.
- Downloaded data is stored completely in RAM, therefore you're restricted by device's memory. Despite CachingPlayerItem is very handy for relatively small audio files (up to 100MB), you may have memory-related problems with large video files.
- URL's must contain a file extension for the player to load properly. To get around this a custom file extension can be specified e.g. `let playerItem = CachingPlayerItem(url: url, customFileExtension: "mp3")`.
- CachingPlayerItem may not work as expected on simulators. If you experience any issues, try running on a device. 
