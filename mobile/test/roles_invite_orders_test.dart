import 'package:flutter_test/flutter_test.dart';
import 'package:i_gen/auth/auth_service.dart';
import 'package:i_gen/auth/invite_service.dart';
import 'package:i_gen/models/order.dart';

void main() {
  group('UserRole.tryParse', () {
    test('parses the closed role set case-insensitively', () {
      expect(UserRole.tryParse('admin'), UserRole.admin);
      expect(UserRole.tryParse('Employee'), UserRole.employee);
      expect(UserRole.tryParse(' DISTRIBUTOR '), UserRole.distributor);
    });

    test('unknown or missing roles parse to null (unprivileged)', () {
      expect(UserRole.tryParse(null), isNull);
      expect(UserRole.tryParse(''), isNull);
      expect(UserRole.tryParse('owner'), isNull);
    });
  });

  group('InviteService.slugPreview', () {
    test('derives a readable slug from the English name', () {
      expect(InviteService.slugPreview('Mohammad Ahmad'), 'mohammad.ahmad');
      expect(
        InviteService.slugPreview('  Jean-Luc  O\'Brien  '),
        'jean.luc.o.brien',
      );
    });

    test('falls back to user for empty input', () {
      expect(InviteService.slugPreview(''), 'user');
      expect(InviteService.slugPreview('...'), 'user');
    });
  });

  group('InviteResult.fromJson', () {
    test('parses the function contract', () {
      final result = InviteResult.fromJson({
        'fake_email': 'mohammad.ahmad.1234@invited.local',
        'action_link': 'https://example.com/verify?token=abc',
      }, InviteMode.invite);
      expect(result.fakeEmail, 'mohammad.ahmad.1234@invited.local');
      expect(result.actionLink, contains('token=abc'));
      expect(result.mode, InviteMode.invite);
    });
  });

  group('orders view models', () {
    test('Order.fromMap parses a server row', () {
      final order = Order.fromMap({
        'id': 'o1',
        'distributor_id': 'd1',
        'status': 'pending',
        'total': 150,
        'currency': 'USD',
        'created_at': '2026-09-01T10:00:00Z',
      });
      expect(order, isNotNull);
      expect(order!.total, 150.0);
      expect(order.createdAt?.year, 2026);
    });

    test('Order.fromMap rejects malformed rows instead of throwing', () {
      expect(Order.fromMap({'id': 'o1'}), isNull);
    });

    test('OrderItem.fromMap rejects zero-shape rows', () {
      expect(
        OrderItem.fromMap({
          'id': 'i1',
          'order_id': 'o1',
          'amount': 2,
          'price': 25.5,
        })!.price,
        25.5,
      );
      expect(OrderItem.fromMap({'id': 'i1'}), isNull);
    });

    test('Distributor.fromMap parses the narrow directory projection', () {
      final d = Distributor.fromMap({
        'id': 'd1',
        'name_ar': 'موزع',
        'name_en': 'Distributor',
        'phone': '+963000000001',
      });
      expect(d, isNotNull);
      expect(d!.phone, '+963000000001');
      expect(Distributor.fromMap({'id': 'd1', 'phone': 'x'}), isNull);
    });
  });
}
