# CachingPlayerItem #
### Stream and cache media content on your iOS device ###

CachingPlayerItem is a subclass of AVPlayerItem. It allows you to play and cache media files. You can start to play a remote file immediately, without waiting the file to be downloaded completely. Once it is downloaded, you will be given an opportunity to store it for future use.

## Features ##
- Written in Swift 2.2
- Convenient notifications through a delegate mechanism
- CachingPlayerItem is a subclass of AVPlayerItem, but with a custom loader. So you still have the power of AVFoundation Framework

## Adding to your project ##
Simply add `CachingPlayerItem.swift` to your project

## Usage ##
get a url to file you want to play:
```Swiftf
let songURL = NSURL(string: "https://example.com/audio.mp3")!
```
instantiate CachingPlayerItem:
```Swift
let playerItem = CachingPlayerItem(url: songURL)
```
instantiate player with the playerItem:
```Swift
player = AVPlayer(playerItem: playerItem)
```
play it:
```Swift
player.play()
```
**Note, that you need to keep a strong reference to your player.**

If you want to cache a file without playing it, or to preload it for future playing, use `download()` method:
```Swift
playerItem = CachingPlayerItem(url: songURL)
playerItem.download()
```
It's fine to start playing the item while it's downloading.


So, minimal code required to play a remote audio looks like this:

```Swift
import UIKit
import AVFoundation

class ViewController: UIViewController {

	var player: AVPlayer!

	override func viewDidLoad() {

		super.viewDidLoad()

		let songURL = NSURL(string: "https://example.com/audio.mp3")!
		let playerItem = CachingPlayerItem(url: songURL)
		player = AVPlayer(playerItem: playerItem)
		player.play()

	}

}
```

## CachingPlayerItemDelegate protocol ##
Usually, you want to conform to the CachingPlayerItemDelegate protocol. It gives you 4 handy methods to implement:

```Swift
// called when file is fully dowloaded
optional func playerItem(playerItem: CachingPlayerItem, didFinishLoadingData data: NSData)
    
// called every time new portion of data is received
optional func playerItem(playerItem: CachingPlayerItem, didLoadBytesSoFar bytesLoaded: Int, outOf bytesExpected: Int)
    
// called after prebuffering is finished, so player item is ready to play. Called only once, after initial prebuffering
optional func playerItemReadyToPlay(playerItem: CachingPlayerItem)
    
// called when some media did not arrive in time to continue playback
optional func playerItemDidStopPlayback(playerItem: CachingPlayerItem)
```

**Don't forget to set `delegate` property of the playerItem to `self`.** Notice, that all 4 methods are optional.

## Demo ##
```Swift
import UIKit
import AVFoundation

class ViewController: UIViewController, CachingPlayerItemDelegate {

    var player: AVPlayer!
   
    override func viewDidLoad() {
        super.viewDidLoad()

        let songURL = NSURL(string: "https://example.com/audio.mp3")!
        let playerItem = CachingPlayerItem(url: songURL)
        playerItem.delegate = self        
        player = AVPlayer(playerItem: playerItem)
    }
    
    func playerItemDidStopPlayback(playerItem: CachingPlayerItem) {
        print("Not enough data for playback. Probably because of the poor network. Wait a bit and try to play later.")
    }
    
    func playerItemReadyToPlay(playerItem: CachingPlayerItem) {
        player.play()
    }
    
    func playerItem(playerItem: CachingPlayerItem, didFinishLoadingData data: NSData) {
        print("File is downloaded and ready for storing")
    }
    
    func playerItem(playerItem: CachingPlayerItem, didLoadBytesSoFar bytesLoaded: Int, outOf bytesExpected: Int) {
        print("Loaded so far: \(bytesLoaded) out of \(bytesExpected)")
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

}
```

## Known limitations ##
- CachingPlayerItem loads its content sequentially. If you seek to yet not loaded portion, it waits until data previous to this position is loaded, and only then starts playback.
- Downloaded data is stored completely in RAM, therefore you're restricted by device's memory. Despite CachingPlayerItem is very handy for relatively small audio files (up to 100MB), you may have memory-related problems with large video files.
