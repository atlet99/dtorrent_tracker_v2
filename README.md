## About

Dart implementation of a BitTorrent HTTP/HTTPS and UDP tracker/scrape client library.

## Supported Protocols

- [BEP 0003 HTTP/HTTPS Tracker/Scrape](https://www.bittorrent.org/beps/bep_0003.html)
- [BEP 0015 UDP Tracker/Scrape](https://www.bittorrent.org/beps/bep_0015.html)
- [BEP 0007 IPv6 Tracker Extension](https://www.bittorrent.org/beps/bep_0007.html)

## How to use it

### Tracker

To create a `TorrentAnnounceTracker` instance, you need to provide an `AnnounceOptionsProvider`. Since there is no default implementation, you need to implement it manually:
```dart
class SimpleProvider implements AnnounceOptionsProvider {
  SimpleProvider(this.torrent, this.peerId, this.port);
  
  final String peerId;
  final int port;
  final Torrent torrent;
  final int compact = 1;
  final int numwant = 50;

  @override
  Future<Map<String, dynamic>> getOptions(Uri uri, String infoHash) {
    return Future.value({
      'downloaded': 0,
      'uploaded': 0,
      'left': torrent.length,
      'compact': compact, // Must be 1
      'numwant': numwant, // Maximum is 50
      'peerId': peerId,
      'port': port
    });
  }
}
```

Create a `TorrentAnnounceTracker` instance:

```dart
var torrentTracker = TorrentAnnounceTracker(SimpleProvider(torrent, peerId, port));
```

Start tracker with different events:

```dart
torrentTracker.runTracker(url, infoHash, event: 'started');
torrentTracker.runTracker(url, infoHash, event: 'completed');
torrentTracker.runTracker(url, infoHash, event: 'stopped');
```

Listen to tracker events:

```dart
torrentTracker.onAnnounceError((source, error) {
  log('Announce error: $error');
});

torrentTracker.onPeerEvent((source, event) {
  print('${source.announceUrl} peer event: $event');
});

torrentTracker.onAnnounceOver((source, time) {
  print('${source.announceUrl} announce completed in $time seconds');
  source.dispose();
});
```


### Scrape

Create a `TorrentScrapeTracker` instance:

```dart
var scrapeTracker = TorrentScrapeTracker();
```

Add scrape URLs and info hash. The tracker will automatically transform announce URLs to scrape URLs:

```dart
scrapeTracker.addScrapes(torrent.announces, torrent.infoHashBuffer);
```

**Note:** A single `Scrape` instance can handle multiple info hashes. If you call `addScrapes` or `addScrape` with the same URL but different info hash buffers, it will return the same `Scrape` instance, allowing you to scrape multiple torrents in one request.

Get scrape results:

```dart
scrapeTracker.scrape(torrent.infoHashBuffer).listen((event) {
  print(event);
});
```

The `scrape` method takes an info hash buffer as a parameter and returns a `Stream`. Listen to the stream to receive scrape results.