export '../generated/models.pb.dart';

// Extension methods to match the previous API if necessary
// Or just export and let callers use the Protobuf API directly.
extension EventExtensions on Event {
  bool hasUniqueViews() => hasField(5);
  int get uniqueViews => getField(5) as int? ?? 0;
  bool hasActiveParticipants() => hasField(6);
  int get activeParticipants => getField(6) as int? ?? 0;
  bool hasIsFavorite() => hasField(7);
  bool get isFavorite => getField(7) as bool? ?? false;
}

extension MerchandiseExtensions on Merchandise {
  bool hasGroupName() => hasField(5);
  String get groupName => getField(5) as String? ?? '';
}
