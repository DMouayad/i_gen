// lib/sync/sync_models.dart

class SyncPayload {
  final String sourceDeviceId;
  final String sourceDeviceName;
  final int timestamp;
  final List<Map<String, dynamic>> products;
  final List<Map<String, dynamic>> invoices;
  final List<Map<String, dynamic>> priceCategories;
  final List<Map<String, dynamic>> prices;
  final List<Tombstone> tombstones;

  const SyncPayload({
    required this.sourceDeviceId,
    required this.sourceDeviceName,
    required this.timestamp,
    this.products = const [],
    this.invoices = const [],
    this.priceCategories = const [],
    this.prices = const [],
    this.tombstones = const [],
  });

  Map<String, dynamic> toJson() => {
    'source_device_id': sourceDeviceId,
    'source_device_name': sourceDeviceName,
    'timestamp': timestamp,
    'products': products,
    'invoices': invoices,
    'price_categories': priceCategories,
    'prices': prices,
    'tombstones': tombstones.map((t) => t.toJson()).toList(),
  };

  factory SyncPayload.fromJson(Map<String, dynamic> json) {
    return SyncPayload(
      sourceDeviceId: json['source_device_id'] as String,
      sourceDeviceName: json['source_device_name'] as String? ?? 'Unknown',
      timestamp: json['timestamp'] as int,
      products: List<Map<String, dynamic>>.from(json['products'] ?? []),
      invoices: List<Map<String, dynamic>>.from(json['invoices'] ?? []),
      priceCategories: List<Map<String, dynamic>>.from(
        json['price_categories'] ?? [],
      ),
      prices: List<Map<String, dynamic>>.from(json['prices'] ?? []),
      tombstones:
          (json['tombstones'] as List<dynamic>?)
              ?.map((t) => Tombstone.fromJson(t as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class Tombstone {
  final String tableName;
  final String uuid;
  final int deletedAt;

  const Tombstone({
    required this.tableName,
    required this.uuid,
    required this.deletedAt,
  });

  Map<String, dynamic> toJson() => {
    'table_name': tableName,
    'uuid': uuid,
    'deleted_at': deletedAt,
  };

  factory Tombstone.fromJson(Map<String, dynamic> json) {
    return Tombstone(
      tableName: json['table_name'] as String,
      uuid: json['uuid'] as String,
      deletedAt: json['deleted_at'] as int,
    );
  }
}

class SyncResult {
  final int inserted;
  final int updated;
  final int deleted;
  final int skipped;
  final List<String> errors;

  const SyncResult({
    this.inserted = 0,
    this.updated = 0,
    this.deleted = 0,
    this.skipped = 0,
    this.errors = const [],
  });

  SyncResult operator +(SyncResult other) {
    return SyncResult(
      inserted: inserted + other.inserted,
      updated: updated + other.updated,
      deleted: deleted + other.deleted,
      skipped: skipped + other.skipped,
      errors: [...errors, ...other.errors],
    );
  }

  @override
  String toString() =>
      'Inserted: $inserted, Updated: $updated, Deleted: $deleted, Skipped: $skipped';
}

class DeviceInfo {
  final String deviceId;
  final String deviceName;
  final int currentTime;
  final int protocolVersion;

  const DeviceInfo({
    required this.deviceId,
    required this.deviceName,
    required this.currentTime,
    this.protocolVersion = 1,
  });

  Map<String, dynamic> toJson() => {
    'device_id': deviceId,
    'device_name': deviceName,
    'current_time': currentTime,
    'protocol_version': protocolVersion,
  };

  factory DeviceInfo.fromJson(Map<String, dynamic> json) {
    return DeviceInfo(
      deviceId: json['device_id'] as String,
      deviceName: json['device_name'] as String? ?? 'Unknown',
      currentTime: json['current_time'] as int,
      protocolVersion: json['protocol_version'] as int? ?? 1,
    );
  }
}
