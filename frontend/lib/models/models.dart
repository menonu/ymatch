import 'package:json_annotation/json_annotation.dart';

part 'models.g.dart';

@JsonSerializable()
class User {
  final int id;
  final String username;
  final String? uuid;

  User({required this.id, required this.username, this.uuid});

  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);
  Map<String, dynamic> toJson() => _$UserToJson(this);
}

@JsonSerializable()
class EventGroup {
  final int id;
  final String name;
  @JsonKey(name: 'creator_id')
  final int? creatorId;

  EventGroup({required this.id, required this.name, this.creatorId});

  factory EventGroup.fromJson(Map<String, dynamic> json) => _$EventGroupFromJson(json);
  Map<String, dynamic> toJson() => _$EventGroupToJson(this);
}

@JsonSerializable()
class Merchandise {
  final int id;
  @JsonKey(name: 'event_id')
  final int eventId;
  final String name;
  @JsonKey(name: 'photo_url')
  final String? photoUrl;

  Merchandise({
    required this.id,
    required this.eventId,
    required this.name,
    this.photoUrl,
  });

  factory Merchandise.fromJson(Map<String, dynamic> json) => _$MerchandiseFromJson(json);
  Map<String, dynamic> toJson() => _$MerchandiseToJson(this);
}

@JsonSerializable()
class InventoryItem {
  final int id;
  @JsonKey(name: 'user_id')
  final int userId;
  @JsonKey(name: 'merch_id')
  final int merchId;
  final String status;
  final int quantity;
  @JsonKey(name: 'merch_name')
  final String? merchName;
  @JsonKey(name: 'photo_url')
  final String? photoUrl;

  InventoryItem({
    required this.id,
    required this.userId,
    required this.merchId,
    required this.status,
    this.quantity = 1,
    this.merchName,
    this.photoUrl,
  });

  InventoryItem copyWith({
    int? id,
    int? userId,
    int? merchId,
    String? status,
    int? quantity,
    String? merchName,
    String? photoUrl,
  }) {
    return InventoryItem(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      merchId: merchId ?? this.merchId,
      status: status ?? this.status,
      quantity: quantity ?? this.quantity,
      merchName: merchName ?? this.merchName,
      photoUrl: photoUrl ?? this.photoUrl,
    );
  }

  factory InventoryItem.fromJson(Map<String, dynamic> json) => _$InventoryItemFromJson(json);
  Map<String, dynamic> toJson() => _$InventoryItemToJson(this);
}
