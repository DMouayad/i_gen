// test/sync/network_utils_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:i_gen/sync/network_utils.dart';

void main() {
  group('NetworkUtils.isValidIp', () {
    test('returns true for valid IP addresses', () {
      expect(NetworkUtils.isValidIp('192.168.1.1'), isTrue);
      expect(NetworkUtils.isValidIp('10.0.0.1'), isTrue);
      expect(NetworkUtils.isValidIp('172.16.0.1'), isTrue);
      expect(NetworkUtils.isValidIp('0.0.0.0'), isTrue);
      expect(NetworkUtils.isValidIp('255.255.255.255'), isTrue);
    });

    test('returns false for invalid IP addresses', () {
      expect(NetworkUtils.isValidIp(''), isFalse);
      expect(NetworkUtils.isValidIp('192.168.1'), isFalse);
      expect(NetworkUtils.isValidIp('192.168.1.256'), isFalse);
      expect(NetworkUtils.isValidIp('192.168.1.1.1'), isFalse);
      expect(NetworkUtils.isValidIp('192.168.1.-1'), isFalse);
      expect(NetworkUtils.isValidIp('not.an.ip.address'), isFalse);
      expect(NetworkUtils.isValidIp('192.168.1.abc'), isFalse);
    });
  });
}
