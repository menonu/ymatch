// This is a generated file - do not edit.
//
// Generated from models.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports
// ignore_for_file: unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use userDescriptor instead')
const User$json = {
  '1': 'User',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 5, '10': 'id'},
    {'1': 'username', '3': 2, '4': 1, '5': 9, '10': 'username'},
    {'1': 'uuid', '3': 3, '4': 1, '5': 9, '9': 0, '10': 'uuid', '17': true},
    {
      '1': 'device_token',
      '3': 4,
      '4': 1,
      '5': 9,
      '9': 1,
      '10': 'deviceToken',
      '17': true
    },
    {
      '1': 'created_at',
      '3': 5,
      '4': 1,
      '5': 9,
      '9': 2,
      '10': 'createdAt',
      '17': true
    },
    {'1': 'role', '3': 6, '4': 1, '5': 9, '9': 3, '10': 'role', '17': true},
    {
      '1': 'is_banned',
      '3': 7,
      '4': 1,
      '5': 8,
      '9': 4,
      '10': 'isBanned',
      '17': true
    },
    {
      '1': 'ban_reason',
      '3': 8,
      '4': 1,
      '5': 9,
      '9': 5,
      '10': 'banReason',
      '17': true
    },
    {
      '1': 'banned_until',
      '3': 9,
      '4': 1,
      '5': 9,
      '9': 6,
      '10': 'bannedUntil',
      '17': true
    },
  ],
  '8': [
    {'1': '_uuid'},
    {'1': '_device_token'},
    {'1': '_created_at'},
    {'1': '_role'},
    {'1': '_is_banned'},
    {'1': '_ban_reason'},
    {'1': '_banned_until'},
  ],
};

/// Descriptor for `User`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List userDescriptor = $convert.base64Decode(
    'CgRVc2VyEg4KAmlkGAEgASgFUgJpZBIaCgh1c2VybmFtZRgCIAEoCVIIdXNlcm5hbWUSFwoEdX'
    'VpZBgDIAEoCUgAUgR1dWlkiAEBEiYKDGRldmljZV90b2tlbhgEIAEoCUgBUgtkZXZpY2VUb2tl'
    'bogBARIiCgpjcmVhdGVkX2F0GAUgASgJSAJSCWNyZWF0ZWRBdIgBARIXCgRyb2xlGAYgASgJSA'
    'NSBHJvbGWIAQESIAoJaXNfYmFubmVkGAcgASgISARSCGlzQmFubmVkiAEBEiIKCmJhbl9yZWFz'
    'b24YCCABKAlIBVIJYmFuUmVhc29uiAEBEiYKDGJhbm5lZF91bnRpbBgJIAEoCUgGUgtiYW5uZW'
    'RVbnRpbIgBAUIHCgVfdXVpZEIPCg1fZGV2aWNlX3Rva2VuQg0KC19jcmVhdGVkX2F0QgcKBV9y'
    'b2xlQgwKCl9pc19iYW5uZWRCDQoLX2Jhbl9yZWFzb25CDwoNX2Jhbm5lZF91bnRpbA==');

@$core.Deprecated('Use eventDescriptor instead')
const Event$json = {
  '1': 'Event',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 5, '10': 'id'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
    {
      '1': 'creator_id',
      '3': 3,
      '4': 1,
      '5': 5,
      '9': 0,
      '10': 'creatorId',
      '17': true
    },
    {
      '1': 'created_at',
      '3': 4,
      '4': 1,
      '5': 9,
      '9': 1,
      '10': 'createdAt',
      '17': true
    },
    {
      '1': 'unique_views',
      '3': 5,
      '4': 1,
      '5': 5,
      '9': 2,
      '10': 'uniqueViews',
      '17': true
    },
    {
      '1': 'active_participants',
      '3': 6,
      '4': 1,
      '5': 5,
      '9': 3,
      '10': 'activeParticipants',
      '17': true
    },
    {
      '1': 'is_favorite',
      '3': 7,
      '4': 1,
      '5': 8,
      '9': 4,
      '10': 'isFavorite',
      '17': true
    },
    {
      '1': 'is_joined',
      '3': 8,
      '4': 1,
      '5': 8,
      '9': 5,
      '10': 'isJoined',
      '17': true
    },
    {'1': 'status', '3': 9, '4': 1, '5': 9, '9': 6, '10': 'status', '17': true},
  ],
  '8': [
    {'1': '_creator_id'},
    {'1': '_created_at'},
    {'1': '_unique_views'},
    {'1': '_active_participants'},
    {'1': '_is_favorite'},
    {'1': '_is_joined'},
    {'1': '_status'},
  ],
};

/// Descriptor for `Event`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List eventDescriptor = $convert.base64Decode(
    'CgVFdmVudBIOCgJpZBgBIAEoBVICaWQSEgoEbmFtZRgCIAEoCVIEbmFtZRIiCgpjcmVhdG9yX2'
    'lkGAMgASgFSABSCWNyZWF0b3JJZIgBARIiCgpjcmVhdGVkX2F0GAQgASgJSAFSCWNyZWF0ZWRB'
    'dIgBARImCgx1bmlxdWVfdmlld3MYBSABKAVIAlILdW5pcXVlVmlld3OIAQESNAoTYWN0aXZlX3'
    'BhcnRpY2lwYW50cxgGIAEoBUgDUhJhY3RpdmVQYXJ0aWNpcGFudHOIAQESJAoLaXNfZmF2b3Jp'
    'dGUYByABKAhIBFIKaXNGYXZvcml0ZYgBARIgCglpc19qb2luZWQYCCABKAhIBVIIaXNKb2luZW'
    'SIAQESGwoGc3RhdHVzGAkgASgJSAZSBnN0YXR1c4gBAUINCgtfY3JlYXRvcl9pZEINCgtfY3Jl'
    'YXRlZF9hdEIPCg1fdW5pcXVlX3ZpZXdzQhYKFF9hY3RpdmVfcGFydGljaXBhbnRzQg4KDF9pc1'
    '9mYXZvcml0ZUIMCgpfaXNfam9pbmVkQgkKB19zdGF0dXM=');

@$core.Deprecated('Use favoriteGroupDescriptor instead')
const FavoriteGroup$json = {
  '1': 'FavoriteGroup',
  '2': [
    {'1': 'user_id', '3': 1, '4': 1, '5': 5, '10': 'userId'},
    {'1': 'event_id', '3': 2, '4': 1, '5': 5, '10': 'eventId'},
    {'1': 'group_name', '3': 3, '4': 1, '5': 9, '10': 'groupName'},
    {
      '1': 'event_name',
      '3': 4,
      '4': 1,
      '5': 9,
      '9': 0,
      '10': 'eventName',
      '17': true
    },
  ],
  '8': [
    {'1': '_event_name'},
  ],
};

/// Descriptor for `FavoriteGroup`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List favoriteGroupDescriptor = $convert.base64Decode(
    'Cg1GYXZvcml0ZUdyb3VwEhcKB3VzZXJfaWQYASABKAVSBnVzZXJJZBIZCghldmVudF9pZBgCIA'
    'EoBVIHZXZlbnRJZBIdCgpncm91cF9uYW1lGAMgASgJUglncm91cE5hbWUSIgoKZXZlbnRfbmFt'
    'ZRgEIAEoCUgAUglldmVudE5hbWWIAQFCDQoLX2V2ZW50X25hbWU=');

@$core.Deprecated('Use merchandiseDescriptor instead')
const Merchandise$json = {
  '1': 'Merchandise',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 5, '10': 'id'},
    {'1': 'event_id', '3': 2, '4': 1, '5': 5, '10': 'eventId'},
    {'1': 'name', '3': 3, '4': 1, '5': 9, '10': 'name'},
    {
      '1': 'photo_url',
      '3': 4,
      '4': 1,
      '5': 9,
      '9': 0,
      '10': 'photoUrl',
      '17': true
    },
    {
      '1': 'group_name',
      '3': 5,
      '4': 1,
      '5': 9,
      '9': 1,
      '10': 'groupName',
      '17': true
    },
    {'1': 'status', '3': 7, '4': 1, '5': 9, '9': 2, '10': 'status', '17': true},
    {
      '1': 'is_deleted',
      '3': 8,
      '4': 1,
      '5': 8,
      '9': 3,
      '10': 'isDeleted',
      '17': true
    },
    {
      '1': 'trade_enabled',
      '3': 9,
      '4': 1,
      '5': 8,
      '9': 4,
      '10': 'tradeEnabled',
      '17': true
    },
    {
      '1': 'creator_id',
      '3': 10,
      '4': 1,
      '5': 5,
      '9': 5,
      '10': 'creatorId',
      '17': true
    },
    {
      '1': 'group_description',
      '3': 11,
      '4': 1,
      '5': 9,
      '9': 6,
      '10': 'groupDescription',
      '17': true
    },
  ],
  '8': [
    {'1': '_photo_url'},
    {'1': '_group_name'},
    {'1': '_status'},
    {'1': '_is_deleted'},
    {'1': '_trade_enabled'},
    {'1': '_creator_id'},
    {'1': '_group_description'},
  ],
};

/// Descriptor for `Merchandise`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List merchandiseDescriptor = $convert.base64Decode(
    'CgtNZXJjaGFuZGlzZRIOCgJpZBgBIAEoBVICaWQSGQoIZXZlbnRfaWQYAiABKAVSB2V2ZW50SW'
    'QSEgoEbmFtZRgDIAEoCVIEbmFtZRIgCglwaG90b191cmwYBCABKAlIAFIIcGhvdG9VcmyIAQES'
    'IgoKZ3JvdXBfbmFtZRgFIAEoCUgBUglncm91cE5hbWWIAQESGwoGc3RhdHVzGAcgASgJSAJSBn'
    'N0YXR1c4gBARIiCgppc19kZWxldGVkGAggASgISANSCWlzRGVsZXRlZIgBARIoCg10cmFkZV9l'
    'bmFibGVkGAkgASgISARSDHRyYWRlRW5hYmxlZIgBARIiCgpjcmVhdG9yX2lkGAogASgFSAVSCW'
    'NyZWF0b3JJZIgBARIwChFncm91cF9kZXNjcmlwdGlvbhgLIAEoCUgGUhBncm91cERlc2NyaXB0'
    'aW9uiAEBQgwKCl9waG90b191cmxCDQoLX2dyb3VwX25hbWVCCQoHX3N0YXR1c0INCgtfaXNfZG'
    'VsZXRlZEIQCg5fdHJhZGVfZW5hYmxlZEINCgtfY3JlYXRvcl9pZEIUChJfZ3JvdXBfZGVzY3Jp'
    'cHRpb24=');

@$core.Deprecated('Use merchandiseGroupDescriptor instead')
const MerchandiseGroup$json = {
  '1': 'MerchandiseGroup',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 5, '10': 'id'},
    {'1': 'event_id', '3': 2, '4': 1, '5': 5, '10': 'eventId'},
    {'1': 'group_name', '3': 3, '4': 1, '5': 9, '10': 'groupName'},
    {
      '1': 'description',
      '3': 4,
      '4': 1,
      '5': 9,
      '9': 0,
      '10': 'description',
      '17': true
    },
    {
      '1': 'created_by',
      '3': 5,
      '4': 1,
      '5': 5,
      '9': 1,
      '10': 'createdBy',
      '17': true
    },
    {
      '1': 'created_at',
      '3': 6,
      '4': 1,
      '5': 9,
      '9': 2,
      '10': 'createdAt',
      '17': true
    },
    {
      '1': 'updated_at',
      '3': 7,
      '4': 1,
      '5': 9,
      '9': 3,
      '10': 'updatedAt',
      '17': true
    },
  ],
  '8': [
    {'1': '_description'},
    {'1': '_created_by'},
    {'1': '_created_at'},
    {'1': '_updated_at'},
  ],
};

/// Descriptor for `MerchandiseGroup`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List merchandiseGroupDescriptor = $convert.base64Decode(
    'ChBNZXJjaGFuZGlzZUdyb3VwEg4KAmlkGAEgASgFUgJpZBIZCghldmVudF9pZBgCIAEoBVIHZX'
    'ZlbnRJZBIdCgpncm91cF9uYW1lGAMgASgJUglncm91cE5hbWUSJQoLZGVzY3JpcHRpb24YBCAB'
    'KAlIAFILZGVzY3JpcHRpb26IAQESIgoKY3JlYXRlZF9ieRgFIAEoBUgBUgljcmVhdGVkQnmIAQ'
    'ESIgoKY3JlYXRlZF9hdBgGIAEoCUgCUgljcmVhdGVkQXSIAQESIgoKdXBkYXRlZF9hdBgHIAEo'
    'CUgDUgl1cGRhdGVkQXSIAQFCDgoMX2Rlc2NyaXB0aW9uQg0KC19jcmVhdGVkX2J5Qg0KC19jcm'
    'VhdGVkX2F0Qg0KC191cGRhdGVkX2F0');

@$core.Deprecated('Use inventoryItemDescriptor instead')
const InventoryItem$json = {
  '1': 'InventoryItem',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 5, '10': 'id'},
    {'1': 'user_id', '3': 2, '4': 1, '5': 5, '10': 'userId'},
    {'1': 'merch_id', '3': 3, '4': 1, '5': 5, '10': 'merchId'},
    {'1': 'status', '3': 4, '4': 1, '5': 9, '10': 'status'},
    {'1': 'quantity', '3': 5, '4': 1, '5': 5, '10': 'quantity'},
    {
      '1': 'merch_name',
      '3': 6,
      '4': 1,
      '5': 9,
      '9': 0,
      '10': 'merchName',
      '17': true
    },
    {
      '1': 'photo_url',
      '3': 7,
      '4': 1,
      '5': 9,
      '9': 1,
      '10': 'photoUrl',
      '17': true
    },
    {
      '1': 'group_name',
      '3': 8,
      '4': 1,
      '5': 9,
      '9': 2,
      '10': 'groupName',
      '17': true
    },
  ],
  '8': [
    {'1': '_merch_name'},
    {'1': '_photo_url'},
    {'1': '_group_name'},
  ],
};

/// Descriptor for `InventoryItem`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List inventoryItemDescriptor = $convert.base64Decode(
    'Cg1JbnZlbnRvcnlJdGVtEg4KAmlkGAEgASgFUgJpZBIXCgd1c2VyX2lkGAIgASgFUgZ1c2VySW'
    'QSGQoIbWVyY2hfaWQYAyABKAVSB21lcmNoSWQSFgoGc3RhdHVzGAQgASgJUgZzdGF0dXMSGgoI'
    'cXVhbnRpdHkYBSABKAVSCHF1YW50aXR5EiIKCm1lcmNoX25hbWUYBiABKAlIAFIJbWVyY2hOYW'
    '1liAEBEiAKCXBob3RvX3VybBgHIAEoCUgBUghwaG90b1VybIgBARIiCgpncm91cF9uYW1lGAgg'
    'ASgJSAJSCWdyb3VwTmFtZYgBAUINCgtfbWVyY2hfbmFtZUIMCgpfcGhvdG9fdXJsQg0KC19ncm'
    '91cF9uYW1l');

@$core.Deprecated('Use tradeMatchDescriptor instead')
const TradeMatch$json = {
  '1': 'TradeMatch',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 5, '10': 'id'},
    {'1': 'user1_id', '3': 2, '4': 1, '5': 5, '10': 'user1Id'},
    {'1': 'user2_id', '3': 3, '4': 1, '5': 5, '10': 'user2Id'},
    {'1': 'status', '3': 4, '4': 1, '5': 9, '10': 'status'},
    {
      '1': 'created_at',
      '3': 5,
      '4': 1,
      '5': 9,
      '9': 0,
      '10': 'createdAt',
      '17': true
    },
    {
      '1': 'other_user',
      '3': 6,
      '4': 1,
      '5': 11,
      '6': '.ymatch.User',
      '9': 1,
      '10': 'otherUser',
      '17': true
    },
    {
      '1': 'user_haves',
      '3': 7,
      '4': 3,
      '5': 11,
      '6': '.ymatch.InventoryItem',
      '10': 'userHaves'
    },
    {
      '1': 'user_wants',
      '3': 8,
      '4': 3,
      '5': 11,
      '6': '.ymatch.InventoryItem',
      '10': 'userWants'
    },
    {
      '1': 'offered_by',
      '3': 9,
      '4': 1,
      '5': 5,
      '9': 2,
      '10': 'offeredBy',
      '17': true
    },
    {
      '1': 'selected_items',
      '3': 10,
      '4': 3,
      '5': 11,
      '6': '.ymatch.MatchItem',
      '10': 'selectedItems'
    },
    {
      '1': 'inventory_applied',
      '3': 11,
      '4': 1,
      '5': 8,
      '10': 'inventoryApplied'
    },
  ],
  '8': [
    {'1': '_created_at'},
    {'1': '_other_user'},
    {'1': '_offered_by'},
  ],
};

/// Descriptor for `TradeMatch`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List tradeMatchDescriptor = $convert.base64Decode(
    'CgpUcmFkZU1hdGNoEg4KAmlkGAEgASgFUgJpZBIZCgh1c2VyMV9pZBgCIAEoBVIHdXNlcjFJZB'
    'IZCgh1c2VyMl9pZBgDIAEoBVIHdXNlcjJJZBIWCgZzdGF0dXMYBCABKAlSBnN0YXR1cxIiCgpj'
    'cmVhdGVkX2F0GAUgASgJSABSCWNyZWF0ZWRBdIgBARIwCgpvdGhlcl91c2VyGAYgASgLMgwueW'
    '1hdGNoLlVzZXJIAVIJb3RoZXJVc2VyiAEBEjQKCnVzZXJfaGF2ZXMYByADKAsyFS55bWF0Y2gu'
    'SW52ZW50b3J5SXRlbVIJdXNlckhhdmVzEjQKCnVzZXJfd2FudHMYCCADKAsyFS55bWF0Y2guSW'
    '52ZW50b3J5SXRlbVIJdXNlcldhbnRzEiIKCm9mZmVyZWRfYnkYCSABKAVIAlIJb2ZmZXJlZEJ5'
    'iAEBEjgKDnNlbGVjdGVkX2l0ZW1zGAogAygLMhEueW1hdGNoLk1hdGNoSXRlbVINc2VsZWN0ZW'
    'RJdGVtcxIrChFpbnZlbnRvcnlfYXBwbGllZBgLIAEoCFIQaW52ZW50b3J5QXBwbGllZEINCgtf'
    'Y3JlYXRlZF9hdEINCgtfb3RoZXJfdXNlckINCgtfb2ZmZXJlZF9ieQ==');

@$core.Deprecated('Use matchItemDescriptor instead')
const MatchItem$json = {
  '1': 'MatchItem',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 5, '10': 'id'},
    {'1': 'match_id', '3': 2, '4': 1, '5': 5, '10': 'matchId'},
    {'1': 'merch_id', '3': 3, '4': 1, '5': 5, '10': 'merchId'},
    {'1': 'giver_user_id', '3': 4, '4': 1, '5': 5, '10': 'giverUserId'},
    {'1': 'quantity', '3': 6, '4': 1, '5': 5, '10': 'quantity'},
    {
      '1': 'merch_name',
      '3': 7,
      '4': 1,
      '5': 9,
      '9': 0,
      '10': 'merchName',
      '17': true
    },
    {
      '1': 'photo_url',
      '3': 8,
      '4': 1,
      '5': 9,
      '9': 1,
      '10': 'photoUrl',
      '17': true
    },
  ],
  '8': [
    {'1': '_merch_name'},
    {'1': '_photo_url'},
  ],
  '9': [
    {'1': 5, '2': 6},
  ],
};

/// Descriptor for `MatchItem`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List matchItemDescriptor = $convert.base64Decode(
    'CglNYXRjaEl0ZW0SDgoCaWQYASABKAVSAmlkEhkKCG1hdGNoX2lkGAIgASgFUgdtYXRjaElkEh'
    'kKCG1lcmNoX2lkGAMgASgFUgdtZXJjaElkEiIKDWdpdmVyX3VzZXJfaWQYBCABKAVSC2dpdmVy'
    'VXNlcklkEhoKCHF1YW50aXR5GAYgASgFUghxdWFudGl0eRIiCgptZXJjaF9uYW1lGAcgASgJSA'
    'BSCW1lcmNoTmFtZYgBARIgCglwaG90b191cmwYCCABKAlIAVIIcGhvdG9VcmyIAQFCDQoLX21l'
    'cmNoX25hbWVCDAoKX3Bob3RvX3VybEoECAUQBg==');

@$core.Deprecated('Use guestLoginRequestDescriptor instead')
const GuestLoginRequest$json = {
  '1': 'GuestLoginRequest',
  '2': [
    {'1': 'uuid', '3': 1, '4': 1, '5': 9, '10': 'uuid'},
    {
      '1': 'device_token',
      '3': 2,
      '4': 1,
      '5': 9,
      '9': 0,
      '10': 'deviceToken',
      '17': true
    },
  ],
  '8': [
    {'1': '_device_token'},
  ],
};

/// Descriptor for `GuestLoginRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List guestLoginRequestDescriptor = $convert.base64Decode(
    'ChFHdWVzdExvZ2luUmVxdWVzdBISCgR1dWlkGAEgASgJUgR1dWlkEiYKDGRldmljZV90b2tlbh'
    'gCIAEoCUgAUgtkZXZpY2VUb2tlbogBAUIPCg1fZGV2aWNlX3Rva2Vu');

@$core.Deprecated('Use loginRequestDescriptor instead')
const LoginRequest$json = {
  '1': 'LoginRequest',
  '2': [
    {'1': 'username', '3': 1, '4': 1, '5': 9, '10': 'username'},
    {'1': 'password', '3': 2, '4': 1, '5': 9, '10': 'password'},
  ],
};

/// Descriptor for `LoginRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List loginRequestDescriptor = $convert.base64Decode(
    'CgxMb2dpblJlcXVlc3QSGgoIdXNlcm5hbWUYASABKAlSCHVzZXJuYW1lEhoKCHBhc3N3b3JkGA'
    'IgASgJUghwYXNzd29yZA==');

@$core.Deprecated('Use createUserRequestDescriptor instead')
const CreateUserRequest$json = {
  '1': 'CreateUserRequest',
  '2': [
    {'1': 'username', '3': 1, '4': 1, '5': 9, '10': 'username'},
    {'1': 'password', '3': 2, '4': 1, '5': 9, '10': 'password'},
    {
      '1': 'device_token',
      '3': 3,
      '4': 1,
      '5': 9,
      '9': 0,
      '10': 'deviceToken',
      '17': true
    },
  ],
  '8': [
    {'1': '_device_token'},
  ],
};

/// Descriptor for `CreateUserRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List createUserRequestDescriptor = $convert.base64Decode(
    'ChFDcmVhdGVVc2VyUmVxdWVzdBIaCgh1c2VybmFtZRgBIAEoCVIIdXNlcm5hbWUSGgoIcGFzc3'
    'dvcmQYAiABKAlSCHBhc3N3b3JkEiYKDGRldmljZV90b2tlbhgDIAEoCUgAUgtkZXZpY2VUb2tl'
    'bogBAUIPCg1fZGV2aWNlX3Rva2Vu');

@$core.Deprecated('Use createEventRequestDescriptor instead')
const CreateEventRequest$json = {
  '1': 'CreateEventRequest',
  '2': [
    {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
    {'1': 'creator_id', '3': 2, '4': 1, '5': 5, '10': 'creatorId'},
    {'1': 'status', '3': 3, '4': 1, '5': 9, '9': 0, '10': 'status', '17': true},
  ],
  '8': [
    {'1': '_status'},
  ],
};

/// Descriptor for `CreateEventRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List createEventRequestDescriptor = $convert.base64Decode(
    'ChJDcmVhdGVFdmVudFJlcXVlc3QSEgoEbmFtZRgBIAEoCVIEbmFtZRIdCgpjcmVhdG9yX2lkGA'
    'IgASgFUgljcmVhdG9ySWQSGwoGc3RhdHVzGAMgASgJSABSBnN0YXR1c4gBAUIJCgdfc3RhdHVz');

@$core.Deprecated('Use updateEventRequestDescriptor instead')
const UpdateEventRequest$json = {
  '1': 'UpdateEventRequest',
  '2': [
    {'1': 'user_id', '3': 1, '4': 1, '5': 5, '10': 'userId'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '9': 0, '10': 'name', '17': true},
  ],
  '8': [
    {'1': '_name'},
  ],
};

/// Descriptor for `UpdateEventRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List updateEventRequestDescriptor = $convert.base64Decode(
    'ChJVcGRhdGVFdmVudFJlcXVlc3QSFwoHdXNlcl9pZBgBIAEoBVIGdXNlcklkEhcKBG5hbWUYAi'
    'ABKAlIAFIEbmFtZYgBAUIHCgVfbmFtZQ==');

@$core.Deprecated('Use toggleFavoriteRequestDescriptor instead')
const ToggleFavoriteRequest$json = {
  '1': 'ToggleFavoriteRequest',
  '2': [
    {'1': 'user_id', '3': 1, '4': 1, '5': 5, '10': 'userId'},
    {'1': 'is_favorite', '3': 2, '4': 1, '5': 8, '10': 'isFavorite'},
  ],
};

/// Descriptor for `ToggleFavoriteRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List toggleFavoriteRequestDescriptor = $convert.base64Decode(
    'ChVUb2dnbGVGYXZvcml0ZVJlcXVlc3QSFwoHdXNlcl9pZBgBIAEoBVIGdXNlcklkEh8KC2lzX2'
    'Zhdm9yaXRlGAIgASgIUgppc0Zhdm9yaXRl');

@$core.Deprecated('Use toggleFavoriteGroupRequestDescriptor instead')
const ToggleFavoriteGroupRequest$json = {
  '1': 'ToggleFavoriteGroupRequest',
  '2': [
    {'1': 'user_id', '3': 1, '4': 1, '5': 5, '10': 'userId'},
    {'1': 'group_name', '3': 2, '4': 1, '5': 9, '10': 'groupName'},
    {'1': 'is_favorite', '3': 3, '4': 1, '5': 8, '10': 'isFavorite'},
  ],
};

/// Descriptor for `ToggleFavoriteGroupRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List toggleFavoriteGroupRequestDescriptor =
    $convert.base64Decode(
        'ChpUb2dnbGVGYXZvcml0ZUdyb3VwUmVxdWVzdBIXCgd1c2VyX2lkGAEgASgFUgZ1c2VySWQSHQ'
        'oKZ3JvdXBfbmFtZRgCIAEoCVIJZ3JvdXBOYW1lEh8KC2lzX2Zhdm9yaXRlGAMgASgIUgppc0Zh'
        'dm9yaXRl');

@$core.Deprecated('Use updateInventoryRequestDescriptor instead')
const UpdateInventoryRequest$json = {
  '1': 'UpdateInventoryRequest',
  '2': [
    {'1': 'user_id', '3': 1, '4': 1, '5': 5, '10': 'userId'},
    {'1': 'merch_id', '3': 2, '4': 1, '5': 5, '10': 'merchId'},
    {'1': 'status', '3': 3, '4': 1, '5': 9, '10': 'status'},
    {'1': 'quantity', '3': 4, '4': 1, '5': 5, '10': 'quantity'},
  ],
};

/// Descriptor for `UpdateInventoryRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List updateInventoryRequestDescriptor = $convert.base64Decode(
    'ChZVcGRhdGVJbnZlbnRvcnlSZXF1ZXN0EhcKB3VzZXJfaWQYASABKAVSBnVzZXJJZBIZCghtZX'
    'JjaF9pZBgCIAEoBVIHbWVyY2hJZBIWCgZzdGF0dXMYAyABKAlSBnN0YXR1cxIaCghxdWFudGl0'
    'eRgEIAEoBVIIcXVhbnRpdHk=');

@$core.Deprecated('Use createMerchRequestDescriptor instead')
const CreateMerchRequest$json = {
  '1': 'CreateMerchRequest',
  '2': [
    {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
    {
      '1': 'photo_url',
      '3': 2,
      '4': 1,
      '5': 9,
      '9': 0,
      '10': 'photoUrl',
      '17': true
    },
    {
      '1': 'group_name',
      '3': 3,
      '4': 1,
      '5': 9,
      '9': 1,
      '10': 'groupName',
      '17': true
    },
    {
      '1': 'creator_id',
      '3': 4,
      '4': 1,
      '5': 5,
      '9': 2,
      '10': 'creatorId',
      '17': true
    },
    {'1': 'status', '3': 5, '4': 1, '5': 9, '9': 3, '10': 'status', '17': true},
  ],
  '8': [
    {'1': '_photo_url'},
    {'1': '_group_name'},
    {'1': '_creator_id'},
    {'1': '_status'},
  ],
};

/// Descriptor for `CreateMerchRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List createMerchRequestDescriptor = $convert.base64Decode(
    'ChJDcmVhdGVNZXJjaFJlcXVlc3QSEgoEbmFtZRgBIAEoCVIEbmFtZRIgCglwaG90b191cmwYAi'
    'ABKAlIAFIIcGhvdG9VcmyIAQESIgoKZ3JvdXBfbmFtZRgDIAEoCUgBUglncm91cE5hbWWIAQES'
    'IgoKY3JlYXRvcl9pZBgEIAEoBUgCUgljcmVhdG9ySWSIAQESGwoGc3RhdHVzGAUgASgJSANSBn'
    'N0YXR1c4gBAUIMCgpfcGhvdG9fdXJsQg0KC19ncm91cF9uYW1lQg0KC19jcmVhdG9yX2lkQgkK'
    'B19zdGF0dXM=');

@$core.Deprecated('Use updateMerchRequestDescriptor instead')
const UpdateMerchRequest$json = {
  '1': 'UpdateMerchRequest',
  '2': [
    {'1': 'user_id', '3': 1, '4': 1, '5': 5, '10': 'userId'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '9': 0, '10': 'name', '17': true},
    {
      '1': 'photo_url',
      '3': 3,
      '4': 1,
      '5': 9,
      '9': 1,
      '10': 'photoUrl',
      '17': true
    },
    {
      '1': 'group_name',
      '3': 4,
      '4': 1,
      '5': 9,
      '9': 2,
      '10': 'groupName',
      '17': true
    },
  ],
  '8': [
    {'1': '_name'},
    {'1': '_photo_url'},
    {'1': '_group_name'},
  ],
};

/// Descriptor for `UpdateMerchRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List updateMerchRequestDescriptor = $convert.base64Decode(
    'ChJVcGRhdGVNZXJjaFJlcXVlc3QSFwoHdXNlcl9pZBgBIAEoBVIGdXNlcklkEhcKBG5hbWUYAi'
    'ABKAlIAFIEbmFtZYgBARIgCglwaG90b191cmwYAyABKAlIAVIIcGhvdG9VcmyIAQESIgoKZ3Jv'
    'dXBfbmFtZRgEIAEoCUgCUglncm91cE5hbWWIAQFCBwoFX25hbWVCDAoKX3Bob3RvX3VybEINCg'
    'tfZ3JvdXBfbmFtZQ==');

@$core.Deprecated('Use updateMatchStatusRequestDescriptor instead')
const UpdateMatchStatusRequest$json = {
  '1': 'UpdateMatchStatusRequest',
  '2': [
    {'1': 'status', '3': 1, '4': 1, '5': 9, '10': 'status'},
    {'1': 'user_id', '3': 2, '4': 1, '5': 5, '10': 'userId'},
  ],
};

/// Descriptor for `UpdateMatchStatusRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List updateMatchStatusRequestDescriptor =
    $convert.base64Decode(
        'ChhVcGRhdGVNYXRjaFN0YXR1c1JlcXVlc3QSFgoGc3RhdHVzGAEgASgJUgZzdGF0dXMSFwoHdX'
        'Nlcl9pZBgCIAEoBVIGdXNlcklk');

@$core.Deprecated('Use offerTradeRequestDescriptor instead')
const OfferTradeRequest$json = {
  '1': 'OfferTradeRequest',
  '2': [
    {'1': 'user_id', '3': 1, '4': 1, '5': 5, '10': 'userId'},
    {
      '1': 'items',
      '3': 2,
      '4': 3,
      '5': 11,
      '6': '.ymatch.OfferItem',
      '10': 'items'
    },
  ],
};

/// Descriptor for `OfferTradeRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List offerTradeRequestDescriptor = $convert.base64Decode(
    'ChFPZmZlclRyYWRlUmVxdWVzdBIXCgd1c2VyX2lkGAEgASgFUgZ1c2VySWQSJwoFaXRlbXMYAi'
    'ADKAsyES55bWF0Y2guT2ZmZXJJdGVtUgVpdGVtcw==');

@$core.Deprecated('Use offerItemDescriptor instead')
const OfferItem$json = {
  '1': 'OfferItem',
  '2': [
    {'1': 'merch_id', '3': 1, '4': 1, '5': 5, '10': 'merchId'},
    {'1': 'giver_user_id', '3': 2, '4': 1, '5': 5, '10': 'giverUserId'},
    {'1': 'quantity', '3': 3, '4': 1, '5': 5, '10': 'quantity'},
  ],
};

/// Descriptor for `OfferItem`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List offerItemDescriptor = $convert.base64Decode(
    'CglPZmZlckl0ZW0SGQoIbWVyY2hfaWQYASABKAVSB21lcmNoSWQSIgoNZ2l2ZXJfdXNlcl9pZB'
    'gCIAEoBVILZ2l2ZXJVc2VySWQSGgoIcXVhbnRpdHkYAyABKAVSCHF1YW50aXR5');

@$core.Deprecated('Use applyInventoryRequestDescriptor instead')
const ApplyInventoryRequest$json = {
  '1': 'ApplyInventoryRequest',
  '2': [
    {'1': 'user_id', '3': 1, '4': 1, '5': 5, '10': 'userId'},
  ],
};

/// Descriptor for `ApplyInventoryRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List applyInventoryRequestDescriptor =
    $convert.base64Decode(
        'ChVBcHBseUludmVudG9yeVJlcXVlc3QSFwoHdXNlcl9pZBgBIAEoBVIGdXNlcklk');

@$core.Deprecated('Use notificationCountsDescriptor instead')
const NotificationCounts$json = {
  '1': 'NotificationCounts',
  '2': [
    {'1': 'pending_matches', '3': 1, '4': 1, '5': 5, '10': 'pendingMatches'},
    {'1': 'offers_in', '3': 2, '4': 1, '5': 5, '10': 'offersIn'},
    {'1': 'accepted', '3': 3, '4': 1, '5': 5, '10': 'accepted'},
    {'1': 'unread_messages', '3': 4, '4': 1, '5': 5, '10': 'unreadMessages'},
    {'1': 'total', '3': 5, '4': 1, '5': 5, '10': 'total'},
  ],
};

/// Descriptor for `NotificationCounts`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List notificationCountsDescriptor = $convert.base64Decode(
    'ChJOb3RpZmljYXRpb25Db3VudHMSJwoPcGVuZGluZ19tYXRjaGVzGAEgASgFUg5wZW5kaW5nTW'
    'F0Y2hlcxIbCglvZmZlcnNfaW4YAiABKAVSCG9mZmVyc0luEhoKCGFjY2VwdGVkGAMgASgFUghh'
    'Y2NlcHRlZBInCg91bnJlYWRfbWVzc2FnZXMYBCABKAVSDnVucmVhZE1lc3NhZ2VzEhQKBXRvdG'
    'FsGAUgASgFUgV0b3RhbA==');

@$core.Deprecated('Use messageDescriptor instead')
const Message$json = {
  '1': 'Message',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 5, '10': 'id'},
    {'1': 'match_id', '3': 2, '4': 1, '5': 5, '10': 'matchId'},
    {'1': 'sender_id', '3': 3, '4': 1, '5': 5, '10': 'senderId'},
    {'1': 'content', '3': 4, '4': 1, '5': 9, '10': 'content'},
    {
      '1': 'created_at',
      '3': 5,
      '4': 1,
      '5': 9,
      '9': 0,
      '10': 'createdAt',
      '17': true
    },
    {
      '1': 'message_type',
      '3': 6,
      '4': 1,
      '5': 9,
      '9': 1,
      '10': 'messageType',
      '17': true
    },
    {
      '1': 'latitude',
      '3': 7,
      '4': 1,
      '5': 1,
      '9': 2,
      '10': 'latitude',
      '17': true
    },
    {
      '1': 'longitude',
      '3': 8,
      '4': 1,
      '5': 1,
      '9': 3,
      '10': 'longitude',
      '17': true
    },
  ],
  '8': [
    {'1': '_created_at'},
    {'1': '_message_type'},
    {'1': '_latitude'},
    {'1': '_longitude'},
  ],
};

/// Descriptor for `Message`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List messageDescriptor = $convert.base64Decode(
    'CgdNZXNzYWdlEg4KAmlkGAEgASgFUgJpZBIZCghtYXRjaF9pZBgCIAEoBVIHbWF0Y2hJZBIbCg'
    'lzZW5kZXJfaWQYAyABKAVSCHNlbmRlcklkEhgKB2NvbnRlbnQYBCABKAlSB2NvbnRlbnQSIgoK'
    'Y3JlYXRlZF9hdBgFIAEoCUgAUgljcmVhdGVkQXSIAQESJgoMbWVzc2FnZV90eXBlGAYgASgJSA'
    'FSC21lc3NhZ2VUeXBliAEBEh8KCGxhdGl0dWRlGAcgASgBSAJSCGxhdGl0dWRliAEBEiEKCWxv'
    'bmdpdHVkZRgIIAEoAUgDUglsb25naXR1ZGWIAQFCDQoLX2NyZWF0ZWRfYXRCDwoNX21lc3NhZ2'
    'VfdHlwZUILCglfbGF0aXR1ZGVCDAoKX2xvbmdpdHVkZQ==');

@$core.Deprecated('Use sendMessageRequestDescriptor instead')
const SendMessageRequest$json = {
  '1': 'SendMessageRequest',
  '2': [
    {'1': 'match_id', '3': 1, '4': 1, '5': 5, '10': 'matchId'},
    {'1': 'sender_id', '3': 2, '4': 1, '5': 5, '10': 'senderId'},
    {'1': 'content', '3': 3, '4': 1, '5': 9, '10': 'content'},
    {
      '1': 'message_type',
      '3': 4,
      '4': 1,
      '5': 9,
      '9': 0,
      '10': 'messageType',
      '17': true
    },
    {
      '1': 'latitude',
      '3': 5,
      '4': 1,
      '5': 1,
      '9': 1,
      '10': 'latitude',
      '17': true
    },
    {
      '1': 'longitude',
      '3': 6,
      '4': 1,
      '5': 1,
      '9': 2,
      '10': 'longitude',
      '17': true
    },
  ],
  '8': [
    {'1': '_message_type'},
    {'1': '_latitude'},
    {'1': '_longitude'},
  ],
};

/// Descriptor for `SendMessageRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sendMessageRequestDescriptor = $convert.base64Decode(
    'ChJTZW5kTWVzc2FnZVJlcXVlc3QSGQoIbWF0Y2hfaWQYASABKAVSB21hdGNoSWQSGwoJc2VuZG'
    'VyX2lkGAIgASgFUghzZW5kZXJJZBIYCgdjb250ZW50GAMgASgJUgdjb250ZW50EiYKDG1lc3Nh'
    'Z2VfdHlwZRgEIAEoCUgAUgttZXNzYWdlVHlwZYgBARIfCghsYXRpdHVkZRgFIAEoAUgBUghsYX'
    'RpdHVkZYgBARIhCglsb25naXR1ZGUYBiABKAFIAlIJbG9uZ2l0dWRliAEBQg8KDV9tZXNzYWdl'
    'X3R5cGVCCwoJX2xhdGl0dWRlQgwKCl9sb25naXR1ZGU=');

@$core.Deprecated('Use searchResultDescriptor instead')
const SearchResult$json = {
  '1': 'SearchResult',
  '2': [
    {'1': 'type', '3': 1, '4': 1, '5': 9, '10': 'type'},
    {'1': 'id', '3': 2, '4': 1, '5': 5, '10': 'id'},
    {'1': 'title', '3': 3, '4': 1, '5': 9, '10': 'title'},
    {
      '1': 'subtitle',
      '3': 4,
      '4': 1,
      '5': 9,
      '9': 0,
      '10': 'subtitle',
      '17': true
    },
    {
      '1': 'photo_url',
      '3': 5,
      '4': 1,
      '5': 9,
      '9': 1,
      '10': 'photoUrl',
      '17': true
    },
    {'1': 'event_id', '3': 6, '4': 1, '5': 5, '10': 'eventId'},
  ],
  '8': [
    {'1': '_subtitle'},
    {'1': '_photo_url'},
  ],
};

/// Descriptor for `SearchResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List searchResultDescriptor = $convert.base64Decode(
    'CgxTZWFyY2hSZXN1bHQSEgoEdHlwZRgBIAEoCVIEdHlwZRIOCgJpZBgCIAEoBVICaWQSFAoFdG'
    'l0bGUYAyABKAlSBXRpdGxlEh8KCHN1YnRpdGxlGAQgASgJSABSCHN1YnRpdGxliAEBEiAKCXBo'
    'b3RvX3VybBgFIAEoCUgBUghwaG90b1VybIgBARIZCghldmVudF9pZBgGIAEoBVIHZXZlbnRJZE'
    'ILCglfc3VidGl0bGVCDAoKX3Bob3RvX3VybA==');

@$core.Deprecated('Use banUserRequestDescriptor instead')
const BanUserRequest$json = {
  '1': 'BanUserRequest',
  '2': [
    {'1': 'reason', '3': 1, '4': 1, '5': 9, '9': 0, '10': 'reason', '17': true},
    {
      '1': 'banned_until',
      '3': 2,
      '4': 1,
      '5': 9,
      '9': 1,
      '10': 'bannedUntil',
      '17': true
    },
  ],
  '8': [
    {'1': '_reason'},
    {'1': '_banned_until'},
  ],
};

/// Descriptor for `BanUserRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List banUserRequestDescriptor = $convert.base64Decode(
    'Cg5CYW5Vc2VyUmVxdWVzdBIbCgZyZWFzb24YASABKAlIAFIGcmVhc29uiAEBEiYKDGJhbm5lZF'
    '91bnRpbBgCIAEoCUgBUgtiYW5uZWRVbnRpbIgBAUIJCgdfcmVhc29uQg8KDV9iYW5uZWRfdW50'
    'aWw=');

@$core.Deprecated('Use updateUserRoleRequestDescriptor instead')
const UpdateUserRoleRequest$json = {
  '1': 'UpdateUserRoleRequest',
  '2': [
    {'1': 'role', '3': 1, '4': 1, '5': 9, '10': 'role'},
  ],
};

/// Descriptor for `UpdateUserRoleRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List updateUserRoleRequestDescriptor =
    $convert.base64Decode(
        'ChVVcGRhdGVVc2VyUm9sZVJlcXVlc3QSEgoEcm9sZRgBIAEoCVIEcm9sZQ==');

@$core.Deprecated('Use updateUsernameRequestDescriptor instead')
const UpdateUsernameRequest$json = {
  '1': 'UpdateUsernameRequest',
  '2': [
    {'1': 'user_id', '3': 1, '4': 1, '5': 5, '10': 'userId'},
    {'1': 'username', '3': 2, '4': 1, '5': 9, '10': 'username'},
  ],
};

/// Descriptor for `UpdateUsernameRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List updateUsernameRequestDescriptor = $convert.base64Decode(
    'ChVVcGRhdGVVc2VybmFtZVJlcXVlc3QSFwoHdXNlcl9pZBgBIAEoBVIGdXNlcklkEhoKCHVzZX'
    'JuYW1lGAIgASgJUgh1c2VybmFtZQ==');

@$core.Deprecated('Use userActionRequestDescriptor instead')
const UserActionRequest$json = {
  '1': 'UserActionRequest',
  '2': [
    {'1': 'user_id', '3': 1, '4': 1, '5': 5, '10': 'userId'},
  ],
};

/// Descriptor for `UserActionRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List userActionRequestDescriptor = $convert.base64Decode(
    'ChFVc2VyQWN0aW9uUmVxdWVzdBIXCgd1c2VyX2lkGAEgASgFUgZ1c2VySWQ=');

@$core.Deprecated('Use createGroupRequestDescriptor instead')
const CreateGroupRequest$json = {
  '1': 'CreateGroupRequest',
  '2': [
    {'1': 'event_id', '3': 1, '4': 1, '5': 5, '10': 'eventId'},
    {'1': 'user_id', '3': 2, '4': 1, '5': 5, '10': 'userId'},
    {'1': 'group_name', '3': 3, '4': 1, '5': 9, '10': 'groupName'},
    {
      '1': 'description',
      '3': 4,
      '4': 1,
      '5': 9,
      '9': 0,
      '10': 'description',
      '17': true
    },
  ],
  '8': [
    {'1': '_description'},
  ],
};

/// Descriptor for `CreateGroupRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List createGroupRequestDescriptor = $convert.base64Decode(
    'ChJDcmVhdGVHcm91cFJlcXVlc3QSGQoIZXZlbnRfaWQYASABKAVSB2V2ZW50SWQSFwoHdXNlcl'
    '9pZBgCIAEoBVIGdXNlcklkEh0KCmdyb3VwX25hbWUYAyABKAlSCWdyb3VwTmFtZRIlCgtkZXNj'
    'cmlwdGlvbhgEIAEoCUgAUgtkZXNjcmlwdGlvbogBAUIOCgxfZGVzY3JpcHRpb24=');

@$core.Deprecated('Use updateGroupRequestDescriptor instead')
const UpdateGroupRequest$json = {
  '1': 'UpdateGroupRequest',
  '2': [
    {'1': 'event_id', '3': 1, '4': 1, '5': 5, '10': 'eventId'},
    {'1': 'user_id', '3': 2, '4': 1, '5': 5, '10': 'userId'},
    {'1': 'group_name', '3': 3, '4': 1, '5': 9, '10': 'groupName'},
    {
      '1': 'description',
      '3': 4,
      '4': 1,
      '5': 9,
      '9': 0,
      '10': 'description',
      '17': true
    },
  ],
  '8': [
    {'1': '_description'},
  ],
};

/// Descriptor for `UpdateGroupRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List updateGroupRequestDescriptor = $convert.base64Decode(
    'ChJVcGRhdGVHcm91cFJlcXVlc3QSGQoIZXZlbnRfaWQYASABKAVSB2V2ZW50SWQSFwoHdXNlcl'
    '9pZBgCIAEoBVIGdXNlcklkEh0KCmdyb3VwX25hbWUYAyABKAlSCWdyb3VwTmFtZRIlCgtkZXNj'
    'cmlwdGlvbhgEIAEoCUgAUgtkZXNjcmlwdGlvbogBAUIOCgxfZGVzY3JpcHRpb24=');

@$core.Deprecated('Use listGroupsResponseDescriptor instead')
const ListGroupsResponse$json = {
  '1': 'ListGroupsResponse',
  '2': [
    {
      '1': 'groups',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.ymatch.MerchandiseGroup',
      '10': 'groups'
    },
  ],
};

/// Descriptor for `ListGroupsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listGroupsResponseDescriptor = $convert.base64Decode(
    'ChJMaXN0R3JvdXBzUmVzcG9uc2USMAoGZ3JvdXBzGAEgAygLMhgueW1hdGNoLk1lcmNoYW5kaX'
    'NlR3JvdXBSBmdyb3Vwcw==');
