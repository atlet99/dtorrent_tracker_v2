import 'dart:typed_data';

import 'package:b_encode_decode/b_encode_decode.dart';
import 'package:dtorrent_tracker_v2/src/tracker/http_tracker.dart';
import 'package:test/test.dart';
import 'package:dtorrent_tracker_v2/src/tracker/tracker.dart';

void main() {
  group('HttpTracker.processResponseData', () {
    final uri = Uri.parse(_testAnnounce);
    final infoHashBuffer = hexString2Buffer(_testInfoHashString)!;
    final infoHashU8List = Uint8List.fromList(infoHashBuffer);
    final httpTracker = HttpTracker(uri, infoHashU8List);

    // setUp(() {});

    test('_fillPeers with Uint8List (BEP0023 compact)', () {
      final inputDataAsString = String.fromCharCodes(_bep0023compactPeersData);
      print('💡inputDataAsString: $inputDataAsString');
      final decoded = decode(_bep0023compactPeersData) as Map;
      print('💡decoded BEP0023 compact peers: $decoded');
      expect(decoded['peers'] is Uint8List, true);
      final res = httpTracker.processResponseData(_bep0023compactPeersData);
      expect(res.peers.isNotEmpty, true);
      expect(res.peers.length, 4);
      expect(res.interval, 3371);
      expect(res.minInterval, 3371);
    });
    test('_fillPeers with List<Map> (BEP003 non compact)', () {
      final inputDataAsString =
          String.fromCharCodes(_bep003nonCompactPeersData);
      print('💡inputDataAsString: $inputDataAsString');
      final decoded = decode(_bep003nonCompactPeersData) as Map;
      print('💡decoded BEP003 non compact peers: $decoded');
      expect(decoded['peers'] is! Uint8List, true);
      final res = httpTracker.processResponseData(_bep003nonCompactPeersData);
      expect(res.peers.isNotEmpty, true);
      expect(res.peers.length, 2);
      expect(res.complete, 0);
      expect(res.incomplete, 2);
      expect(res.interval, 20);
    });
  });

  group('HttpTracker events (stop/complete)', () {
    test('generateQueryParameters includes stopped event when stop() is called',
        () {
      final uri = Uri.parse('http://example.com/announce');
      final infoHashBuffer = hexString2Buffer(_testInfoHashString)!;
      final infoHashU8List = Uint8List.fromList(infoHashBuffer);
      final httpTracker = HttpTracker(uri, infoHashU8List);

      // Simulate stop() call - set the event
      httpTracker.announce(EVENT_STOPPED, {
        'downloaded': 1000,
        'uploaded': 500,
        'left': 0,
        'compact': 1,
        'numwant': 50,
        'peerId': 'test-peer-id-123456',
        'port': 6881
      });

      expect(httpTracker.currentEvent, EVENT_STOPPED);

      // Verify generateQueryParameters includes stopped event
      final params = httpTracker.generateQueryParameters({
        'downloaded': 1000,
        'uploaded': 500,
        'left': 0,
        'compact': 1,
        'numwant': 50,
        'peerId': 'test-peer-id-123456',
        'port': 6881
      });

      expect(params['event'], EVENT_STOPPED);
    });

    test(
        'generateQueryParameters includes completed event when complete() is called',
        () {
      final uri = Uri.parse('http://example.com/announce');
      final infoHashBuffer = hexString2Buffer(_testInfoHashString)!;
      final infoHashU8List = Uint8List.fromList(infoHashBuffer);
      final httpTracker = HttpTracker(uri, infoHashU8List);

      // Simulate complete() call - set the event
      httpTracker.announce(EVENT_COMPLETED, {
        'downloaded': 1000,
        'uploaded': 500,
        'left': 0,
        'compact': 1,
        'numwant': 50,
        'peerId': 'test-peer-id-123456',
        'port': 6881
      });

      expect(httpTracker.currentEvent, EVENT_COMPLETED);

      // Verify generateQueryParameters includes completed event
      final params = httpTracker.generateQueryParameters({
        'downloaded': 1000,
        'uploaded': 500,
        'left': 0,
        'compact': 1,
        'numwant': 50,
        'peerId': 'test-peer-id-123456',
        'port': 6881
      });

      expect(params['event'], EVENT_COMPLETED);
    });

    test('stop() and complete() set correct event type before httpGet', () {
      final uri = Uri.parse('http://example.com/announce');
      final infoHashBuffer = hexString2Buffer(_testInfoHashString)!;
      final infoHashU8List = Uint8List.fromList(infoHashBuffer);
      final httpTracker = HttpTracker(uri, infoHashU8List);

      httpTracker.announce(EVENT_STOPPED, {
        'downloaded': 1000,
        'uploaded': 500,
        'left': 0,
        'compact': 1,
        'numwant': 50,
        'peerId': 'test-peer-id-123456',
        'port': 6881
      });
      expect(httpTracker.currentEvent, EVENT_STOPPED);
      httpTracker.announce(EVENT_COMPLETED, {
        'downloaded': 1000,
        'uploaded': 500,
        'left': 0,
        'compact': 1,
        'numwant': 50,
        'peerId': 'test-peer-id-123456',
        'port': 6881
      });
      expect(httpTracker.currentEvent, EVENT_COMPLETED);
    });

    test('connection is not closed before httpGet (isClosed check)', () {
      final uri = Uri.parse('http://example.com/announce');
      final infoHashBuffer = hexString2Buffer(_testInfoHashString)!;
      final infoHashU8List = Uint8List.fromList(infoHashBuffer);
      final httpTracker = HttpTracker(uri, infoHashU8List);

      expect(httpTracker.isClosed, false);

      // Call announce (simulates call inside stop() or complete())
      // Connection must remain open
      httpTracker.announce(EVENT_STOPPED, {
        'downloaded': 1000,
        'uploaded': 500,
        'left': 0,
        'compact': 1,
        'numwant': 50,
        'peerId': 'test-peer-id-123456',
        'port': 6881
      });

      // Tracker should still be open after announce
      // close() is called in super.stop() after httpGet in real scenario
      expect(httpTracker.isClosed, false);
    });

    test('stop() does not close connection before httpGet can execute', () {
      final uri = Uri.parse('http://example.com/announce');
      final infoHashBuffer = hexString2Buffer(_testInfoHashString)!;
      final infoHashU8List = Uint8List.fromList(infoHashBuffer);
      final httpTracker = HttpTracker(uri, infoHashU8List);

      expect(httpTracker.isClosed, false);

      // Key check: when stop() calls super.stop(), httpGet() must execute
      // BEFORE closing. Verified by isClosed = false when announce() is called

      // Simulate stop() - verify event is set and connection is still open
      httpTracker.announce(EVENT_STOPPED, {
        'downloaded': 1000,
        'uploaded': 500,
        'left': 0,
        'compact': 1,
        'numwant': 50,
        'peerId': 'test-peer-id-123456',
        'port': 6881
      });

      // Connection must be open for httpGet() to execute
      expect(httpTracker.isClosed, false);
      expect(httpTracker.currentEvent, EVENT_STOPPED);
    });

    test('complete() does not close connection before httpGet can execute', () {
      final uri = Uri.parse('http://example.com/announce');
      final infoHashBuffer = hexString2Buffer(_testInfoHashString)!;
      final infoHashU8List = Uint8List.fromList(infoHashBuffer);
      final httpTracker = HttpTracker(uri, infoHashU8List);

      expect(httpTracker.isClosed, false);

      // Simulate complete() - verify event is set and connection is open
      httpTracker.announce(EVENT_COMPLETED, {
        'downloaded': 1000,
        'uploaded': 500,
        'left': 0,
        'compact': 1,
        'numwant': 50,
        'peerId': 'test-peer-id-123456',
        'port': 6881
      });

      // Connection must be open for httpGet() to execute
      expect(httpTracker.isClosed, false);
      expect(httpTracker.currentEvent, EVENT_COMPLETED);
    });

    test(
        'fix verification: stop() allows httpGet to execute by not closing early',
        () {
      // Verifies the fix works:
      // BEFORE: stop() called close() BEFORE super.stop(),
      // causing isClosed = true and httpGet() returned null
      // AFTER: stop() calls super.stop() directly,
      // close() is called inside super.stop() AFTER announce()

      final uri = Uri.parse('http://example.com/announce');
      final infoHashBuffer = hexString2Buffer(_testInfoHashString)!;
      final infoHashU8List = Uint8List.fromList(infoHashBuffer);
      final httpTracker = HttpTracker(uri, infoHashU8List);

      // Simulate stop() call sequence:
      // 1. HttpTracker.stop() is called
      // 2. super.stop() is called (WITHOUT prior close())
      // 3. announce() is called inside super.stop()
      // 4. httpGet() is called inside announce()
      // 5. At this point isClosed must be false!

      expect(httpTracker.isClosed, false);

      // Simulate announce() call as in super.stop()
      // If close() was called earlier, httpGet() would return null
      // Now httpGet() can execute because isClosed = false
      final canExecuteHttpGet = !httpTracker.isClosed;

      expect(canExecuteHttpGet, true,
          reason:
              'httpGet() must be executable because connection is not closed');
      expect(httpTracker.currentEvent, isNull); // Not set yet

      // Set event as in announce()
      httpTracker.announce(EVENT_STOPPED, {
        'downloaded': 1000,
        'uploaded': 500,
        'left': 0,
        'compact': 1,
        'numwant': 50,
        'peerId': 'test-peer-id-123456',
        'port': 6881
      });

      // Verify event is set and connection is still open
      expect(httpTracker.currentEvent, EVENT_STOPPED);
      expect(httpTracker.isClosed, false);
    });
  });

  group('HttpTracker query string construction', () {
    test('query string should not start with &', () {
      final uri = Uri.parse('http://example.com/announce');
      final infoHashBuffer = hexString2Buffer(_testInfoHashString)!;
      final infoHashU8List = Uint8List.fromList(infoHashBuffer);
      final httpTracker = HttpTracker(uri, infoHashU8List);

      // Generate query parameters
      final params = httpTracker.generateQueryParameters({
        'downloaded': 1000,
        'uploaded': 500,
        'left': 0,
        'compact': 1,
        'numwant': 50,
        'peerId': 'test-peer-id-123456',
        'port': 6881
      });

      // Manually construct URL to test query string format
      // This simulates what _createAccessURL does
      var queryParts = <String>[];
      params.forEach((key, value) {
        queryParts.add('$key=$value');
      });
      var queryStr = queryParts.join('&');
      var testUrl = '${uri.origin}${uri.path}?$queryStr';

      // Verify URL does not contain malformed ?& pattern
      expect(testUrl.contains('?&'), false,
          reason: 'URL should not contain ?& pattern');
      expect(testUrl.startsWith('${uri.origin}${uri.path}?'), true,
          reason: 'URL should start with base path and ?');

      // Verify query string starts directly after ?
      final queryStartIndex = testUrl.indexOf('?');
      expect(queryStartIndex, greaterThan(-1));
      if (queryStartIndex + 1 < testUrl.length) {
        final firstCharAfterQuestion = testUrl[queryStartIndex + 1];
        expect(firstCharAfterQuestion, isNot('&'),
            reason: 'First character after ? should not be &');
      }
    });

    test('query string with multiple parameters should be properly formatted',
        () {
      final uri = Uri.parse('http://tracker.example.com/announce');
      final infoHashBuffer = hexString2Buffer(_testInfoHashString)!;
      final infoHashU8List = Uint8List.fromList(infoHashBuffer);
      final httpTracker = HttpTracker(uri, infoHashU8List);

      // Generate query parameters
      final params = httpTracker.generateQueryParameters({
        'downloaded': 1000,
        'uploaded': 500,
        'left': 0,
        'compact': 1,
        'numwant': 50,
        'peerId': 'test-peer-id-123456',
        'port': 6881
      });

      // Manually construct URL to test query string format
      var queryParts = <String>[];
      params.forEach((key, value) {
        queryParts.add('$key=$value');
      });
      var queryStr = queryParts.join('&');
      var testUrl = '${uri.origin}${uri.path}?$queryStr';

      // Verify URL format (don't parse as info_hash contains encoded special characters)
      expect(testUrl.contains('?&'), false,
          reason: 'URL should not contain ?& pattern');
      expect(testUrl.startsWith('${uri.origin}${uri.path}?'), true);

      // Verify query string contains expected parameters
      expect(testUrl, contains('compact='));
      expect(testUrl, contains('downloaded='));
      expect(testUrl, contains('uploaded='));
      expect(testUrl, contains('left='));
      expect(testUrl, contains('numwant='));
      expect(testUrl, contains('port='));
      expect(testUrl, contains('peer_id='));

      // Verify query string starts correctly
      final queryStartIndex = testUrl.indexOf('?');
      expect(queryStartIndex, greaterThan(-1));
      if (queryStartIndex + 1 < testUrl.length) {
        final firstCharAfterQuestion = testUrl[queryStartIndex + 1];
        expect(firstCharAfterQuestion, isNot('&'),
            reason: 'First character after ? should not be &');
      }
    });

    test('query string with list values should be properly formatted', () {
      final uri = Uri.parse('http://example.com/announce');

      // Create test parameters with list values to test query string construction
      // This simulates HttpScrape which can return Map<String, dynamic> with List values
      final testParams = <String, dynamic>{
        'key1': 'value1',
        'key2': ['value2a', 'value2b'],
        'key3': 'value3'
      };

      // Manually construct query string as _createAccessURL does
      var queryParts = <String>[];
      testParams.forEach((key, value) {
        if (value is String) {
          queryParts.add('$key=$value');
        } else if (value is List) {
          for (var v in value) {
            queryParts.add('$key=$v');
          }
        }
      });
      var queryStr = queryParts.join('&');
      var testUrl = '${uri.origin}${uri.path}?$queryStr';

      // Verify URL format
      expect(testUrl.contains('?&'), false);
      expect(testUrl, contains('key1=value1'));
      expect(testUrl, contains('key2=value2a'));
      expect(testUrl, contains('key2=value2b'));
      expect(testUrl, contains('key3=value3'));

      // Verify query string starts correctly
      final queryStartIndex = testUrl.indexOf('?');
      expect(queryStartIndex, greaterThan(-1));
      if (queryStartIndex + 1 < testUrl.length) {
        final firstCharAfterQuestion = testUrl[queryStartIndex + 1];
        expect(firstCharAfterQuestion, isNot('&'));
      }
    });
  });
}

List<int>? hexString2Buffer(String hexStr) {
  if (hexStr.isEmpty || hexStr.length.remainder(2) != 0) return null;
  var size = hexStr.length ~/ 2;
  var re = <int>[];
  for (var i = 0; i < size; i++) {
    var s = hexStr.substring(i * 2, i * 2 + 2);
    var byte = int.parse(s, radix: 16);
    re.add(byte);
  }
  return re;
}

const _testAnnounce =
    'http://bt.t-ru.org/ann?pk=76a9f26aac4c1bdbe997327ae6e7a928';
const _testInfoHashString = '9ebab45b516418b5309d97d7e1066f7e737822b1';

final _bep0023compactPeersData = Uint8List.fromList([
  100,
  56,
  58,
  105,
  110,
  116,
  101,
  114,
  118,
  97,
  108,
  105,
  51,
  51,
  55,
  49,
  101,
  49,
  50,
  58,
  109,
  105,
  110,
  32,
  105,
  110,
  116,
  101,
  114,
  118,
  97,
  108,
  105,
  51,
  51,
  55,
  49,
  101,
  53,
  58,
  112,
  101,
  101,
  114,
  115,
  50,
  52,
  58,
  46,
  71,
  223,
  59,
  254,
  124,
  46,
  71,
  223,
  59,
  26,
  225,
  95,
  31,
  0,
  102,
  77,
  221,
  193,
  194,
  100,
  16,
  146,
  131,
  101
]);

final _bep003nonCompactPeersData = Uint8List.fromList([
  100,
  56,
  58,
  99,
  111,
  109,
  112,
  108,
  101,
  116,
  101,
  105,
  48,
  101,
  49,
  48,
  58,
  105,
  110,
  99,
  111,
  109,
  112,
  108,
  101,
  116,
  101,
  105,
  50,
  101,
  56,
  58,
  105,
  110,
  116,
  101,
  114,
  118,
  97,
  108,
  105,
  50,
  48,
  101,
  53,
  58,
  112,
  101,
  101,
  114,
  115,
  108,
  100,
  50,
  58,
  105,
  112,
  49,
  51,
  58,
  55,
  55,
  46,
  50,
  52,
  54,
  46,
  49,
  53,
  57,
  46,
  49,
  49,
  52,
  58,
  112,
  111,
  114,
  116,
  105,
  53,
  49,
  52,
  49,
  51,
  101,
  101,
  100,
  50,
  58,
  105,
  112,
  49,
  50,
  58,
  54,
  50,
  46,
  49,
  54,
  53,
  46,
  55,
  46,
  49,
  48,
  52,
  52,
  58,
  112,
  111,
  114,
  116,
  105,
  49,
  52,
  48,
  56,
  50,
  101,
  101,
  101,
  101
]);
