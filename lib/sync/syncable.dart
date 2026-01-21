import 'package:uuid/uuid.dart';

mixin Syncable {
  String get uuid;
  int get updatedAt;

  Map<String, dynamic> toSyncJson();
}

/// Helper for generating sync fields
class SyncFields {
  static int now() => DateTime.now().toUtc().millisecondsSinceEpoch;
  static String newUuid() => const Uuid().v4();
}
