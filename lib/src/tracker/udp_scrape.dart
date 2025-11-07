import 'dart:io';
import 'dart:typed_data';

import 'package:dtorrent_common/dtorrent_common.dart';
import 'package:logging/logging.dart';

import 'scrape_event.dart';
import 'udp_tracker_base.dart';
import 'scrape.dart';

var _log = Logger('UDPScrape');

/// Take a look : [UDP Scrape Specification](http://xbtt.sourceforge.net/udp_tracker_protocol.html)
class UDPScrape extends Scrape with UDPTrackerBase {
  UDPScrape(Uri uri) : super('${uri.host}:${uri.port}', uri);

  @override
  Future scrape(Map options) {
    return contactAnnouncer(options);
  }

  /// When scraping, the data sent to the remote includes:
  /// - Connection ID: This is returned by Remote after the first connection and
  /// is passed as a parameter.
  /// - Action: Here, it is 2, which means "Scrape."
  /// - Transaction ID: It was generated during the first connection.
  /// - [info hash]: This can be the info hash of multiple Torrent files.
  @override
  Uint8List generateSecondTouchMessage(Uint8List connectionId, Map options) {
    var list = <int>[];
    list.addAll(connectionId);
    list.addAll(
        ACTION_SCRAPE); // The type of Action is currently 'scrap,' which is represented as 2.
    list.addAll(transcationId!); // Session ID.
    var infos = infoHashSet;
    if (infos.isEmpty) throw Exception('Infohash cannot be empty.');
    for (var info in infos) {
      list.addAll(info);
    }
    return Uint8List.fromList(list);
  }

  ///
  /// Process the scrape information returned from the remote.
  /// The information consists of a set of data consisting of "complete",
  /// "downloaded" and "incomplete."
  ///
  @override
  dynamic processResponseData(
      Uint8List data, int action, Iterable<CompactAddress> addresses) {
    var event = ScrapeEvent(scrapeUrl);

    if (action != 2) {
      throw Exception('The Action in the returned data does not match.');
    }

    // Validate minimum length: 8 bytes (Action + Transaction ID) + 12 bytes per info_hash
    var expectedLength = 8 + (infoHashSet.length * 12);
    if (data.length < expectedLength) {
      throw Exception(
        'Invalid scrape response length: expected at least $expectedLength bytes '
        '(8 bytes header + 12 bytes × ${infoHashSet.length} info_hashes), '
        'got ${data.length} bytes',
      );
    }

    var view = ByteData.view(data.buffer);
    var i = 0;

    try {
      for (var index = 8; index < expectedLength; index += 12, i++) {
        // Additional bounds check for safety
        if (index + 12 > data.length) {
          throw Exception(
            'Insufficient data at index $index: need 12 bytes, '
            'only ${data.length - index} bytes remaining',
          );
        }

        if (i >= infoHashSet.length) {
          _log.warning(
            'Received more scrape entries (${i + 1}) than requested '
            '(${infoHashSet.length}), ignoring extra entries',
          );
          break;
        }

        var file = ScrapeResult(
            transformBufferToHexString(infoHashSet.elementAt(i)),
            complete: view.getUint32(index),
            downloaded: view.getUint32(index + 4),
            incomplete: view.getUint32(index + 8));
        event.addFile(file.infoHash, file);
      }
    } catch (e) {
      if (e is Exception && e.toString().contains('Index')) {
        throw Exception(
          'Failed to parse scrape response: $e. '
          'Data length: ${data.length}, Expected: $expectedLength',
        );
      }
      rethrow;
    }

    return event;
  }

  @override
  void handleSocketDone() async {
    await close();
  }

  @override
  void handleSocketError(e) {
    close();
  }

  @override
  Future<List<CompactAddress>?> get addresses async {
    try {
      var ips = await InternetAddress.lookup(scrapeUrl.host);
      var l = <CompactAddress>[];
      for (var element in ips) {
        try {
          l.add(CompactAddress(element, scrapeUrl.port));
        } catch (e) {
          //
        }
      }
      return l;
    } catch (e) {
      return null;
    }
  }
}
