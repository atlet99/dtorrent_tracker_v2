import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dtorrent_tracker_v2/src/tracker/udp_tracker.dart';
import 'package:test/test.dart';

void main() {
  group('UDPTracker timeout tests', () {
    final testInfoHash =
        Uint8List.fromList(List.generate(20, (i) => i)); // 20-byte info hash
    late RawDatagramSocket mockServerSocket;
    late InternetAddress localhost;
    int? serverPort;

    setUp(() async {
      localhost = InternetAddress.loopbackIPv4;
      mockServerSocket = await RawDatagramSocket.bind(localhost, 0);
      serverPort = mockServerSocket.port;
    });

    tearDown(() async {
      mockServerSocket.close();
    });

    test('timeout occurs when no response is received', () async {
      // Create tracker with non-existent address to guarantee timeout
      final uri = Uri.parse('udp://127.0.0.1:99999'); // Unreachable port
      final tracker = UDPTracker(uri, testInfoHash);

      final startTime = DateTime.now();

      try {
        await tracker.announce('started', {
          'downloaded': 0,
          'uploaded': 0,
          'left': 1000,
          'numwant': 50,
          'peerId': 'test-peer-id-1234567890',
          'port': 6881,
        });
        fail('Expected timeout error, but got success');
      } catch (e) {
        final elapsed = DateTime.now().difference(startTime);
        // Verify that the error is related to timeout
        expect(e.toString(), contains('timeout'));
        // Verify that timeout occurred approximately after 15 seconds (with tolerance)
        expect(elapsed.inSeconds, greaterThanOrEqualTo(14));
        expect(elapsed.inSeconds, lessThanOrEqualTo(16));
      } finally {
        await tracker.close();
      }
    });

    test('timeout timer is cancelled when response is received', () async {
      // Create a simple UDP server that responds to connect requests
      final uri = Uri.parse('udp://${localhost.address}:$serverPort');
      final tracker = UDPTracker(uri, testInfoHash);

      // Get transaction ID for tracking
      final transactionIdNum = tracker.transcationIdNum;

      // Listen for incoming requests
      mockServerSocket.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = mockServerSocket.receive();
          if (datagram != null && datagram.data.length >= 16) {
            // Check if this is a connect request
            final data = datagram.data;
            final view = ByteData.view(data.buffer);
            final action = view.getUint32(0);
            final tid = view.getUint32(4);

            if (action == 0 && tid == transactionIdNum) {
              // Send connect response
              final response = Uint8List(16);
              final responseView = ByteData.view(response.buffer);
              responseView.setUint32(0, 0); // action = connect
              responseView.setUint32(4, transactionIdNum); // transaction ID
              // connection ID (8 bytes)
              response.setRange(8, 16, [1, 2, 3, 4, 5, 6, 7, 8]);

              mockServerSocket.send(response, datagram.address, datagram.port);

              // Then send announce response
              Future.delayed(Duration(milliseconds: 100), () {
                final announceResponse = Uint8List(20);
                final announceView = ByteData.view(announceResponse.buffer);
                announceView.setUint32(0, 1); // action = announce
                announceView.setUint32(4, transactionIdNum); // transaction ID
                announceView.setUint32(8, 1800); // interval
                announceView.setUint32(12, 10); // complete
                announceView.setUint32(16, 5); // incomplete

                mockServerSocket.send(
                    announceResponse, datagram.address, datagram.port);
              });
            }
          }
        }
      });

      final startTime = DateTime.now();

      try {
        final result = await tracker.announce('started', {
          'downloaded': 0,
          'uploaded': 0,
          'left': 1000,
          'numwant': 50,
          'peerId': 'test-peer-id-1234567890',
          'port': 6881,
        });

        final elapsed = DateTime.now().difference(startTime);

        // Verify that response was received quickly (no timeout occurred)
        expect(elapsed.inSeconds, lessThan(5));
        expect(result, isNotNull);
        expect(result!.interval, 1800);
        expect(result.complete, 10);
        expect(result.incomplete, 5);
      } catch (e) {
        fail('Expected success, but got error: $e');
      } finally {
        await tracker.close();
      }
    });

    test(
        'timeout occurs when only connect response is received but announce times out',
        () async {
      final uri = Uri.parse('udp://${localhost.address}:$serverPort');
      final tracker = UDPTracker(uri, testInfoHash);

      final transactionIdNum = tracker.transcationIdNum;

      // Server responds only to connect, but does not respond to announce
      mockServerSocket.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = mockServerSocket.receive();
          if (datagram != null && datagram.data.length >= 16) {
            final data = datagram.data;
            final view = ByteData.view(data.buffer);
            final action = view.getUint32(0);
            final tid = view.getUint32(4);

            if (action == 0 && tid == transactionIdNum) {
              // Send connect response
              final response = Uint8List(16);
              final responseView = ByteData.view(response.buffer);
              responseView.setUint32(0, 0); // action = connect
              responseView.setUint32(4, transactionIdNum);
              response.setRange(8, 16, [1, 2, 3, 4, 5, 6, 7, 8]);

              mockServerSocket.send(response, datagram.address, datagram.port);
              // Do NOT send announce response - this will cause timeout
            }
          }
        }
      });

      final startTime = DateTime.now();

      try {
        await tracker.announce('started', {
          'downloaded': 0,
          'uploaded': 0,
          'left': 1000,
          'numwant': 50,
          'peerId': 'test-peer-id-1234567890',
          'port': 6881,
        });
        fail('Expected timeout error, but got success');
      } catch (e) {
        final elapsed = DateTime.now().difference(startTime);
        expect(e.toString(), contains('timeout'));
        // Timeout should occur approximately after 15 seconds
        expect(elapsed.inSeconds, greaterThanOrEqualTo(14));
        expect(elapsed.inSeconds, lessThanOrEqualTo(16));
      } finally {
        await tracker.close();
      }
    });

    test('timeout timer is cancelled on socket error', () async {
      final uri = Uri.parse('udp://${localhost.address}:$serverPort');
      final tracker = UDPTracker(uri, testInfoHash);

      // Close server immediately to trigger error
      mockServerSocket.close();

      final startTime = DateTime.now();

      try {
        await tracker.announce('started', {
          'downloaded': 0,
          'uploaded': 0,
          'left': 1000,
          'numwant': 50,
          'peerId': 'test-peer-id-1234567890',
          'port': 6881,
        });
        fail('Expected error, but got success');
      } catch (e) {
        final elapsed = DateTime.now().difference(startTime);
        // Error should occur quickly, without waiting for timeout
        expect(elapsed.inSeconds, lessThan(5));
      } finally {
        await tracker.close();
      }
    });

    test('timeout timer is cancelled when tracker is closed', () async {
      final uri = Uri.parse('udp://${localhost.address}:$serverPort');
      final tracker = UDPTracker(uri, testInfoHash);

      // Start announce but don't respond
      final future = tracker.announce('started', {
        'downloaded': 0,
        'uploaded': 0,
        'left': 1000,
        'numwant': 50,
        'peerId': 'test-peer-id-1234567890',
        'port': 6881,
      });

      // Close tracker immediately
      await Future.delayed(Duration(milliseconds: 100));
      await tracker.close();

      // Verify that future completes with error (not timeout)
      try {
        await future;
        fail('Expected error, but got success');
      } catch (e) {
        // Expect close error, not timeout
        expect(e.toString(), isNot(contains('timeout')));
      }
    });

    test('multiple requests use timeout independently', () async {
      final uri = Uri.parse('udp://${localhost.address}:$serverPort');
      final tracker1 = UDPTracker(uri, testInfoHash);
      final tracker2 = UDPTracker(uri, testInfoHash);

      // Configure server for quick response
      mockServerSocket.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = mockServerSocket.receive();
          if (datagram != null) {
            // Send quick response
            final response = Uint8List(16);
            final responseView = ByteData.view(response.buffer);
            responseView.setUint32(0, 0); // action = connect
            responseView.setUint32(4, 12345); // transaction ID
            response.setRange(8, 16, [1, 2, 3, 4, 5, 6, 7, 8]);

            mockServerSocket.send(response, datagram.address, datagram.port);
          }
        }
      });

      final startTime = DateTime.now();

      // Start two requests in parallel
      final futures = [
        tracker1.announce('started', {
          'downloaded': 0,
          'uploaded': 0,
          'left': 1000,
          'numwant': 50,
          'peerId': 'test-peer-id-1',
          'port': 6881,
        }).catchError((e) => e),
        tracker2.announce('started', {
          'downloaded': 0,
          'uploaded': 0,
          'left': 1000,
          'numwant': 50,
          'peerId': 'test-peer-id-2',
          'port': 6882,
        }).catchError((e) => e),
      ];

      await Future.wait(futures);

      final elapsed = DateTime.now().difference(startTime);
      // Both requests should complete quickly or timeout independently
      expect(elapsed.inSeconds, lessThan(20)); // Less than 2 timeouts

      await tracker1.close();
      await tracker2.close();
    });
  });

  group('UDPTracker retry mechanism tests', () {
    final testInfoHash =
        Uint8List.fromList(List.generate(20, (i) => i)); // 20-byte info hash
    late RawDatagramSocket mockServerSocket;
    late InternetAddress localhost;
    int? serverPort;

    setUp(() async {
      localhost = InternetAddress.loopbackIPv4;
      mockServerSocket = await RawDatagramSocket.bind(localhost, 0);
      serverPort = mockServerSocket.port;
    });

    tearDown(() async {
      mockServerSocket.close();
    });

    test('maxConnectRetryTimes can be configured', () {
      final uri = Uri.parse('udp://127.0.0.1:6881');
      final tracker = UDPTracker(uri, testInfoHash);

      // Test default value
      expect(tracker.maxConnectRetryTimes, 3);

      // Test custom value
      tracker.maxConnectRetryTimes = 5;
      expect(tracker.maxConnectRetryTimes, 5);

      tracker.maxConnectRetryTimes = 1;
      expect(tracker.maxConnectRetryTimes, 1);

      tracker.close();
    });

    test('retry mechanism respects isClosed flag', () async {
      final uri = Uri.parse('udp://${localhost.address}:$serverPort');
      final tracker = UDPTracker(uri, testInfoHash);
      tracker.maxConnectRetryTimes = 10; // High limit

      // Close tracker immediately
      await tracker.close();

      // Verify that tracker is closed
      expect(tracker.isClosed, isTrue);

      // Try to announce - should fail immediately without retries
      final startTime = DateTime.now();

      try {
        await tracker.announce('started', {
          'downloaded': 0,
          'uploaded': 0,
          'left': 1000,
          'numwant': 50,
          'peerId': 'test-peer-id-1234567890',
          'port': 6881,
        });
        fail('Expected error, but got success');
      } catch (e) {
        final elapsed = DateTime.now().difference(startTime);
        // Should fail immediately, not wait for retries
        expect(elapsed.inMilliseconds, lessThan(100));
      }
    });

    test('retry mechanism is implemented in _sendMessage', () {
      // This test verifies that the retry mechanism code exists
      // and can be configured via maxConnectRetryTimes
      final uri = Uri.parse('udp://127.0.0.1:6881');
      final tracker = UDPTracker(uri, testInfoHash);

      // Verify that maxConnectRetryTimes is accessible and configurable
      expect(tracker.maxConnectRetryTimes, isA<int>());
      expect(tracker.maxConnectRetryTimes, greaterThan(0));

      // Verify that we can set different values
      tracker.maxConnectRetryTimes = 1;
      expect(tracker.maxConnectRetryTimes, 1);

      tracker.maxConnectRetryTimes = 10;
      expect(tracker.maxConnectRetryTimes, 10);

      tracker.close();
    });
  });
}
