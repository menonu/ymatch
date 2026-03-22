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
    {'1': 'is_banned', '3': 7, '4': 1, '5': 8, '9': 4, '10': 'isBanned', '17': true},
    {'1': 'ban_reason', '3': 8, '4': 1, '5': 9, '9': 5, '10': 'banReason', '17': true},
    {'1': 'banned_until', '3': 9, '4': 1, '5': 9, '9': 6, '10': 'bannedUntil', '17': true},
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
    'bogBARIiCgpjcmVhdGVkX2F0GAUgASgJSAJSCWNyZWF0ZWRBdIgBAUIHCgVfdXVpZEIPCg1fZG'
    'V2aWNlX3Rva2VuQg0KC19jcmVhdGVkX2F0');

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
    'SIAQFCDQoLX2NyZWF0b3JfaWRCDQoLX2NyZWF0ZWRfYXRCDwoNX3VuaXF1ZV92aWV3c0IWChRf'
    'YWN0aXZlX3BhcnRpY2lwYW50c0IOCgxfaXNfZmF2b3JpdGVCDAoKX2lzX2pvaW5lZA==');

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
    {
      '1': 'sort_order',
      '3': 6,
      '4': 1,
      '5': 5,
      '9': 2,
      '10': 'sortOrder',
      '17': true
    },
    {'1': 'status', '3': 7, '4': 1, '5': 9, '9': 3, '10': 'status', '17': true},
    {'1': 'is_deleted', '3': 8, '4': 1, '5': 8, '9': 4, '10': 'isDeleted', '17': true},
    {'1': 'trade_enabled', '3': 9, '4': 1, '5': 8, '9': 5, '10': 'tradeEnabled', '17': true},
    {'1': 'creator_id', '3': 10, '4': 1, '5': 5, '9': 6, '10': 'creatorId', '17': true},
  ],
  '8': [
    {'1': '_photo_url'},
    {'1': '_group_name'},
    {'1': '_sort_order'},
    {'1': '_status'},
    {'1': '_is_deleted'},
    {'1': '_trade_enabled'},
    {'1': '_creator_id'},
  ],
};

/// Descriptor for `Merchandise`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List merchandiseDescriptor = $convert.base64Decode(
    'CgtNZXJjaGFuZGlzZRIOCgJpZBgBIAEoBVICaWQSGQoIZXZlbnRfaWQYAiABKAVSB2V2ZW50SW'
    'QSEgoEbmFtZRgDIAEoCVIEbmFtZRIgCglwaG90b191cmwYBCABKAlIAFIIcGhvdG9VcmyIAQES'
    'IgoKZ3JvdXBfbmFtZRgFIAEoCUgBUglncm91cE5hbWWIAQESIgoKc29ydF9vcmRlchgGIAEoBU'
    'gCUglzb3J0T3JkZXKIAQFCDAoKX3Bob3RvX3VybEINCgtfZ3JvdXBfbmFtZUINCgtfc29ydF9v'
    'cmRlcg==');

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
  ],
  '8': [
    {'1': '_created_at'},
    {'1': '_other_user'},
  ],
};

/// Descriptor for `TradeMatch`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List tradeMatchDescriptor = $convert.base64Decode(
    'CgpUcmFkZU1hdGNoEg4KAmlkGAEgASgFUgJpZBIZCgh1c2VyMV9pZBgCIAEoBVIHdXNlcjFJZB'
    'IZCgh1c2VyMl9pZBgDIAEoBVIHdXNlcjJJZBIWCgZzdGF0dXMYBCABKAlSBnN0YXR1cxIiCgpj'
    'cmVhdGVkX2F0GAUgASgJSABSCWNyZWF0ZWRBdIgBARIwCgpvdGhlcl91c2VyGAYgASgLMgwueW'
    '1hdGNoLlVzZXJIAVIJb3RoZXJVc2VyiAEBEjQKCnVzZXJfaGF2ZXMYByADKAsyFS55bWF0Y2gu'
    'SW52ZW50b3J5SXRlbVIJdXNlckhhdmVzEjQKCnVzZXJfd2FudHMYCCADKAsyFS55bWF0Y2guSW'
    '52ZW50b3J5SXRlbVIJdXNlcldhbnRzQg0KC19jcmVhdGVkX2F0Qg0KC19vdGhlcl91c2Vy');

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
    'IgASgFUgljcmVhdG9ySWQ=');

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

@$core.Deprecated('Use updateMerchSortOrderRequestDescriptor instead')
const UpdateMerchSortOrderRequest$json = {
  '1': 'UpdateMerchSortOrderRequest',
  '2': [
    {'1': 'event_id', '3': 1, '4': 1, '5': 5, '10': 'eventId'},
    {
      '1': 'sort_orders',
      '3': 2,
      '4': 3,
      '5': 11,
      '6': '.ymatch.UpdateMerchSortOrderRequest.SortOrdersEntry',
      '10': 'sortOrders'
    },
  ],
  '3': [UpdateMerchSortOrderRequest_SortOrdersEntry$json],
};

@$core.Deprecated('Use updateMerchSortOrderRequestDescriptor instead')
const UpdateMerchSortOrderRequest_SortOrdersEntry$json = {
  '1': 'SortOrdersEntry',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 5, '10': 'key'},
    {'1': 'value', '3': 2, '4': 1, '5': 5, '10': 'value'},
  ],
  '7': {'7': true},
};

/// Descriptor for `UpdateMerchSortOrderRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List updateMerchSortOrderRequestDescriptor = $convert.base64Decode(
    'ChtVcGRhdGVNZXJjaFNvcnRPcmRlclJlcXVlc3QSGQoIZXZlbnRfaWQYASABKAVSB2V2ZW50SW'
    'QSVAoLc29ydF9vcmRlcnMYAiADKAsyMy55bWF0Y2guVXBkYXRlTWVyY2hTb3J0T3JkZXJSZXF1'
    'ZXN0LlNvcnRPcmRlcnNFbnRyeVIKc29ydE9yZGVycxo9Cg9Tb3J0T3JkZXJzRW50cnkSEAoDa2'
    'V5GAEgASgFUgNrZXkSFAoFdmFsdWUYAiABKAVSBXZhbHVlOgI4AQ==');

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
    {'1': 'creator_id', '3': 4, '4': 1, '5': 5, '9': 2, '10': 'creatorId', '17': true},
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
    'ABKAlIAFIIcGhvdG9VcmyIAQESIgoKZ3JvdXBfbmFtZRgDIAEoCUgBUglncm91cE5hbWWIAQFC'
    'DAoKX3Bob3RvX3VybEINCgtfZ3JvdXBfbmFtZQ==');

@$core.Deprecated('Use updateMatchStatusRequestDescriptor instead')
const UpdateMatchStatusRequest$json = {
  '1': 'UpdateMatchStatusRequest',
  '2': [
    {'1': 'status', '3': 1, '4': 1, '5': 9, '10': 'status'},
  ],
};

/// Descriptor for `UpdateMatchStatusRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List updateMatchStatusRequestDescriptor =
    $convert.base64Decode(
        'ChhVcGRhdGVNYXRjaFN0YXR1c1JlcXVlc3QSFgoGc3RhdHVzGAEgASgJUgZzdGF0dXM=');

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
    {'1': 'banned_until', '3': 2, '4': 1, '5': 9, '9': 1, '10': 'bannedUntil', '17': true},
  ],
  '8': [
    {'1': '_reason'},
    {'1': '_banned_until'},
  ],
};

/// Descriptor for `BanUserRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List banUserRequestDescriptor = $convert.base64Decode(
    'Cg5CYW5Vc2VyUmVxdWVzdA==');

@$core.Deprecated('Use updateUserRoleRequestDescriptor instead')
const UpdateUserRoleRequest$json = {
  '1': 'UpdateUserRoleRequest',
  '2': [
    {'1': 'role', '3': 1, '4': 1, '5': 9, '10': 'role'},
  ],
};

/// Descriptor for `UpdateUserRoleRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List updateUserRoleRequestDescriptor = $convert.base64Decode(
    'ChVVcGRhdGVVc2VyUm9sZVJlcXVlc3Q=');

@$core.Deprecated('Use userActionRequestDescriptor instead')
const UserActionRequest$json = {
  '1': 'UserActionRequest',
  '2': [
    {'1': 'user_id', '3': 1, '4': 1, '5': 5, '10': 'userId'},
  ],
};

/// Descriptor for `UserActionRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List userActionRequestDescriptor = $convert.base64Decode(
    'ChFVc2VyQWN0aW9uUmVxdWVzdA==');
