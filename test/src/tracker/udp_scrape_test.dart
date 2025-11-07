import 'dart:io';
import 'dart:typed_data';

import 'package:dtorrent_common/dtorrent_common.dart';
import 'package:dtorrent_tracker_v2/src/tracker/udp_scrape.dart';
import 'package:test/test.dart';

void main() {
  group('UDPScrape length validation tests', () {
    final testInfoHash1 =
        Uint8List.fromList(List.generate(20, (i) => i)); // 20-byte info hash
    final testInfoHash2 = Uint8List.fromList(
        List.generate(20, (i) => i + 20)); // Another 20-byte info hash
    late UDPScrape scraper;
    late InternetAddress localhost;

    setUp(() {
      localhost = InternetAddress.loopbackIPv4;
      final uri = Uri.parse('udp://${localhost.address}:6881');
      scraper = UDPScrape(uri);
    });

    tearDown(() {
      scraper.close();
    });

    test('processResponseData validates minimum length for single info_hash',
        () {
      scraper.addInfoHash(testInfoHash1);

      // Create valid response: 8 bytes header + 12 bytes for one info_hash = 20 bytes
      final validResponse = Uint8List(20);
      final view = ByteData.view(validResponse.buffer);
      view.setUint32(0, 2); // action = scrape
      view.setUint32(4, 12345); // transaction ID
      view.setUint32(8, 100); // complete
      view.setUint32(12, 50); // downloaded
      view.setUint32(16, 25); // incomplete

      final result = scraper.processResponseData(
          validResponse, 2, [CompactAddress(localhost, 6881)]);
      expect(result, isNotNull);
      expect(result.files.length, 1);
    });

    test('processResponseData throws exception when data is too short', () {
      scraper.addInfoHash(testInfoHash1);

      // Create response with only 8 bytes (header only, missing scrape data)
      final shortResponse = Uint8List(8);
      final view = ByteData.view(shortResponse.buffer);
      view.setUint32(0, 2); // action = scrape
      view.setUint32(4, 12345); // transaction ID

      expect(
        () => scraper.processResponseData(
            shortResponse, 2, [CompactAddress(localhost, 6881)]),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('Invalid scrape response length'),
        )),
      );
    });

    test(
        'processResponseData throws exception when data is truncated mid-entry',
        () {
      scraper.addInfoHash(testInfoHash1);

      // Create response with 8 bytes header + 8 bytes (missing 4 bytes for incomplete)
      final truncatedResponse = Uint8List(16);
      final view = ByteData.view(truncatedResponse.buffer);
      view.setUint32(0, 2); // action = scrape
      view.setUint32(4, 12345); // transaction ID
      view.setUint32(8, 100); // complete
      view.setUint32(12, 50); // downloaded
      // incomplete is missing

      expect(
        () => scraper.processResponseData(
            truncatedResponse, 2, [CompactAddress(localhost, 6881)]),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('Invalid scrape response length'),
        )),
      );
    });

    test('processResponseData validates length for multiple info_hashes', () {
      scraper.addInfoHash(testInfoHash1);
      scraper.addInfoHash(testInfoHash2);

      // Create valid response: 8 bytes header + 12 bytes × 2 = 32 bytes
      final validResponse = Uint8List(32);
      final view = ByteData.view(validResponse.buffer);
      view.setUint32(0, 2); // action = scrape
      view.setUint32(4, 12345); // transaction ID
      // First info_hash data
      view.setUint32(8, 100); // complete
      view.setUint32(12, 50); // downloaded
      view.setUint32(16, 25); // incomplete
      // Second info_hash data
      view.setUint32(20, 200); // complete
      view.setUint32(24, 100); // downloaded
      view.setUint32(28, 50); // incomplete

      final result = scraper.processResponseData(
          validResponse, 2, [CompactAddress(localhost, 6881)]);
      expect(result, isNotNull);
      expect(result.files.length, 2);
    });

    test(
        'processResponseData throws exception when insufficient data for multiple info_hashes',
        () {
      scraper.addInfoHash(testInfoHash1);
      scraper.addInfoHash(testInfoHash2);

      // Create response with only 20 bytes (enough for one info_hash, but not two)
      final insufficientResponse = Uint8List(20);
      final view = ByteData.view(insufficientResponse.buffer);
      view.setUint32(0, 2); // action = scrape
      view.setUint32(4, 12345); // transaction ID
      view.setUint32(8, 100); // complete
      view.setUint32(12, 50); // downloaded
      view.setUint32(16, 25); // incomplete

      expect(
        () => scraper.processResponseData(
            insufficientResponse, 2, [CompactAddress(localhost, 6881)]),
        throwsA(isA<Exception>()
            .having(
              (e) => e.toString(),
              'message',
              contains('Invalid scrape response length'),
            )
            .having(
              (e) => e.toString(),
              'message',
              contains('expected at least 32 bytes'),
            )),
      );
    });

    test('processResponseData handles extra data gracefully', () {
      scraper.addInfoHash(testInfoHash1);

      // Create response with extra data beyond what's needed
      final extraDataResponse = Uint8List(30);
      final view = ByteData.view(extraDataResponse.buffer);
      view.setUint32(0, 2); // action = scrape
      view.setUint32(4, 12345); // transaction ID
      view.setUint32(8, 100); // complete
      view.setUint32(12, 50); // downloaded
      view.setUint32(16, 25); // incomplete
      // Extra 10 bytes that should be ignored

      final result = scraper.processResponseData(
          extraDataResponse, 2, [CompactAddress(localhost, 6881)]);
      expect(result, isNotNull);
      expect(result.files.length, 1);
    });

    test('processResponseData throws exception when action does not match', () {
      scraper.addInfoHash(testInfoHash1);

      final response = Uint8List(20);
      final view = ByteData.view(response.buffer);
      view.setUint32(0, 1); // Wrong action (announce instead of scrape)
      view.setUint32(4, 12345); // transaction ID

      expect(
        () => scraper.processResponseData(
            response, 1, [CompactAddress(localhost, 6881)]),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('The Action in the returned data does not match'),
        )),
      );
    });

    test('processResponseData validates bounds during parsing', () {
      scraper.addInfoHash(testInfoHash1);

      // Create response that passes initial length check but fails during parsing
      // This shouldn't happen with proper validation, but we test it anyway
      final response = Uint8List(19); // Just 1 byte short
      final view = ByteData.view(response.buffer);
      view.setUint32(0, 2); // action = scrape
      view.setUint32(4, 12345); // transaction ID
      view.setUint32(8, 100); // complete
      view.setUint32(12, 50); // downloaded
      // incomplete is partially missing (only 3 bytes available)

      expect(
        () => scraper.processResponseData(
            response, 2, [CompactAddress(localhost, 6881)]),
        throwsA(isA<Exception>()),
      );
    });
  });
}
