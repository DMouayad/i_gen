import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:i_gen/db/db_constants.dart';
import 'package:i_gen/sync/device_identity.dart';
import 'package:i_gen/sync/sync_models.dart';
import 'package:i_gen/sync/sync_repo.dart';
import 'package:i_gen/sync/sync_service.dart';
import 'package:sqflite/sqflite.dart';
import 'dart:convert';

class SyncDebugScreen extends StatefulWidget {
  const SyncDebugScreen({super.key});

  @override
  State<SyncDebugScreen> createState() => _SyncDebugScreenState();
}

class _SyncDebugScreenState extends State<SyncDebugScreen> {
  final List<String> _logs = [];
  bool _isRunning = false;

  Database get _db => GetIt.I.get<Database>();
  SyncRepository get _syncRepo => GetIt.I.get<SyncRepository>();
  SyncService get _syncService => GetIt.I.get<SyncService>();

  void _log(String message) {
    setState(() {
      _logs.add(
        '[${DateTime.now().toIso8601String().substring(11, 19)}] $message',
      );
    });
    debugPrint(message);
  }

  void _clearLogs() {
    setState(() => _logs.clear());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync Debug'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _clearLogs,
            tooltip: 'Clear Logs',
          ),
        ],
      ),
      body: Column(
        children: [
          // Test Buttons
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _TestButton(
                  label: '1. Check Migration',
                  onPressed: _testMigration,
                  isRunning: _isRunning,
                ),
                _TestButton(
                  label: '2. Device Info',
                  onPressed: _testDeviceInfo,
                  isRunning: _isRunning,
                ),
                _TestButton(
                  label: '3. Export Payload',
                  onPressed: _testExport,
                  isRunning: _isRunning,
                ),
                _TestButton(
                  label: '4. Test Tombstones',
                  onPressed: _testTombstones,
                  isRunning: _isRunning,
                ),
                _TestButton(
                  label: '5. Simulate Import',
                  onPressed: _testImport,
                  isRunning: _isRunning,
                ),
                _TestButton(
                  label: '6. Full Sync Test',
                  onPressed: _testFullSync,
                  isRunning: _isRunning,
                ),
                _TestButton(
                  label: '7. Debug Prices',
                  onPressed: _debugPrices,
                  isRunning: _isRunning,
                ),
              ],
            ),
          ),
          const Divider(),
          // Log Output
          Expanded(
            child: Container(
              color: Colors.grey.shade900,
              child: ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: _logs.length,
                itemBuilder: (context, index) {
                  final log = _logs[index];
                  final color = _getLogColor(log);
                  return Text(
                    log,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: color,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Add this method
  Future<void> _debugPrices() => _runTest(() async {
    _log('=== Debugging Prices ===');

    // 1. Show all prices with their timestamps
    final prices = await _db.rawQuery('''
    SELECT 
      prices.*,
      product.model AS product_model,
      product.uuid AS product_uuid,
      price_category.name AS category_name,
      price_category.uuid AS category_uuid
    FROM ${DbConstants.tablePrices} prices
    JOIN ${DbConstants.tableProduct} product 
      ON prices.${DbConstants.columnPricesProductId} = product.${DbConstants.columnId}
    JOIN ${DbConstants.tablePriceCategory} price_category 
      ON prices.${DbConstants.columnPricesPriceCategoryId} = price_category.${DbConstants.columnId}
    ORDER BY prices.updated_at DESC
    LIMIT 20
  ''');

    _log('📦 Recent prices (${prices.length}):');

    for (final p in prices) {
      final updatedAt = p['updated_at'] as int? ?? 0;
      final date = DateTime.fromMillisecondsSinceEpoch(updatedAt);
      _log(
        '   ${p['product_model']} / ${p['category_name']}: '
        'price=${p['price']}, '
        'updated=$date, '
        'uuid=${p['uuid']}',
      );
    }

    // 2. Check sync history
    final history = await _db.query(DbConstants.tableSyncHistory);
    _log('📦 Sync history:');
    for (final h in history) {
      final lastSync = DateTime.fromMillisecondsSinceEpoch(
        h['last_sync_at'] as int,
      );
      _log('   ${h['device_name']}: last_sync=$lastSync');
    }

    // 3. Check what would be exported
    final anchor = history.isNotEmpty
        ? (history.first['last_sync_at'] as int? ?? 0)
        : 0;

    final toExport = await _db.rawQuery(
      '''
    SELECT COUNT(*) as count FROM ${DbConstants.tablePrices}
    WHERE updated_at > ?
  ''',
      [anchor],
    );

    _log('📦 Prices to export (since last sync): ${toExport.first['count']}');

    // 4. Verify UUIDs exist
    final missingUuids = await _db.rawQuery('''
    SELECT COUNT(*) as count FROM ${DbConstants.tablePrices}
    WHERE uuid IS NULL OR uuid = ''
  ''');

    if ((missingUuids.first['count'] as int) > 0) {
      _log('⚠️ Prices missing UUIDs: ${missingUuids.first['count']}');
    } else {
      _log('✅ All prices have UUIDs');
    }

    // 5. Verify updated_at exists
    final missingTimestamps = await _db.rawQuery('''
    SELECT COUNT(*) as count FROM ${DbConstants.tablePrices}
    WHERE updated_at IS NULL OR updated_at = 0
  ''');

    if ((missingTimestamps.first['count'] as int) > 0) {
      _log('⚠️ Prices missing timestamps: ${missingTimestamps.first['count']}');
    } else {
      _log('✅ All prices have timestamps');
    }
  });
  Color _getLogColor(String log) {
    if (log.contains('✅')) return Colors.green;
    if (log.contains('❌')) return Colors.red;
    if (log.contains('⚠️')) return Colors.orange;
    if (log.contains('📦')) return Colors.cyan;
    return Colors.white;
  }

  Future<void> _runTest(Future<void> Function() test) async {
    if (_isRunning) return;
    setState(() => _isRunning = true);
    try {
      await test();
    } catch (e, stack) {
      _log('❌ Error: $e');
      _log(stack.toString().split('\n').take(5).join('\n'));
    } finally {
      setState(() => _isRunning = false);
    }
  }

  // ==================== TEST 1: Migration ====================
  Future<void> _testMigration() => _runTest(() async {
    _log('=== Testing Migration ===');

    final tables = [
      DbConstants.tableProduct,
      DbConstants.tableInvoice,
      DbConstants.tableInvoiceLine,
      DbConstants.tablePriceCategory,
      DbConstants.tablePrices,
    ];

    for (final table in tables) {
      // Check if columns exist
      final info = await _db.rawQuery('PRAGMA table_info($table)');
      final columns = info.map((r) => r['name'] as String).toList();

      final hasUuid = columns.contains('uuid');
      final hasUpdatedAt = columns.contains('updated_at');

      if (hasUuid && hasUpdatedAt) {
        _log('✅ $table: has uuid and updated_at columns');
      } else {
        _log(
          '❌ $table: missing columns (uuid: $hasUuid, updated_at: $hasUpdatedAt)',
        );
        continue;
      }

      // Check if existing records have UUIDs
      // ✅ Fixed: Use single quotes for empty string
      final nullUuids = await _db.rawQuery(
        "SELECT COUNT(*) as count FROM $table WHERE uuid IS NULL OR uuid = ''",
      );
      final nullCount = nullUuids.first['count'] as int;

      final total = await _db.rawQuery('SELECT COUNT(*) as count FROM $table');
      final totalCount = total.first['count'] as int;

      if (nullCount == 0) {
        _log('✅ $table: all $totalCount records have UUIDs');
      } else {
        _log('⚠️ $table: $nullCount of $totalCount records missing UUIDs');
      }
    }

    // Check sync tables exist
    final syncTables = await _db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'sync%'",
    );
    _log('📦 Sync tables: ${syncTables.map((r) => r['name']).join(', ')}');
  });
  // ==================== TEST 2: Device Info ====================
  Future<void> _testDeviceInfo() => _runTest(() async {
    _log('=== Device Info ===');

    final deviceId = await DeviceIdentity.getDeviceId();
    final deviceName = await DeviceIdentity.getDeviceName();
    final info = await _syncService.getDeviceInfo();

    _log('📦 Device ID: $deviceId');
    _log('📦 Device Name: $deviceName');
    _log(
      '📦 Current Time: ${DateTime.fromMillisecondsSinceEpoch(info.currentTime)}',
    );
    _log('📦 Protocol Version: ${info.protocolVersion}');
    _log('✅ Device identity working');
  });

  // ==================== TEST 3: Export ====================
  Future<void> _testExport() => _runTest(() async {
    _log('=== Testing Export ===');

    // Full export (anchor = 0)
    final payload = await _syncService.createFullPayload();

    _log('📦 Products: ${payload.products.length}');
    _log('📦 Invoices: ${payload.invoices.length}');
    _log('📦 Price Categories: ${payload.priceCategories.length}');
    _log('📦 Prices: ${payload.prices.length}');
    _log('📦 Tombstones: ${payload.tombstones.length}');

    // Show sample data
    if (payload.products.isNotEmpty) {
      final sample = payload.products.first;
      _log('📦 Sample Product:');
      _log('   uuid: ${sample['uuid']}');
      _log('   model: ${sample['model']}');
      _log('   updated_at: ${sample['updated_at']}');
    }

    if (payload.invoices.isNotEmpty) {
      final sample = payload.invoices.first;
      _log('📦 Sample Invoice:');
      _log('   uuid: ${sample['uuid']}');
      _log('   customer: ${sample['customer']}');
      _log('   lines: ${(sample['lines'] as List?)?.length ?? 0}');
    }

    // Validate JSON serialization
    try {
      final json = jsonEncode(payload.toJson());
      _log('✅ Payload serializes to JSON (${json.length} bytes)');
    } catch (e) {
      _log('❌ JSON serialization failed: $e');
    }
  });

  // ==================== TEST 4: Tombstones ====================
  Future<void> _testTombstones() => _runTest(() async {
    _log('=== Testing Tombstones ===');

    // Check current tombstones
    final existing = await _db.query(DbConstants.tableSyncTombstones);
    _log('📦 Existing tombstones: ${existing.length}');

    // Record a test tombstone
    final testUuid = 'test-tombstone-${DateTime.now().millisecondsSinceEpoch}';
    await _syncRepo.recordDeletion('test_table', testUuid);
    _log('📦 Recorded test tombstone: $testUuid');

    // Verify it was recorded
    final after = await _db.query(DbConstants.tableSyncTombstones);
    if (after.length == existing.length + 1) {
      _log('✅ Tombstone recorded successfully');
    } else {
      _log('❌ Tombstone not recorded');
    }

    // Clean up test tombstone
    await _db.delete(
      DbConstants.tableSyncTombstones,
      where: 'uuid = ?',
      whereArgs: [testUuid],
    );
    _log('📦 Cleaned up test tombstone');
  });

  // ==================== TEST 5: Import ====================
  Future<void> _testImport() => _runTest(() async {
    _log('=== Testing Import (Simulated) ===');

    // Create a fake payload simulating data from another device
    final fakePayload = SyncPayload(
      sourceDeviceId: 'fake-device-001',
      sourceDeviceName: 'Test Device',
      timestamp: DateTime.now().toUtc().millisecondsSinceEpoch,
      products: [
        {
          'uuid': 'test-product-${DateTime.now().millisecondsSinceEpoch}',
          'model': 'TEST-MODEL-001',
          'name': 'Test Product (Sync Import)',
          'updated_at': DateTime.now().toUtc().millisecondsSinceEpoch,
        },
      ],
      invoices: [],
      priceCategories: [],
      prices: [],
      tombstones: [],
    );

    _log('📦 Simulating import of 1 product...');

    final result = await _syncService.mergePayload(fakePayload);

    _log('📦 Result: $result');

    if (result.inserted == 1) {
      _log('✅ New product inserted');

      // Try importing again - should skip (duplicate)
      final result2 = await _syncService.mergePayload(fakePayload);
      if (result2.skipped == 1) {
        _log('✅ Duplicate correctly skipped');
      } else {
        _log('⚠️ Expected skip, got: $result2');
      }

      // Try with newer timestamp - should update
      fakePayload.products.first['updated_at'] =
          DateTime.now().toUtc().millisecondsSinceEpoch + 1000;
      fakePayload.products.first['name'] = 'Test Product (Updated)';

      final result3 = await _syncService.mergePayload(fakePayload);
      if (result3.updated == 1) {
        _log('✅ Newer version correctly updated');
      } else {
        _log('⚠️ Expected update, got: $result3');
      }
    } else {
      _log('❌ Product not inserted: $result');
    }

    // Clean up
    await _db.delete(
      DbConstants.tableProduct,
      where: 'model = ?',
      whereArgs: ['TEST-MODEL-001'],
    );
    _log('📦 Cleaned up test product');
  });

  // ==================== TEST 6: Full Sync Simulation ====================
  Future<void> _testFullSync() => _runTest(() async {
    _log('=== Full Sync Simulation ===');

    // Step 1: Export current data
    _log('Step 1: Exporting local data...');
    final exportPayload = await _syncService.createFullPayload();
    final exportJson = jsonEncode(exportPayload.toJson());
    _log('📦 Exported ${exportJson.length} bytes');

    // Step 2: Simulate receiving data (parse the JSON back)
    _log('Step 2: Parsing payload...');
    final parsedPayload = SyncPayload.fromJson(jsonDecode(exportJson));
    _log(
      '📦 Parsed: ${parsedPayload.products.length} products, ${parsedPayload.invoices.length} invoices',
    );

    // Step 3: Verify round-trip
    if (parsedPayload.products.length == exportPayload.products.length &&
        parsedPayload.invoices.length == exportPayload.invoices.length) {
      _log('✅ Round-trip serialization successful');
    } else {
      _log('❌ Data mismatch after serialization');
    }

    // Step 4: Check sync history
    final history = await _syncRepo.getSyncHistory();
    _log('📦 Sync history entries: ${history.length}');
    for (final entry in history) {
      final lastSync = DateTime.fromMillisecondsSinceEpoch(
        entry['last_sync_at'] as int,
      );
      _log('   ${entry['device_name']}: last sync $lastSync');
    }

    _log('✅ Full sync simulation complete');
  });
}

class _TestButton extends StatelessWidget {
  const _TestButton({
    required this.label,
    required this.onPressed,
    required this.isRunning,
  });

  final String label;
  final VoidCallback onPressed;
  final bool isRunning;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: isRunning ? null : onPressed,
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}
