// This is a generated file - do not edit.
//
// Generated from models.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

/// Core Models
class User extends $pb.GeneratedMessage {
  factory User({
    $core.int? id,
    $core.String? username,
    $core.String? uuid,
    $core.String? deviceToken,
    $core.String? createdAt,
    $core.String? role,
    $core.bool? isBanned,
    $core.String? banReason,
    $core.String? bannedUntil,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (username != null) result.username = username;
    if (uuid != null) result.uuid = uuid;
    if (deviceToken != null) result.deviceToken = deviceToken;
    if (createdAt != null) result.createdAt = createdAt;
    if (role != null) result.role = role;
    if (isBanned != null) result.isBanned = isBanned;
    if (banReason != null) result.banReason = banReason;
    if (bannedUntil != null) result.bannedUntil = bannedUntil;
    return result;
  }

  User._();

  factory User.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory User.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'User',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ymatch'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'username')
    ..aOS(3, _omitFieldNames ? '' : 'uuid')
    ..aOS(4, _omitFieldNames ? '' : 'deviceToken')
    ..aOS(5, _omitFieldNames ? '' : 'createdAt')
    ..aOS(6, _omitFieldNames ? '' : 'role')
    ..aOB(7, _omitFieldNames ? '' : 'isBanned')
    ..aOS(8, _omitFieldNames ? '' : 'banReason')
    ..aOS(9, _omitFieldNames ? '' : 'bannedUntil')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  User clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  User copyWith(void Function(User) updates) =>
      super.copyWith((message) => updates(message as User)) as User;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static User create() => User._();
  @$core.override
  User createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static User getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<User>(create);
  static User? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get id => $_getIZ(0);
  @$pb.TagNumber(1)
  set id($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get username => $_getSZ(1);
  @$pb.TagNumber(2)
  set username($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasUsername() => $_has(1);
  @$pb.TagNumber(2)
  void clearUsername() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get uuid => $_getSZ(2);
  @$pb.TagNumber(3)
  set uuid($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasUuid() => $_has(2);
  @$pb.TagNumber(3)
  void clearUuid() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get deviceToken => $_getSZ(3);
  @$pb.TagNumber(4)
  set deviceToken($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasDeviceToken() => $_has(3);
  @$pb.TagNumber(4)
  void clearDeviceToken() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get createdAt => $_getSZ(4);
  @$pb.TagNumber(5)
  set createdAt($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasCreatedAt() => $_has(4);
  @$pb.TagNumber(5)
  void clearCreatedAt() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get role => $_getSZ(5);
  @$pb.TagNumber(6)
  set role($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasRole() => $_has(5);
  @$pb.TagNumber(6)
  void clearRole() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.bool get isBanned => $_getBF(6);
  @$pb.TagNumber(7)
  set isBanned($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(7)
  $core.bool hasIsBanned() => $_has(6);
  @$pb.TagNumber(7)
  void clearIsBanned() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.String get banReason => $_getSZ(7);
  @$pb.TagNumber(8)
  set banReason($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasBanReason() => $_has(7);
  @$pb.TagNumber(8)
  void clearBanReason() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.String get bannedUntil => $_getSZ(8);
  @$pb.TagNumber(9)
  set bannedUntil($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasBannedUntil() => $_has(8);
  @$pb.TagNumber(9)
  void clearBannedUntil() => $_clearField(9);
}

class Event extends $pb.GeneratedMessage {
  factory Event({
    $core.int? id,
    $core.String? name,
    $core.int? creatorId,
    $core.String? createdAt,
    $core.int? uniqueViews,
    $core.int? activeParticipants,
    $core.bool? isFavorite,
    $core.bool? isJoined,
    $core.String? status,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (name != null) result.name = name;
    if (creatorId != null) result.creatorId = creatorId;
    if (createdAt != null) result.createdAt = createdAt;
    if (uniqueViews != null) result.uniqueViews = uniqueViews;
    if (activeParticipants != null)
      result.activeParticipants = activeParticipants;
    if (isFavorite != null) result.isFavorite = isFavorite;
    if (isJoined != null) result.isJoined = isJoined;
    if (status != null) result.status = status;
    return result;
  }

  Event._();

  factory Event.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Event.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Event',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ymatch'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..aI(3, _omitFieldNames ? '' : 'creatorId')
    ..aOS(4, _omitFieldNames ? '' : 'createdAt')
    ..aI(5, _omitFieldNames ? '' : 'uniqueViews')
    ..aI(6, _omitFieldNames ? '' : 'activeParticipants')
    ..aOB(7, _omitFieldNames ? '' : 'isFavorite')
    ..aOB(8, _omitFieldNames ? '' : 'isJoined')
    ..aOS(9, _omitFieldNames ? '' : 'status')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Event clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Event copyWith(void Function(Event) updates) =>
      super.copyWith((message) => updates(message as Event)) as Event;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Event create() => Event._();
  @$core.override
  Event createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Event getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Event>(create);
  static Event? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get id => $_getIZ(0);
  @$pb.TagNumber(1)
  set id($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get creatorId => $_getIZ(2);
  @$pb.TagNumber(3)
  set creatorId($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasCreatorId() => $_has(2);
  @$pb.TagNumber(3)
  void clearCreatorId() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get createdAt => $_getSZ(3);
  @$pb.TagNumber(4)
  set createdAt($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasCreatedAt() => $_has(3);
  @$pb.TagNumber(4)
  void clearCreatedAt() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get uniqueViews => $_getIZ(4);
  @$pb.TagNumber(5)
  set uniqueViews($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasUniqueViews() => $_has(4);
  @$pb.TagNumber(5)
  void clearUniqueViews() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get activeParticipants => $_getIZ(5);
  @$pb.TagNumber(6)
  set activeParticipants($core.int value) => $_setSignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasActiveParticipants() => $_has(5);
  @$pb.TagNumber(6)
  void clearActiveParticipants() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.bool get isFavorite => $_getBF(6);
  @$pb.TagNumber(7)
  set isFavorite($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(7)
  $core.bool hasIsFavorite() => $_has(6);
  @$pb.TagNumber(7)
  void clearIsFavorite() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.bool get isJoined => $_getBF(7);
  @$pb.TagNumber(8)
  set isJoined($core.bool value) => $_setBool(7, value);
  @$pb.TagNumber(8)
  $core.bool hasIsJoined() => $_has(7);
  @$pb.TagNumber(8)
  void clearIsJoined() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.String get status => $_getSZ(8);
  @$pb.TagNumber(9)
  set status($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasStatus() => $_has(8);
  @$pb.TagNumber(9)
  void clearStatus() => $_clearField(9);
}

class FavoriteGroup extends $pb.GeneratedMessage {
  factory FavoriteGroup({
    $core.int? userId,
    $core.int? eventId,
    $core.String? groupName,
    $core.String? eventName,
  }) {
    final result = create();
    if (userId != null) result.userId = userId;
    if (eventId != null) result.eventId = eventId;
    if (groupName != null) result.groupName = groupName;
    if (eventName != null) result.eventName = eventName;
    return result;
  }

  FavoriteGroup._();

  factory FavoriteGroup.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory FavoriteGroup.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FavoriteGroup',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ymatch'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'userId')
    ..aI(2, _omitFieldNames ? '' : 'eventId')
    ..aOS(3, _omitFieldNames ? '' : 'groupName')
    ..aOS(4, _omitFieldNames ? '' : 'eventName')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FavoriteGroup clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FavoriteGroup copyWith(void Function(FavoriteGroup) updates) =>
      super.copyWith((message) => updates(message as FavoriteGroup))
          as FavoriteGroup;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FavoriteGroup create() => FavoriteGroup._();
  @$core.override
  FavoriteGroup createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static FavoriteGroup getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FavoriteGroup>(create);
  static FavoriteGroup? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get userId => $_getIZ(0);
  @$pb.TagNumber(1)
  set userId($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasUserId() => $_has(0);
  @$pb.TagNumber(1)
  void clearUserId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get eventId => $_getIZ(1);
  @$pb.TagNumber(2)
  set eventId($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasEventId() => $_has(1);
  @$pb.TagNumber(2)
  void clearEventId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get groupName => $_getSZ(2);
  @$pb.TagNumber(3)
  set groupName($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasGroupName() => $_has(2);
  @$pb.TagNumber(3)
  void clearGroupName() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get eventName => $_getSZ(3);
  @$pb.TagNumber(4)
  set eventName($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasEventName() => $_has(3);
  @$pb.TagNumber(4)
  void clearEventName() => $_clearField(4);
}

class Merchandise extends $pb.GeneratedMessage {
  factory Merchandise({
    $core.int? id,
    $core.int? eventId,
    $core.String? name,
    $core.String? photoUrl,
    $core.String? groupName,
    $core.String? status,
    $core.bool? isDeleted,
    $core.bool? tradeEnabled,
    $core.int? creatorId,
    $core.String? groupDescription,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (eventId != null) result.eventId = eventId;
    if (name != null) result.name = name;
    if (photoUrl != null) result.photoUrl = photoUrl;
    if (groupName != null) result.groupName = groupName;
    if (status != null) result.status = status;
    if (isDeleted != null) result.isDeleted = isDeleted;
    if (tradeEnabled != null) result.tradeEnabled = tradeEnabled;
    if (creatorId != null) result.creatorId = creatorId;
    if (groupDescription != null) result.groupDescription = groupDescription;
    return result;
  }

  Merchandise._();

  factory Merchandise.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Merchandise.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Merchandise',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ymatch'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'id')
    ..aI(2, _omitFieldNames ? '' : 'eventId')
    ..aOS(3, _omitFieldNames ? '' : 'name')
    ..aOS(4, _omitFieldNames ? '' : 'photoUrl')
    ..aOS(5, _omitFieldNames ? '' : 'groupName')
    ..aOS(7, _omitFieldNames ? '' : 'status')
    ..aOB(8, _omitFieldNames ? '' : 'isDeleted')
    ..aOB(9, _omitFieldNames ? '' : 'tradeEnabled')
    ..aI(10, _omitFieldNames ? '' : 'creatorId')
    ..aOS(11, _omitFieldNames ? '' : 'groupDescription')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Merchandise clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Merchandise copyWith(void Function(Merchandise) updates) =>
      super.copyWith((message) => updates(message as Merchandise))
          as Merchandise;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Merchandise create() => Merchandise._();
  @$core.override
  Merchandise createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Merchandise getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Merchandise>(create);
  static Merchandise? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get id => $_getIZ(0);
  @$pb.TagNumber(1)
  set id($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get eventId => $_getIZ(1);
  @$pb.TagNumber(2)
  set eventId($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasEventId() => $_has(1);
  @$pb.TagNumber(2)
  void clearEventId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get name => $_getSZ(2);
  @$pb.TagNumber(3)
  set name($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasName() => $_has(2);
  @$pb.TagNumber(3)
  void clearName() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get photoUrl => $_getSZ(3);
  @$pb.TagNumber(4)
  set photoUrl($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasPhotoUrl() => $_has(3);
  @$pb.TagNumber(4)
  void clearPhotoUrl() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get groupName => $_getSZ(4);
  @$pb.TagNumber(5)
  set groupName($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasGroupName() => $_has(4);
  @$pb.TagNumber(5)
  void clearGroupName() => $_clearField(5);

  @$pb.TagNumber(7)
  $core.String get status => $_getSZ(5);
  @$pb.TagNumber(7)
  set status($core.String value) => $_setString(5, value);
  @$pb.TagNumber(7)
  $core.bool hasStatus() => $_has(5);
  @$pb.TagNumber(7)
  void clearStatus() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.bool get isDeleted => $_getBF(6);
  @$pb.TagNumber(8)
  set isDeleted($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(8)
  $core.bool hasIsDeleted() => $_has(6);
  @$pb.TagNumber(8)
  void clearIsDeleted() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.bool get tradeEnabled => $_getBF(7);
  @$pb.TagNumber(9)
  set tradeEnabled($core.bool value) => $_setBool(7, value);
  @$pb.TagNumber(9)
  $core.bool hasTradeEnabled() => $_has(7);
  @$pb.TagNumber(9)
  void clearTradeEnabled() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.int get creatorId => $_getIZ(8);
  @$pb.TagNumber(10)
  set creatorId($core.int value) => $_setSignedInt32(8, value);
  @$pb.TagNumber(10)
  $core.bool hasCreatorId() => $_has(8);
  @$pb.TagNumber(10)
  void clearCreatorId() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.String get groupDescription => $_getSZ(9);
  @$pb.TagNumber(11)
  set groupDescription($core.String value) => $_setString(9, value);
  @$pb.TagNumber(11)
  $core.bool hasGroupDescription() => $_has(9);
  @$pb.TagNumber(11)
  void clearGroupDescription() => $_clearField(11);
}

class MerchandiseGroup extends $pb.GeneratedMessage {
  factory MerchandiseGroup({
    $core.int? id,
    $core.int? eventId,
    $core.String? groupName,
    $core.String? description,
    $core.int? createdBy,
    $core.String? createdAt,
    $core.String? updatedAt,
    $core.String? photoUrl,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (eventId != null) result.eventId = eventId;
    if (groupName != null) result.groupName = groupName;
    if (description != null) result.description = description;
    if (createdBy != null) result.createdBy = createdBy;
    if (createdAt != null) result.createdAt = createdAt;
    if (updatedAt != null) result.updatedAt = updatedAt;
    if (photoUrl != null) result.photoUrl = photoUrl;
    return result;
  }

  MerchandiseGroup._();

  factory MerchandiseGroup.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory MerchandiseGroup.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MerchandiseGroup',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ymatch'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'id')
    ..aI(2, _omitFieldNames ? '' : 'eventId')
    ..aOS(3, _omitFieldNames ? '' : 'groupName')
    ..aOS(4, _omitFieldNames ? '' : 'description')
    ..aI(5, _omitFieldNames ? '' : 'createdBy')
    ..aOS(6, _omitFieldNames ? '' : 'createdAt')
    ..aOS(7, _omitFieldNames ? '' : 'updatedAt')
    ..aOS(8, _omitFieldNames ? '' : 'photoUrl')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MerchandiseGroup clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MerchandiseGroup copyWith(void Function(MerchandiseGroup) updates) =>
      super.copyWith((message) => updates(message as MerchandiseGroup))
          as MerchandiseGroup;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MerchandiseGroup create() => MerchandiseGroup._();
  @$core.override
  MerchandiseGroup createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static MerchandiseGroup getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MerchandiseGroup>(create);
  static MerchandiseGroup? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get id => $_getIZ(0);
  @$pb.TagNumber(1)
  set id($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get eventId => $_getIZ(1);
  @$pb.TagNumber(2)
  set eventId($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasEventId() => $_has(1);
  @$pb.TagNumber(2)
  void clearEventId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get groupName => $_getSZ(2);
  @$pb.TagNumber(3)
  set groupName($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasGroupName() => $_has(2);
  @$pb.TagNumber(3)
  void clearGroupName() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get description => $_getSZ(3);
  @$pb.TagNumber(4)
  set description($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasDescription() => $_has(3);
  @$pb.TagNumber(4)
  void clearDescription() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get createdBy => $_getIZ(4);
  @$pb.TagNumber(5)
  set createdBy($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasCreatedBy() => $_has(4);
  @$pb.TagNumber(5)
  void clearCreatedBy() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get createdAt => $_getSZ(5);
  @$pb.TagNumber(6)
  set createdAt($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasCreatedAt() => $_has(5);
  @$pb.TagNumber(6)
  void clearCreatedAt() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get updatedAt => $_getSZ(6);
  @$pb.TagNumber(7)
  set updatedAt($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasUpdatedAt() => $_has(6);
  @$pb.TagNumber(7)
  void clearUpdatedAt() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.String get photoUrl => $_getSZ(7);
  @$pb.TagNumber(8)
  set photoUrl($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasPhotoUrl() => $_has(7);
  @$pb.TagNumber(8)
  void clearPhotoUrl() => $_clearField(8);
}

class InventoryItem extends $pb.GeneratedMessage {
  factory InventoryItem({
    $core.int? id,
    $core.int? userId,
    $core.int? merchId,
    $core.String? status,
    $core.int? quantity,
    $core.String? merchName,
    $core.String? photoUrl,
    $core.String? groupName,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (userId != null) result.userId = userId;
    if (merchId != null) result.merchId = merchId;
    if (status != null) result.status = status;
    if (quantity != null) result.quantity = quantity;
    if (merchName != null) result.merchName = merchName;
    if (photoUrl != null) result.photoUrl = photoUrl;
    if (groupName != null) result.groupName = groupName;
    return result;
  }

  InventoryItem._();

  factory InventoryItem.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory InventoryItem.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'InventoryItem',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ymatch'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'id')
    ..aI(2, _omitFieldNames ? '' : 'userId')
    ..aI(3, _omitFieldNames ? '' : 'merchId')
    ..aOS(4, _omitFieldNames ? '' : 'status')
    ..aI(5, _omitFieldNames ? '' : 'quantity')
    ..aOS(6, _omitFieldNames ? '' : 'merchName')
    ..aOS(7, _omitFieldNames ? '' : 'photoUrl')
    ..aOS(8, _omitFieldNames ? '' : 'groupName')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  InventoryItem clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  InventoryItem copyWith(void Function(InventoryItem) updates) =>
      super.copyWith((message) => updates(message as InventoryItem))
          as InventoryItem;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static InventoryItem create() => InventoryItem._();
  @$core.override
  InventoryItem createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static InventoryItem getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<InventoryItem>(create);
  static InventoryItem? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get id => $_getIZ(0);
  @$pb.TagNumber(1)
  set id($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get userId => $_getIZ(1);
  @$pb.TagNumber(2)
  set userId($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasUserId() => $_has(1);
  @$pb.TagNumber(2)
  void clearUserId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get merchId => $_getIZ(2);
  @$pb.TagNumber(3)
  set merchId($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasMerchId() => $_has(2);
  @$pb.TagNumber(3)
  void clearMerchId() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get status => $_getSZ(3);
  @$pb.TagNumber(4)
  set status($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasStatus() => $_has(3);
  @$pb.TagNumber(4)
  void clearStatus() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get quantity => $_getIZ(4);
  @$pb.TagNumber(5)
  set quantity($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasQuantity() => $_has(4);
  @$pb.TagNumber(5)
  void clearQuantity() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get merchName => $_getSZ(5);
  @$pb.TagNumber(6)
  set merchName($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasMerchName() => $_has(5);
  @$pb.TagNumber(6)
  void clearMerchName() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get photoUrl => $_getSZ(6);
  @$pb.TagNumber(7)
  set photoUrl($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasPhotoUrl() => $_has(6);
  @$pb.TagNumber(7)
  void clearPhotoUrl() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.String get groupName => $_getSZ(7);
  @$pb.TagNumber(8)
  set groupName($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasGroupName() => $_has(7);
  @$pb.TagNumber(8)
  void clearGroupName() => $_clearField(8);
}

class TradeMatch extends $pb.GeneratedMessage {
  factory TradeMatch({
    $core.int? id,
    $core.int? user1Id,
    $core.int? user2Id,
    $core.String? status,
    $core.String? createdAt,
    User? otherUser,
    $core.Iterable<InventoryItem>? userHaves,
    $core.Iterable<InventoryItem>? userWants,
    $core.int? offeredBy,
    $core.Iterable<MatchItem>? selectedItems,
    $core.bool? inventoryApplied,
    $core.String? groupName,
    $core.String? eventName,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (user1Id != null) result.user1Id = user1Id;
    if (user2Id != null) result.user2Id = user2Id;
    if (status != null) result.status = status;
    if (createdAt != null) result.createdAt = createdAt;
    if (otherUser != null) result.otherUser = otherUser;
    if (userHaves != null) result.userHaves.addAll(userHaves);
    if (userWants != null) result.userWants.addAll(userWants);
    if (offeredBy != null) result.offeredBy = offeredBy;
    if (selectedItems != null) result.selectedItems.addAll(selectedItems);
    if (inventoryApplied != null) result.inventoryApplied = inventoryApplied;
    if (groupName != null) result.groupName = groupName;
    if (eventName != null) result.eventName = eventName;
    return result;
  }

  TradeMatch._();

  factory TradeMatch.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TradeMatch.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TradeMatch',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ymatch'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'id')
    ..aI(2, _omitFieldNames ? '' : 'user1Id')
    ..aI(3, _omitFieldNames ? '' : 'user2Id')
    ..aOS(4, _omitFieldNames ? '' : 'status')
    ..aOS(5, _omitFieldNames ? '' : 'createdAt')
    ..aOM<User>(6, _omitFieldNames ? '' : 'otherUser', subBuilder: User.create)
    ..pPM<InventoryItem>(7, _omitFieldNames ? '' : 'userHaves',
        subBuilder: InventoryItem.create)
    ..pPM<InventoryItem>(8, _omitFieldNames ? '' : 'userWants',
        subBuilder: InventoryItem.create)
    ..aI(9, _omitFieldNames ? '' : 'offeredBy')
    ..pPM<MatchItem>(10, _omitFieldNames ? '' : 'selectedItems',
        subBuilder: MatchItem.create)
    ..aOB(11, _omitFieldNames ? '' : 'inventoryApplied')
    ..aOS(12, _omitFieldNames ? '' : 'groupName')
    ..aOS(13, _omitFieldNames ? '' : 'eventName')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TradeMatch clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TradeMatch copyWith(void Function(TradeMatch) updates) =>
      super.copyWith((message) => updates(message as TradeMatch)) as TradeMatch;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TradeMatch create() => TradeMatch._();
  @$core.override
  TradeMatch createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TradeMatch getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TradeMatch>(create);
  static TradeMatch? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get id => $_getIZ(0);
  @$pb.TagNumber(1)
  set id($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get user1Id => $_getIZ(1);
  @$pb.TagNumber(2)
  set user1Id($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasUser1Id() => $_has(1);
  @$pb.TagNumber(2)
  void clearUser1Id() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get user2Id => $_getIZ(2);
  @$pb.TagNumber(3)
  set user2Id($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasUser2Id() => $_has(2);
  @$pb.TagNumber(3)
  void clearUser2Id() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get status => $_getSZ(3);
  @$pb.TagNumber(4)
  set status($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasStatus() => $_has(3);
  @$pb.TagNumber(4)
  void clearStatus() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get createdAt => $_getSZ(4);
  @$pb.TagNumber(5)
  set createdAt($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasCreatedAt() => $_has(4);
  @$pb.TagNumber(5)
  void clearCreatedAt() => $_clearField(5);

  @$pb.TagNumber(6)
  User get otherUser => $_getN(5);
  @$pb.TagNumber(6)
  set otherUser(User value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasOtherUser() => $_has(5);
  @$pb.TagNumber(6)
  void clearOtherUser() => $_clearField(6);
  @$pb.TagNumber(6)
  User ensureOtherUser() => $_ensure(5);

  @$pb.TagNumber(7)
  $pb.PbList<InventoryItem> get userHaves => $_getList(6);

  @$pb.TagNumber(8)
  $pb.PbList<InventoryItem> get userWants => $_getList(7);

  @$pb.TagNumber(9)
  $core.int get offeredBy => $_getIZ(8);
  @$pb.TagNumber(9)
  set offeredBy($core.int value) => $_setSignedInt32(8, value);
  @$pb.TagNumber(9)
  $core.bool hasOfferedBy() => $_has(8);
  @$pb.TagNumber(9)
  void clearOfferedBy() => $_clearField(9);

  @$pb.TagNumber(10)
  $pb.PbList<MatchItem> get selectedItems => $_getList(9);

  @$pb.TagNumber(11)
  $core.bool get inventoryApplied => $_getBF(10);
  @$pb.TagNumber(11)
  set inventoryApplied($core.bool value) => $_setBool(10, value);
  @$pb.TagNumber(11)
  $core.bool hasInventoryApplied() => $_has(10);
  @$pb.TagNumber(11)
  void clearInventoryApplied() => $_clearField(11);

  @$pb.TagNumber(12)
  $core.String get groupName => $_getSZ(11);
  @$pb.TagNumber(12)
  set groupName($core.String value) => $_setString(11, value);
  @$pb.TagNumber(12)
  $core.bool hasGroupName() => $_has(11);
  @$pb.TagNumber(12)
  void clearGroupName() => $_clearField(12);

  @$pb.TagNumber(13)
  $core.String get eventName => $_getSZ(12);
  @$pb.TagNumber(13)
  set eventName($core.String value) => $_setString(12, value);
  @$pb.TagNumber(13)
  $core.bool hasEventName() => $_has(12);
  @$pb.TagNumber(13)
  void clearEventName() => $_clearField(13);
}

class MatchItem extends $pb.GeneratedMessage {
  factory MatchItem({
    $core.int? id,
    $core.int? matchId,
    $core.int? merchId,
    $core.int? giverUserId,
    $core.int? quantity,
    $core.String? merchName,
    $core.String? photoUrl,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (matchId != null) result.matchId = matchId;
    if (merchId != null) result.merchId = merchId;
    if (giverUserId != null) result.giverUserId = giverUserId;
    if (quantity != null) result.quantity = quantity;
    if (merchName != null) result.merchName = merchName;
    if (photoUrl != null) result.photoUrl = photoUrl;
    return result;
  }

  MatchItem._();

  factory MatchItem.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory MatchItem.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MatchItem',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ymatch'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'id')
    ..aI(2, _omitFieldNames ? '' : 'matchId')
    ..aI(3, _omitFieldNames ? '' : 'merchId')
    ..aI(4, _omitFieldNames ? '' : 'giverUserId')
    ..aI(6, _omitFieldNames ? '' : 'quantity')
    ..aOS(7, _omitFieldNames ? '' : 'merchName')
    ..aOS(8, _omitFieldNames ? '' : 'photoUrl')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MatchItem clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MatchItem copyWith(void Function(MatchItem) updates) =>
      super.copyWith((message) => updates(message as MatchItem)) as MatchItem;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MatchItem create() => MatchItem._();
  @$core.override
  MatchItem createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static MatchItem getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MatchItem>(create);
  static MatchItem? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get id => $_getIZ(0);
  @$pb.TagNumber(1)
  set id($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get matchId => $_getIZ(1);
  @$pb.TagNumber(2)
  set matchId($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMatchId() => $_has(1);
  @$pb.TagNumber(2)
  void clearMatchId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get merchId => $_getIZ(2);
  @$pb.TagNumber(3)
  set merchId($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasMerchId() => $_has(2);
  @$pb.TagNumber(3)
  void clearMerchId() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get giverUserId => $_getIZ(3);
  @$pb.TagNumber(4)
  set giverUserId($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasGiverUserId() => $_has(3);
  @$pb.TagNumber(4)
  void clearGiverUserId() => $_clearField(4);

  @$pb.TagNumber(6)
  $core.int get quantity => $_getIZ(4);
  @$pb.TagNumber(6)
  set quantity($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(6)
  $core.bool hasQuantity() => $_has(4);
  @$pb.TagNumber(6)
  void clearQuantity() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get merchName => $_getSZ(5);
  @$pb.TagNumber(7)
  set merchName($core.String value) => $_setString(5, value);
  @$pb.TagNumber(7)
  $core.bool hasMerchName() => $_has(5);
  @$pb.TagNumber(7)
  void clearMerchName() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.String get photoUrl => $_getSZ(6);
  @$pb.TagNumber(8)
  set photoUrl($core.String value) => $_setString(6, value);
  @$pb.TagNumber(8)
  $core.bool hasPhotoUrl() => $_has(6);
  @$pb.TagNumber(8)
  void clearPhotoUrl() => $_clearField(8);
}

/// Request/Response Models
class GuestLoginRequest extends $pb.GeneratedMessage {
  factory GuestLoginRequest({
    $core.String? uuid,
    $core.String? deviceToken,
  }) {
    final result = create();
    if (uuid != null) result.uuid = uuid;
    if (deviceToken != null) result.deviceToken = deviceToken;
    return result;
  }

  GuestLoginRequest._();

  factory GuestLoginRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory GuestLoginRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GuestLoginRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ymatch'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'uuid')
    ..aOS(2, _omitFieldNames ? '' : 'deviceToken')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GuestLoginRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GuestLoginRequest copyWith(void Function(GuestLoginRequest) updates) =>
      super.copyWith((message) => updates(message as GuestLoginRequest))
          as GuestLoginRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GuestLoginRequest create() => GuestLoginRequest._();
  @$core.override
  GuestLoginRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static GuestLoginRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GuestLoginRequest>(create);
  static GuestLoginRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get uuid => $_getSZ(0);
  @$pb.TagNumber(1)
  set uuid($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasUuid() => $_has(0);
  @$pb.TagNumber(1)
  void clearUuid() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get deviceToken => $_getSZ(1);
  @$pb.TagNumber(2)
  set deviceToken($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDeviceToken() => $_has(1);
  @$pb.TagNumber(2)
  void clearDeviceToken() => $_clearField(2);
}

class LoginRequest extends $pb.GeneratedMessage {
  factory LoginRequest({
    $core.String? username,
    $core.String? password,
  }) {
    final result = create();
    if (username != null) result.username = username;
    if (password != null) result.password = password;
    return result;
  }

  LoginRequest._();

  factory LoginRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory LoginRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LoginRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ymatch'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'username')
    ..aOS(2, _omitFieldNames ? '' : 'password')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LoginRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LoginRequest copyWith(void Function(LoginRequest) updates) =>
      super.copyWith((message) => updates(message as LoginRequest))
          as LoginRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LoginRequest create() => LoginRequest._();
  @$core.override
  LoginRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static LoginRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<LoginRequest>(create);
  static LoginRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get username => $_getSZ(0);
  @$pb.TagNumber(1)
  set username($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasUsername() => $_has(0);
  @$pb.TagNumber(1)
  void clearUsername() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get password => $_getSZ(1);
  @$pb.TagNumber(2)
  set password($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPassword() => $_has(1);
  @$pb.TagNumber(2)
  void clearPassword() => $_clearField(2);
}

class CreateUserRequest extends $pb.GeneratedMessage {
  factory CreateUserRequest({
    $core.String? username,
    $core.String? password,
    $core.String? deviceToken,
  }) {
    final result = create();
    if (username != null) result.username = username;
    if (password != null) result.password = password;
    if (deviceToken != null) result.deviceToken = deviceToken;
    return result;
  }

  CreateUserRequest._();

  factory CreateUserRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CreateUserRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CreateUserRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ymatch'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'username')
    ..aOS(2, _omitFieldNames ? '' : 'password')
    ..aOS(3, _omitFieldNames ? '' : 'deviceToken')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateUserRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateUserRequest copyWith(void Function(CreateUserRequest) updates) =>
      super.copyWith((message) => updates(message as CreateUserRequest))
          as CreateUserRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CreateUserRequest create() => CreateUserRequest._();
  @$core.override
  CreateUserRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CreateUserRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CreateUserRequest>(create);
  static CreateUserRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get username => $_getSZ(0);
  @$pb.TagNumber(1)
  set username($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasUsername() => $_has(0);
  @$pb.TagNumber(1)
  void clearUsername() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get password => $_getSZ(1);
  @$pb.TagNumber(2)
  set password($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPassword() => $_has(1);
  @$pb.TagNumber(2)
  void clearPassword() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get deviceToken => $_getSZ(2);
  @$pb.TagNumber(3)
  set deviceToken($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDeviceToken() => $_has(2);
  @$pb.TagNumber(3)
  void clearDeviceToken() => $_clearField(3);
}

class CreateEventRequest extends $pb.GeneratedMessage {
  factory CreateEventRequest({
    $core.String? name,
    $core.int? creatorId,
    $core.String? status,
  }) {
    final result = create();
    if (name != null) result.name = name;
    if (creatorId != null) result.creatorId = creatorId;
    if (status != null) result.status = status;
    return result;
  }

  CreateEventRequest._();

  factory CreateEventRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CreateEventRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CreateEventRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ymatch'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..aI(2, _omitFieldNames ? '' : 'creatorId')
    ..aOS(3, _omitFieldNames ? '' : 'status')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateEventRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateEventRequest copyWith(void Function(CreateEventRequest) updates) =>
      super.copyWith((message) => updates(message as CreateEventRequest))
          as CreateEventRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CreateEventRequest create() => CreateEventRequest._();
  @$core.override
  CreateEventRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CreateEventRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CreateEventRequest>(create);
  static CreateEventRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get creatorId => $_getIZ(1);
  @$pb.TagNumber(2)
  set creatorId($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasCreatorId() => $_has(1);
  @$pb.TagNumber(2)
  void clearCreatorId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get status => $_getSZ(2);
  @$pb.TagNumber(3)
  set status($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasStatus() => $_has(2);
  @$pb.TagNumber(3)
  void clearStatus() => $_clearField(3);
}

class UpdateEventRequest extends $pb.GeneratedMessage {
  factory UpdateEventRequest({
    $core.int? userId,
    $core.String? name,
  }) {
    final result = create();
    if (userId != null) result.userId = userId;
    if (name != null) result.name = name;
    return result;
  }

  UpdateEventRequest._();

  factory UpdateEventRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory UpdateEventRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UpdateEventRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ymatch'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'userId')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateEventRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateEventRequest copyWith(void Function(UpdateEventRequest) updates) =>
      super.copyWith((message) => updates(message as UpdateEventRequest))
          as UpdateEventRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UpdateEventRequest create() => UpdateEventRequest._();
  @$core.override
  UpdateEventRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static UpdateEventRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UpdateEventRequest>(create);
  static UpdateEventRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get userId => $_getIZ(0);
  @$pb.TagNumber(1)
  set userId($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasUserId() => $_has(0);
  @$pb.TagNumber(1)
  void clearUserId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => $_clearField(2);
}

class ToggleFavoriteRequest extends $pb.GeneratedMessage {
  factory ToggleFavoriteRequest({
    $core.int? userId,
    $core.bool? isFavorite,
  }) {
    final result = create();
    if (userId != null) result.userId = userId;
    if (isFavorite != null) result.isFavorite = isFavorite;
    return result;
  }

  ToggleFavoriteRequest._();

  factory ToggleFavoriteRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ToggleFavoriteRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ToggleFavoriteRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ymatch'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'userId')
    ..aOB(2, _omitFieldNames ? '' : 'isFavorite')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ToggleFavoriteRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ToggleFavoriteRequest copyWith(
          void Function(ToggleFavoriteRequest) updates) =>
      super.copyWith((message) => updates(message as ToggleFavoriteRequest))
          as ToggleFavoriteRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ToggleFavoriteRequest create() => ToggleFavoriteRequest._();
  @$core.override
  ToggleFavoriteRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ToggleFavoriteRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ToggleFavoriteRequest>(create);
  static ToggleFavoriteRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get userId => $_getIZ(0);
  @$pb.TagNumber(1)
  set userId($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasUserId() => $_has(0);
  @$pb.TagNumber(1)
  void clearUserId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get isFavorite => $_getBF(1);
  @$pb.TagNumber(2)
  set isFavorite($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasIsFavorite() => $_has(1);
  @$pb.TagNumber(2)
  void clearIsFavorite() => $_clearField(2);
}

class ToggleFavoriteGroupRequest extends $pb.GeneratedMessage {
  factory ToggleFavoriteGroupRequest({
    $core.int? userId,
    $core.String? groupName,
    $core.bool? isFavorite,
  }) {
    final result = create();
    if (userId != null) result.userId = userId;
    if (groupName != null) result.groupName = groupName;
    if (isFavorite != null) result.isFavorite = isFavorite;
    return result;
  }

  ToggleFavoriteGroupRequest._();

  factory ToggleFavoriteGroupRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ToggleFavoriteGroupRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ToggleFavoriteGroupRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ymatch'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'userId')
    ..aOS(2, _omitFieldNames ? '' : 'groupName')
    ..aOB(3, _omitFieldNames ? '' : 'isFavorite')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ToggleFavoriteGroupRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ToggleFavoriteGroupRequest copyWith(
          void Function(ToggleFavoriteGroupRequest) updates) =>
      super.copyWith(
              (message) => updates(message as ToggleFavoriteGroupRequest))
          as ToggleFavoriteGroupRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ToggleFavoriteGroupRequest create() => ToggleFavoriteGroupRequest._();
  @$core.override
  ToggleFavoriteGroupRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ToggleFavoriteGroupRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ToggleFavoriteGroupRequest>(create);
  static ToggleFavoriteGroupRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get userId => $_getIZ(0);
  @$pb.TagNumber(1)
  set userId($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasUserId() => $_has(0);
  @$pb.TagNumber(1)
  void clearUserId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get groupName => $_getSZ(1);
  @$pb.TagNumber(2)
  set groupName($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasGroupName() => $_has(1);
  @$pb.TagNumber(2)
  void clearGroupName() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get isFavorite => $_getBF(2);
  @$pb.TagNumber(3)
  set isFavorite($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasIsFavorite() => $_has(2);
  @$pb.TagNumber(3)
  void clearIsFavorite() => $_clearField(3);
}

class UpdateInventoryRequest extends $pb.GeneratedMessage {
  factory UpdateInventoryRequest({
    $core.int? userId,
    $core.int? merchId,
    $core.String? status,
    $core.int? quantity,
  }) {
    final result = create();
    if (userId != null) result.userId = userId;
    if (merchId != null) result.merchId = merchId;
    if (status != null) result.status = status;
    if (quantity != null) result.quantity = quantity;
    return result;
  }

  UpdateInventoryRequest._();

  factory UpdateInventoryRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory UpdateInventoryRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UpdateInventoryRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ymatch'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'userId')
    ..aI(2, _omitFieldNames ? '' : 'merchId')
    ..aOS(3, _omitFieldNames ? '' : 'status')
    ..aI(4, _omitFieldNames ? '' : 'quantity')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateInventoryRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateInventoryRequest copyWith(
          void Function(UpdateInventoryRequest) updates) =>
      super.copyWith((message) => updates(message as UpdateInventoryRequest))
          as UpdateInventoryRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UpdateInventoryRequest create() => UpdateInventoryRequest._();
  @$core.override
  UpdateInventoryRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static UpdateInventoryRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UpdateInventoryRequest>(create);
  static UpdateInventoryRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get userId => $_getIZ(0);
  @$pb.TagNumber(1)
  set userId($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasUserId() => $_has(0);
  @$pb.TagNumber(1)
  void clearUserId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get merchId => $_getIZ(1);
  @$pb.TagNumber(2)
  set merchId($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMerchId() => $_has(1);
  @$pb.TagNumber(2)
  void clearMerchId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get status => $_getSZ(2);
  @$pb.TagNumber(3)
  set status($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasStatus() => $_has(2);
  @$pb.TagNumber(3)
  void clearStatus() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get quantity => $_getIZ(3);
  @$pb.TagNumber(4)
  set quantity($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasQuantity() => $_has(3);
  @$pb.TagNumber(4)
  void clearQuantity() => $_clearField(4);
}

class CreateMerchRequest extends $pb.GeneratedMessage {
  factory CreateMerchRequest({
    $core.String? name,
    $core.String? photoUrl,
    $core.String? groupName,
    $core.int? creatorId,
    $core.String? status,
  }) {
    final result = create();
    if (name != null) result.name = name;
    if (photoUrl != null) result.photoUrl = photoUrl;
    if (groupName != null) result.groupName = groupName;
    if (creatorId != null) result.creatorId = creatorId;
    if (status != null) result.status = status;
    return result;
  }

  CreateMerchRequest._();

  factory CreateMerchRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CreateMerchRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CreateMerchRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ymatch'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..aOS(2, _omitFieldNames ? '' : 'photoUrl')
    ..aOS(3, _omitFieldNames ? '' : 'groupName')
    ..aI(4, _omitFieldNames ? '' : 'creatorId')
    ..aOS(5, _omitFieldNames ? '' : 'status')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateMerchRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateMerchRequest copyWith(void Function(CreateMerchRequest) updates) =>
      super.copyWith((message) => updates(message as CreateMerchRequest))
          as CreateMerchRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CreateMerchRequest create() => CreateMerchRequest._();
  @$core.override
  CreateMerchRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CreateMerchRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CreateMerchRequest>(create);
  static CreateMerchRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get photoUrl => $_getSZ(1);
  @$pb.TagNumber(2)
  set photoUrl($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPhotoUrl() => $_has(1);
  @$pb.TagNumber(2)
  void clearPhotoUrl() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get groupName => $_getSZ(2);
  @$pb.TagNumber(3)
  set groupName($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasGroupName() => $_has(2);
  @$pb.TagNumber(3)
  void clearGroupName() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get creatorId => $_getIZ(3);
  @$pb.TagNumber(4)
  set creatorId($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasCreatorId() => $_has(3);
  @$pb.TagNumber(4)
  void clearCreatorId() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get status => $_getSZ(4);
  @$pb.TagNumber(5)
  set status($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasStatus() => $_has(4);
  @$pb.TagNumber(5)
  void clearStatus() => $_clearField(5);
}

class UpdateMerchRequest extends $pb.GeneratedMessage {
  factory UpdateMerchRequest({
    $core.int? userId,
    $core.String? name,
    $core.String? photoUrl,
    $core.String? groupName,
  }) {
    final result = create();
    if (userId != null) result.userId = userId;
    if (name != null) result.name = name;
    if (photoUrl != null) result.photoUrl = photoUrl;
    if (groupName != null) result.groupName = groupName;
    return result;
  }

  UpdateMerchRequest._();

  factory UpdateMerchRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory UpdateMerchRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UpdateMerchRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ymatch'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'userId')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..aOS(3, _omitFieldNames ? '' : 'photoUrl')
    ..aOS(4, _omitFieldNames ? '' : 'groupName')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateMerchRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateMerchRequest copyWith(void Function(UpdateMerchRequest) updates) =>
      super.copyWith((message) => updates(message as UpdateMerchRequest))
          as UpdateMerchRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UpdateMerchRequest create() => UpdateMerchRequest._();
  @$core.override
  UpdateMerchRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static UpdateMerchRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UpdateMerchRequest>(create);
  static UpdateMerchRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get userId => $_getIZ(0);
  @$pb.TagNumber(1)
  set userId($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasUserId() => $_has(0);
  @$pb.TagNumber(1)
  void clearUserId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get photoUrl => $_getSZ(2);
  @$pb.TagNumber(3)
  set photoUrl($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasPhotoUrl() => $_has(2);
  @$pb.TagNumber(3)
  void clearPhotoUrl() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get groupName => $_getSZ(3);
  @$pb.TagNumber(4)
  set groupName($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasGroupName() => $_has(3);
  @$pb.TagNumber(4)
  void clearGroupName() => $_clearField(4);
}

class UpdateMatchStatusRequest extends $pb.GeneratedMessage {
  factory UpdateMatchStatusRequest({
    $core.String? status,
    $core.int? userId,
  }) {
    final result = create();
    if (status != null) result.status = status;
    if (userId != null) result.userId = userId;
    return result;
  }

  UpdateMatchStatusRequest._();

  factory UpdateMatchStatusRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory UpdateMatchStatusRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UpdateMatchStatusRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ymatch'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'status')
    ..aI(2, _omitFieldNames ? '' : 'userId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateMatchStatusRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateMatchStatusRequest copyWith(
          void Function(UpdateMatchStatusRequest) updates) =>
      super.copyWith((message) => updates(message as UpdateMatchStatusRequest))
          as UpdateMatchStatusRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UpdateMatchStatusRequest create() => UpdateMatchStatusRequest._();
  @$core.override
  UpdateMatchStatusRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static UpdateMatchStatusRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UpdateMatchStatusRequest>(create);
  static UpdateMatchStatusRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get status => $_getSZ(0);
  @$pb.TagNumber(1)
  set status($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasStatus() => $_has(0);
  @$pb.TagNumber(1)
  void clearStatus() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get userId => $_getIZ(1);
  @$pb.TagNumber(2)
  set userId($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasUserId() => $_has(1);
  @$pb.TagNumber(2)
  void clearUserId() => $_clearField(2);
}

class OfferTradeRequest extends $pb.GeneratedMessage {
  factory OfferTradeRequest({
    $core.int? userId,
    $core.Iterable<OfferItem>? items,
  }) {
    final result = create();
    if (userId != null) result.userId = userId;
    if (items != null) result.items.addAll(items);
    return result;
  }

  OfferTradeRequest._();

  factory OfferTradeRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory OfferTradeRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'OfferTradeRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ymatch'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'userId')
    ..pPM<OfferItem>(2, _omitFieldNames ? '' : 'items',
        subBuilder: OfferItem.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  OfferTradeRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  OfferTradeRequest copyWith(void Function(OfferTradeRequest) updates) =>
      super.copyWith((message) => updates(message as OfferTradeRequest))
          as OfferTradeRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static OfferTradeRequest create() => OfferTradeRequest._();
  @$core.override
  OfferTradeRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static OfferTradeRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<OfferTradeRequest>(create);
  static OfferTradeRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get userId => $_getIZ(0);
  @$pb.TagNumber(1)
  set userId($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasUserId() => $_has(0);
  @$pb.TagNumber(1)
  void clearUserId() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<OfferItem> get items => $_getList(1);
}

class OfferItem extends $pb.GeneratedMessage {
  factory OfferItem({
    $core.int? merchId,
    $core.int? giverUserId,
    $core.int? quantity,
  }) {
    final result = create();
    if (merchId != null) result.merchId = merchId;
    if (giverUserId != null) result.giverUserId = giverUserId;
    if (quantity != null) result.quantity = quantity;
    return result;
  }

  OfferItem._();

  factory OfferItem.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory OfferItem.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'OfferItem',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ymatch'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'merchId')
    ..aI(2, _omitFieldNames ? '' : 'giverUserId')
    ..aI(3, _omitFieldNames ? '' : 'quantity')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  OfferItem clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  OfferItem copyWith(void Function(OfferItem) updates) =>
      super.copyWith((message) => updates(message as OfferItem)) as OfferItem;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static OfferItem create() => OfferItem._();
  @$core.override
  OfferItem createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static OfferItem getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<OfferItem>(create);
  static OfferItem? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get merchId => $_getIZ(0);
  @$pb.TagNumber(1)
  set merchId($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasMerchId() => $_has(0);
  @$pb.TagNumber(1)
  void clearMerchId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get giverUserId => $_getIZ(1);
  @$pb.TagNumber(2)
  set giverUserId($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasGiverUserId() => $_has(1);
  @$pb.TagNumber(2)
  void clearGiverUserId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get quantity => $_getIZ(2);
  @$pb.TagNumber(3)
  set quantity($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasQuantity() => $_has(2);
  @$pb.TagNumber(3)
  void clearQuantity() => $_clearField(3);
}

class ApplyInventoryRequest extends $pb.GeneratedMessage {
  factory ApplyInventoryRequest({
    $core.int? userId,
  }) {
    final result = create();
    if (userId != null) result.userId = userId;
    return result;
  }

  ApplyInventoryRequest._();

  factory ApplyInventoryRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ApplyInventoryRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ApplyInventoryRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ymatch'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'userId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ApplyInventoryRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ApplyInventoryRequest copyWith(
          void Function(ApplyInventoryRequest) updates) =>
      super.copyWith((message) => updates(message as ApplyInventoryRequest))
          as ApplyInventoryRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ApplyInventoryRequest create() => ApplyInventoryRequest._();
  @$core.override
  ApplyInventoryRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ApplyInventoryRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ApplyInventoryRequest>(create);
  static ApplyInventoryRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get userId => $_getIZ(0);
  @$pb.TagNumber(1)
  set userId($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasUserId() => $_has(0);
  @$pb.TagNumber(1)
  void clearUserId() => $_clearField(1);
}

class NotificationCounts extends $pb.GeneratedMessage {
  factory NotificationCounts({
    $core.int? pendingMatches,
    $core.int? offersIn,
    $core.int? accepted,
    $core.int? unreadMessages,
    $core.int? total,
  }) {
    final result = create();
    if (pendingMatches != null) result.pendingMatches = pendingMatches;
    if (offersIn != null) result.offersIn = offersIn;
    if (accepted != null) result.accepted = accepted;
    if (unreadMessages != null) result.unreadMessages = unreadMessages;
    if (total != null) result.total = total;
    return result;
  }

  NotificationCounts._();

  factory NotificationCounts.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory NotificationCounts.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'NotificationCounts',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ymatch'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'pendingMatches')
    ..aI(2, _omitFieldNames ? '' : 'offersIn')
    ..aI(3, _omitFieldNames ? '' : 'accepted')
    ..aI(4, _omitFieldNames ? '' : 'unreadMessages')
    ..aI(5, _omitFieldNames ? '' : 'total')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  NotificationCounts clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  NotificationCounts copyWith(void Function(NotificationCounts) updates) =>
      super.copyWith((message) => updates(message as NotificationCounts))
          as NotificationCounts;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static NotificationCounts create() => NotificationCounts._();
  @$core.override
  NotificationCounts createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static NotificationCounts getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<NotificationCounts>(create);
  static NotificationCounts? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get pendingMatches => $_getIZ(0);
  @$pb.TagNumber(1)
  set pendingMatches($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPendingMatches() => $_has(0);
  @$pb.TagNumber(1)
  void clearPendingMatches() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get offersIn => $_getIZ(1);
  @$pb.TagNumber(2)
  set offersIn($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasOffersIn() => $_has(1);
  @$pb.TagNumber(2)
  void clearOffersIn() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get accepted => $_getIZ(2);
  @$pb.TagNumber(3)
  set accepted($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAccepted() => $_has(2);
  @$pb.TagNumber(3)
  void clearAccepted() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get unreadMessages => $_getIZ(3);
  @$pb.TagNumber(4)
  set unreadMessages($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasUnreadMessages() => $_has(3);
  @$pb.TagNumber(4)
  void clearUnreadMessages() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get total => $_getIZ(4);
  @$pb.TagNumber(5)
  set total($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasTotal() => $_has(4);
  @$pb.TagNumber(5)
  void clearTotal() => $_clearField(5);
}

class Message extends $pb.GeneratedMessage {
  factory Message({
    $core.int? id,
    $core.int? matchId,
    $core.int? senderId,
    $core.String? content,
    $core.String? createdAt,
    $core.String? messageType,
    $core.double? latitude,
    $core.double? longitude,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (matchId != null) result.matchId = matchId;
    if (senderId != null) result.senderId = senderId;
    if (content != null) result.content = content;
    if (createdAt != null) result.createdAt = createdAt;
    if (messageType != null) result.messageType = messageType;
    if (latitude != null) result.latitude = latitude;
    if (longitude != null) result.longitude = longitude;
    return result;
  }

  Message._();

  factory Message.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Message.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Message',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ymatch'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'id')
    ..aI(2, _omitFieldNames ? '' : 'matchId')
    ..aI(3, _omitFieldNames ? '' : 'senderId')
    ..aOS(4, _omitFieldNames ? '' : 'content')
    ..aOS(5, _omitFieldNames ? '' : 'createdAt')
    ..aOS(6, _omitFieldNames ? '' : 'messageType')
    ..aD(7, _omitFieldNames ? '' : 'latitude')
    ..aD(8, _omitFieldNames ? '' : 'longitude')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Message clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Message copyWith(void Function(Message) updates) =>
      super.copyWith((message) => updates(message as Message)) as Message;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Message create() => Message._();
  @$core.override
  Message createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Message getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Message>(create);
  static Message? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get id => $_getIZ(0);
  @$pb.TagNumber(1)
  set id($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get matchId => $_getIZ(1);
  @$pb.TagNumber(2)
  set matchId($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMatchId() => $_has(1);
  @$pb.TagNumber(2)
  void clearMatchId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get senderId => $_getIZ(2);
  @$pb.TagNumber(3)
  set senderId($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSenderId() => $_has(2);
  @$pb.TagNumber(3)
  void clearSenderId() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get content => $_getSZ(3);
  @$pb.TagNumber(4)
  set content($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasContent() => $_has(3);
  @$pb.TagNumber(4)
  void clearContent() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get createdAt => $_getSZ(4);
  @$pb.TagNumber(5)
  set createdAt($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasCreatedAt() => $_has(4);
  @$pb.TagNumber(5)
  void clearCreatedAt() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get messageType => $_getSZ(5);
  @$pb.TagNumber(6)
  set messageType($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasMessageType() => $_has(5);
  @$pb.TagNumber(6)
  void clearMessageType() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.double get latitude => $_getN(6);
  @$pb.TagNumber(7)
  set latitude($core.double value) => $_setDouble(6, value);
  @$pb.TagNumber(7)
  $core.bool hasLatitude() => $_has(6);
  @$pb.TagNumber(7)
  void clearLatitude() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.double get longitude => $_getN(7);
  @$pb.TagNumber(8)
  set longitude($core.double value) => $_setDouble(7, value);
  @$pb.TagNumber(8)
  $core.bool hasLongitude() => $_has(7);
  @$pb.TagNumber(8)
  void clearLongitude() => $_clearField(8);
}

class SendMessageRequest extends $pb.GeneratedMessage {
  factory SendMessageRequest({
    $core.int? matchId,
    $core.int? senderId,
    $core.String? content,
    $core.String? messageType,
    $core.double? latitude,
    $core.double? longitude,
  }) {
    final result = create();
    if (matchId != null) result.matchId = matchId;
    if (senderId != null) result.senderId = senderId;
    if (content != null) result.content = content;
    if (messageType != null) result.messageType = messageType;
    if (latitude != null) result.latitude = latitude;
    if (longitude != null) result.longitude = longitude;
    return result;
  }

  SendMessageRequest._();

  factory SendMessageRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SendMessageRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SendMessageRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ymatch'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'matchId')
    ..aI(2, _omitFieldNames ? '' : 'senderId')
    ..aOS(3, _omitFieldNames ? '' : 'content')
    ..aOS(4, _omitFieldNames ? '' : 'messageType')
    ..aD(5, _omitFieldNames ? '' : 'latitude')
    ..aD(6, _omitFieldNames ? '' : 'longitude')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SendMessageRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SendMessageRequest copyWith(void Function(SendMessageRequest) updates) =>
      super.copyWith((message) => updates(message as SendMessageRequest))
          as SendMessageRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SendMessageRequest create() => SendMessageRequest._();
  @$core.override
  SendMessageRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SendMessageRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SendMessageRequest>(create);
  static SendMessageRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get matchId => $_getIZ(0);
  @$pb.TagNumber(1)
  set matchId($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasMatchId() => $_has(0);
  @$pb.TagNumber(1)
  void clearMatchId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get senderId => $_getIZ(1);
  @$pb.TagNumber(2)
  set senderId($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSenderId() => $_has(1);
  @$pb.TagNumber(2)
  void clearSenderId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get content => $_getSZ(2);
  @$pb.TagNumber(3)
  set content($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasContent() => $_has(2);
  @$pb.TagNumber(3)
  void clearContent() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get messageType => $_getSZ(3);
  @$pb.TagNumber(4)
  set messageType($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasMessageType() => $_has(3);
  @$pb.TagNumber(4)
  void clearMessageType() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.double get latitude => $_getN(4);
  @$pb.TagNumber(5)
  set latitude($core.double value) => $_setDouble(4, value);
  @$pb.TagNumber(5)
  $core.bool hasLatitude() => $_has(4);
  @$pb.TagNumber(5)
  void clearLatitude() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.double get longitude => $_getN(5);
  @$pb.TagNumber(6)
  set longitude($core.double value) => $_setDouble(5, value);
  @$pb.TagNumber(6)
  $core.bool hasLongitude() => $_has(5);
  @$pb.TagNumber(6)
  void clearLongitude() => $_clearField(6);
}

class SearchResult extends $pb.GeneratedMessage {
  factory SearchResult({
    $core.String? type,
    $core.int? id,
    $core.String? title,
    $core.String? subtitle,
    $core.String? photoUrl,
    $core.int? eventId,
  }) {
    final result = create();
    if (type != null) result.type = type;
    if (id != null) result.id = id;
    if (title != null) result.title = title;
    if (subtitle != null) result.subtitle = subtitle;
    if (photoUrl != null) result.photoUrl = photoUrl;
    if (eventId != null) result.eventId = eventId;
    return result;
  }

  SearchResult._();

  factory SearchResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SearchResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SearchResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ymatch'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'type')
    ..aI(2, _omitFieldNames ? '' : 'id')
    ..aOS(3, _omitFieldNames ? '' : 'title')
    ..aOS(4, _omitFieldNames ? '' : 'subtitle')
    ..aOS(5, _omitFieldNames ? '' : 'photoUrl')
    ..aI(6, _omitFieldNames ? '' : 'eventId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SearchResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SearchResult copyWith(void Function(SearchResult) updates) =>
      super.copyWith((message) => updates(message as SearchResult))
          as SearchResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SearchResult create() => SearchResult._();
  @$core.override
  SearchResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SearchResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SearchResult>(create);
  static SearchResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get type => $_getSZ(0);
  @$pb.TagNumber(1)
  set type($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasType() => $_has(0);
  @$pb.TagNumber(1)
  void clearType() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get id => $_getIZ(1);
  @$pb.TagNumber(2)
  set id($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasId() => $_has(1);
  @$pb.TagNumber(2)
  void clearId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get title => $_getSZ(2);
  @$pb.TagNumber(3)
  set title($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasTitle() => $_has(2);
  @$pb.TagNumber(3)
  void clearTitle() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get subtitle => $_getSZ(3);
  @$pb.TagNumber(4)
  set subtitle($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSubtitle() => $_has(3);
  @$pb.TagNumber(4)
  void clearSubtitle() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get photoUrl => $_getSZ(4);
  @$pb.TagNumber(5)
  set photoUrl($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasPhotoUrl() => $_has(4);
  @$pb.TagNumber(5)
  void clearPhotoUrl() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get eventId => $_getIZ(5);
  @$pb.TagNumber(6)
  set eventId($core.int value) => $_setSignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasEventId() => $_has(5);
  @$pb.TagNumber(6)
  void clearEventId() => $_clearField(6);
}

/// Admin request types
class BanUserRequest extends $pb.GeneratedMessage {
  factory BanUserRequest({
    $core.String? reason,
    $core.String? bannedUntil,
  }) {
    final result = create();
    if (reason != null) result.reason = reason;
    if (bannedUntil != null) result.bannedUntil = bannedUntil;
    return result;
  }

  BanUserRequest._();

  factory BanUserRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory BanUserRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'BanUserRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ymatch'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'reason')
    ..aOS(2, _omitFieldNames ? '' : 'bannedUntil')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BanUserRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BanUserRequest copyWith(void Function(BanUserRequest) updates) =>
      super.copyWith((message) => updates(message as BanUserRequest))
          as BanUserRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static BanUserRequest create() => BanUserRequest._();
  @$core.override
  BanUserRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static BanUserRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<BanUserRequest>(create);
  static BanUserRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get reason => $_getSZ(0);
  @$pb.TagNumber(1)
  set reason($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasReason() => $_has(0);
  @$pb.TagNumber(1)
  void clearReason() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get bannedUntil => $_getSZ(1);
  @$pb.TagNumber(2)
  set bannedUntil($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasBannedUntil() => $_has(1);
  @$pb.TagNumber(2)
  void clearBannedUntil() => $_clearField(2);
}

class UpdateUserRoleRequest extends $pb.GeneratedMessage {
  factory UpdateUserRoleRequest({
    $core.String? role,
  }) {
    final result = create();
    if (role != null) result.role = role;
    return result;
  }

  UpdateUserRoleRequest._();

  factory UpdateUserRoleRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory UpdateUserRoleRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UpdateUserRoleRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ymatch'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'role')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateUserRoleRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateUserRoleRequest copyWith(
          void Function(UpdateUserRoleRequest) updates) =>
      super.copyWith((message) => updates(message as UpdateUserRoleRequest))
          as UpdateUserRoleRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UpdateUserRoleRequest create() => UpdateUserRoleRequest._();
  @$core.override
  UpdateUserRoleRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static UpdateUserRoleRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UpdateUserRoleRequest>(create);
  static UpdateUserRoleRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get role => $_getSZ(0);
  @$pb.TagNumber(1)
  set role($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRole() => $_has(0);
  @$pb.TagNumber(1)
  void clearRole() => $_clearField(1);
}

class UpdateUsernameRequest extends $pb.GeneratedMessage {
  factory UpdateUsernameRequest({
    $core.int? userId,
    $core.String? username,
  }) {
    final result = create();
    if (userId != null) result.userId = userId;
    if (username != null) result.username = username;
    return result;
  }

  UpdateUsernameRequest._();

  factory UpdateUsernameRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory UpdateUsernameRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UpdateUsernameRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ymatch'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'userId')
    ..aOS(2, _omitFieldNames ? '' : 'username')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateUsernameRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateUsernameRequest copyWith(
          void Function(UpdateUsernameRequest) updates) =>
      super.copyWith((message) => updates(message as UpdateUsernameRequest))
          as UpdateUsernameRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UpdateUsernameRequest create() => UpdateUsernameRequest._();
  @$core.override
  UpdateUsernameRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static UpdateUsernameRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UpdateUsernameRequest>(create);
  static UpdateUsernameRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get userId => $_getIZ(0);
  @$pb.TagNumber(1)
  set userId($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasUserId() => $_has(0);
  @$pb.TagNumber(1)
  void clearUserId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get username => $_getSZ(1);
  @$pb.TagNumber(2)
  set username($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasUsername() => $_has(1);
  @$pb.TagNumber(2)
  void clearUsername() => $_clearField(2);
}

/// Generic request with user_id for permission checks
class UserActionRequest extends $pb.GeneratedMessage {
  factory UserActionRequest({
    $core.int? userId,
  }) {
    final result = create();
    if (userId != null) result.userId = userId;
    return result;
  }

  UserActionRequest._();

  factory UserActionRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory UserActionRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UserActionRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ymatch'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'userId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UserActionRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UserActionRequest copyWith(void Function(UserActionRequest) updates) =>
      super.copyWith((message) => updates(message as UserActionRequest))
          as UserActionRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UserActionRequest create() => UserActionRequest._();
  @$core.override
  UserActionRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static UserActionRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UserActionRequest>(create);
  static UserActionRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get userId => $_getIZ(0);
  @$pb.TagNumber(1)
  set userId($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasUserId() => $_has(0);
  @$pb.TagNumber(1)
  void clearUserId() => $_clearField(1);
}

class CreateGroupRequest extends $pb.GeneratedMessage {
  factory CreateGroupRequest({
    $core.int? eventId,
    $core.int? userId,
    $core.String? groupName,
    $core.String? description,
    $core.String? photoUrl,
  }) {
    final result = create();
    if (eventId != null) result.eventId = eventId;
    if (userId != null) result.userId = userId;
    if (groupName != null) result.groupName = groupName;
    if (description != null) result.description = description;
    if (photoUrl != null) result.photoUrl = photoUrl;
    return result;
  }

  CreateGroupRequest._();

  factory CreateGroupRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CreateGroupRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CreateGroupRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ymatch'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'eventId')
    ..aI(2, _omitFieldNames ? '' : 'userId')
    ..aOS(3, _omitFieldNames ? '' : 'groupName')
    ..aOS(4, _omitFieldNames ? '' : 'description')
    ..aOS(5, _omitFieldNames ? '' : 'photoUrl')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateGroupRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateGroupRequest copyWith(void Function(CreateGroupRequest) updates) =>
      super.copyWith((message) => updates(message as CreateGroupRequest))
          as CreateGroupRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CreateGroupRequest create() => CreateGroupRequest._();
  @$core.override
  CreateGroupRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CreateGroupRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CreateGroupRequest>(create);
  static CreateGroupRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get eventId => $_getIZ(0);
  @$pb.TagNumber(1)
  set eventId($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasEventId() => $_has(0);
  @$pb.TagNumber(1)
  void clearEventId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get userId => $_getIZ(1);
  @$pb.TagNumber(2)
  set userId($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasUserId() => $_has(1);
  @$pb.TagNumber(2)
  void clearUserId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get groupName => $_getSZ(2);
  @$pb.TagNumber(3)
  set groupName($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasGroupName() => $_has(2);
  @$pb.TagNumber(3)
  void clearGroupName() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get description => $_getSZ(3);
  @$pb.TagNumber(4)
  set description($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasDescription() => $_has(3);
  @$pb.TagNumber(4)
  void clearDescription() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get photoUrl => $_getSZ(4);
  @$pb.TagNumber(5)
  set photoUrl($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasPhotoUrl() => $_has(4);
  @$pb.TagNumber(5)
  void clearPhotoUrl() => $_clearField(5);
}

class UpdateGroupRequest extends $pb.GeneratedMessage {
  factory UpdateGroupRequest({
    $core.int? eventId,
    $core.int? userId,
    $core.String? groupName,
    $core.String? description,
    $core.String? photoUrl,
  }) {
    final result = create();
    if (eventId != null) result.eventId = eventId;
    if (userId != null) result.userId = userId;
    if (groupName != null) result.groupName = groupName;
    if (description != null) result.description = description;
    if (photoUrl != null) result.photoUrl = photoUrl;
    return result;
  }

  UpdateGroupRequest._();

  factory UpdateGroupRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory UpdateGroupRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UpdateGroupRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ymatch'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'eventId')
    ..aI(2, _omitFieldNames ? '' : 'userId')
    ..aOS(3, _omitFieldNames ? '' : 'groupName')
    ..aOS(4, _omitFieldNames ? '' : 'description')
    ..aOS(5, _omitFieldNames ? '' : 'photoUrl')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateGroupRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateGroupRequest copyWith(void Function(UpdateGroupRequest) updates) =>
      super.copyWith((message) => updates(message as UpdateGroupRequest))
          as UpdateGroupRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UpdateGroupRequest create() => UpdateGroupRequest._();
  @$core.override
  UpdateGroupRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static UpdateGroupRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UpdateGroupRequest>(create);
  static UpdateGroupRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get eventId => $_getIZ(0);
  @$pb.TagNumber(1)
  set eventId($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasEventId() => $_has(0);
  @$pb.TagNumber(1)
  void clearEventId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get userId => $_getIZ(1);
  @$pb.TagNumber(2)
  set userId($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasUserId() => $_has(1);
  @$pb.TagNumber(2)
  void clearUserId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get groupName => $_getSZ(2);
  @$pb.TagNumber(3)
  set groupName($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasGroupName() => $_has(2);
  @$pb.TagNumber(3)
  void clearGroupName() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get description => $_getSZ(3);
  @$pb.TagNumber(4)
  set description($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasDescription() => $_has(3);
  @$pb.TagNumber(4)
  void clearDescription() => $_clearField(4);

  /// When set: update photo_url (empty string clears). When unset: leave as-is.
  @$pb.TagNumber(5)
  $core.String get photoUrl => $_getSZ(4);
  @$pb.TagNumber(5)
  set photoUrl($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasPhotoUrl() => $_has(4);
  @$pb.TagNumber(5)
  void clearPhotoUrl() => $_clearField(5);
}

class ListGroupsResponse extends $pb.GeneratedMessage {
  factory ListGroupsResponse({
    $core.Iterable<MerchandiseGroup>? groups,
  }) {
    final result = create();
    if (groups != null) result.groups.addAll(groups);
    return result;
  }

  ListGroupsResponse._();

  factory ListGroupsResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListGroupsResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListGroupsResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ymatch'),
      createEmptyInstance: create)
    ..pPM<MerchandiseGroup>(1, _omitFieldNames ? '' : 'groups',
        subBuilder: MerchandiseGroup.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListGroupsResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListGroupsResponse copyWith(void Function(ListGroupsResponse) updates) =>
      super.copyWith((message) => updates(message as ListGroupsResponse))
          as ListGroupsResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListGroupsResponse create() => ListGroupsResponse._();
  @$core.override
  ListGroupsResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListGroupsResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListGroupsResponse>(create);
  static ListGroupsResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<MerchandiseGroup> get groups => $_getList(0);
}

/// Event-member API (ADR 0004 §5, #228 PR3b): event-scoped role assignments
/// for an event. `role` is "creator" or "editor". Used by the
/// GET /api/v1/events/:id/members endpoint.
class EventMember extends $pb.GeneratedMessage {
  factory EventMember({
    $core.int? userId,
    $core.String? role,
    $core.String? username,
  }) {
    final result = create();
    if (userId != null) result.userId = userId;
    if (role != null) result.role = role;
    if (username != null) result.username = username;
    return result;
  }

  EventMember._();

  factory EventMember.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory EventMember.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'EventMember',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ymatch'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'userId')
    ..aOS(2, _omitFieldNames ? '' : 'role')
    ..aOS(3, _omitFieldNames ? '' : 'username')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EventMember clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EventMember copyWith(void Function(EventMember) updates) =>
      super.copyWith((message) => updates(message as EventMember))
          as EventMember;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EventMember create() => EventMember._();
  @$core.override
  EventMember createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static EventMember getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<EventMember>(create);
  static EventMember? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get userId => $_getIZ(0);
  @$pb.TagNumber(1)
  set userId($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasUserId() => $_has(0);
  @$pb.TagNumber(1)
  void clearUserId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get role => $_getSZ(1);
  @$pb.TagNumber(2)
  set role($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasRole() => $_has(1);
  @$pb.TagNumber(2)
  void clearRole() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get username => $_getSZ(2);
  @$pb.TagNumber(3)
  set username($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasUsername() => $_has(2);
  @$pb.TagNumber(3)
  void clearUsername() => $_clearField(3);
}

class ListEventMembersResponse extends $pb.GeneratedMessage {
  factory ListEventMembersResponse({
    $core.Iterable<EventMember>? members,
  }) {
    final result = create();
    if (members != null) result.members.addAll(members);
    return result;
  }

  ListEventMembersResponse._();

  factory ListEventMembersResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListEventMembersResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListEventMembersResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ymatch'),
      createEmptyInstance: create)
    ..pPM<EventMember>(1, _omitFieldNames ? '' : 'members',
        subBuilder: EventMember.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListEventMembersResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListEventMembersResponse copyWith(
          void Function(ListEventMembersResponse) updates) =>
      super.copyWith((message) => updates(message as ListEventMembersResponse))
          as ListEventMembersResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListEventMembersResponse create() => ListEventMembersResponse._();
  @$core.override
  ListEventMembersResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListEventMembersResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListEventMembersResponse>(create);
  static ListEventMembersResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<EventMember> get members => $_getList(0);
}

/// Current-user event-role API (#366): the caller's standing on a single
/// event, used by the frontend to gate the Add Merch button without reading the
/// denormalized `User.role`. Accessible to any active caller (no 403 for a plain
/// viewer) — unlike the creator-only `members` list, this is the per-viewer gate.
///
/// `can_create_merch` is the exact decision `create_merch` enforces (via
/// `RbacService::check(MerchCreate)`), so the frontend gate is the same check,
/// not a re-derivation.
class MyEventRoleResponse extends $pb.GeneratedMessage {
  factory MyEventRoleResponse({
    $core.String? role,
    $core.bool? globalOverride,
    $core.bool? canCreateMerch,
  }) {
    final result = create();
    if (role != null) result.role = role;
    if (globalOverride != null) result.globalOverride = globalOverride;
    if (canCreateMerch != null) result.canCreateMerch = canCreateMerch;
    return result;
  }

  MyEventRoleResponse._();

  factory MyEventRoleResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory MyEventRoleResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MyEventRoleResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ymatch'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'role')
    ..aOB(2, _omitFieldNames ? '' : 'globalOverride')
    ..aOB(3, _omitFieldNames ? '' : 'canCreateMerch')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MyEventRoleResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MyEventRoleResponse copyWith(void Function(MyEventRoleResponse) updates) =>
      super.copyWith((message) => updates(message as MyEventRoleResponse))
          as MyEventRoleResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MyEventRoleResponse create() => MyEventRoleResponse._();
  @$core.override
  MyEventRoleResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static MyEventRoleResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MyEventRoleResponse>(create);
  static MyEventRoleResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get role => $_getSZ(0);
  @$pb.TagNumber(1)
  set role($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRole() => $_has(0);
  @$pb.TagNumber(1)
  void clearRole() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get globalOverride => $_getBF(1);
  @$pb.TagNumber(2)
  set globalOverride($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasGlobalOverride() => $_has(1);
  @$pb.TagNumber(2)
  void clearGlobalOverride() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get canCreateMerch => $_getBF(2);
  @$pb.TagNumber(3)
  set canCreateMerch($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasCanCreateMerch() => $_has(2);
  @$pb.TagNumber(3)
  void clearCanCreateMerch() => $_clearField(3);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
