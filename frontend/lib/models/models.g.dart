// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

User _$UserFromJson(Map<String, dynamic> json) => User(
  id: (json['id'] as num).toInt(),
  username: json['username'] as String,
  uuid: json['uuid'] as String?,
);

Map<String, dynamic> _$UserToJson(User instance) => <String, dynamic>{
  'id': instance.id,
  'username': instance.username,
  'uuid': instance.uuid,
};

EventGroup _$EventGroupFromJson(Map<String, dynamic> json) => EventGroup(
  id: (json['id'] as num).toInt(),
  name: json['name'] as String,
  creatorId: (json['creator_id'] as num?)?.toInt(),
);

Map<String, dynamic> _$EventGroupToJson(EventGroup instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'creator_id': instance.creatorId,
    };

Merchandise _$MerchandiseFromJson(Map<String, dynamic> json) => Merchandise(
  id: (json['id'] as num).toInt(),
  eventId: (json['event_id'] as num).toInt(),
  name: json['name'] as String,
  photoUrl: json['photo_url'] as String?,
);

Map<String, dynamic> _$MerchandiseToJson(Merchandise instance) =>
    <String, dynamic>{
      'id': instance.id,
      'event_id': instance.eventId,
      'name': instance.name,
      'photo_url': instance.photoUrl,
    };

InventoryItem _$InventoryItemFromJson(Map<String, dynamic> json) =>
    InventoryItem(
      id: (json['id'] as num).toInt(),
      userId: (json['user_id'] as num).toInt(),
      merchId: (json['merch_id'] as num).toInt(),
      status: json['status'] as String,
    );

Map<String, dynamic> _$InventoryItemToJson(InventoryItem instance) =>
    <String, dynamic>{
      'id': instance.id,
      'user_id': instance.userId,
      'merch_id': instance.merchId,
      'status': instance.status,
    };
