// This is a generated file - do not edit.
//
// Generated from meshsetu.proto.

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

@$core.Deprecated('Use priorityDescriptor instead')
const Priority$json = {
  '1': 'Priority',
  '2': [
    {'1': 'P_UNSPECIFIED', '2': 0},
    {'1': 'P0_CRITICAL', '2': 1},
    {'1': 'P1_HIGH', '2': 2},
    {'1': 'P2_NORMAL', '2': 3},
    {'1': 'P3_BULK', '2': 4},
  ],
};

/// Descriptor for `Priority`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List priorityDescriptor = $convert.base64Decode(
    'CghQcmlvcml0eRIRCg1QX1VOU1BFQ0lGSUVEEAASDwoLUDBfQ1JJVElDQUwQARILCgdQMV9ISU'
    'dIEAISDQoJUDJfTk9STUFMEAMSCwoHUDNfQlVMSxAE');

@$core.Deprecated('Use payloadTypeDescriptor instead')
const PayloadType$json = {
  '1': 'PayloadType',
  '2': [
    {'1': 'PT_UNSPECIFIED', '2': 0},
    {'1': 'STRUCTURED_SOS', '2': 1},
    {'1': 'ROOM_MESSAGE', '2': 2},
    {'1': 'VOICE_MANIFEST', '2': 3},
    {'1': 'VOICE_OBJECT', '2': 4},
    {'1': 'ACK', '2': 5},
    {'1': 'RESPONDER_UPDATE', '2': 6},
    {'1': 'BEACON_OBSERVATION', '2': 7},
  ],
};

/// Descriptor for `PayloadType`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List payloadTypeDescriptor = $convert.base64Decode(
    'CgtQYXlsb2FkVHlwZRISCg5QVF9VTlNQRUNJRklFRBAAEhIKDlNUUlVDVFVSRURfU09TEAESEA'
    'oMUk9PTV9NRVNTQUdFEAISEgoOVk9JQ0VfTUFOSUZFU1QQAxIQCgxWT0lDRV9PQkpFQ1QQBBIH'
    'CgNBQ0sQBRIUChBSRVNQT05ERVJfVVBEQVRFEAYSFgoSQkVBQ09OX09CU0VSVkFUSU9OEAc=');

@$core.Deprecated('Use meshEnvelopeDescriptor instead')
const MeshEnvelope$json = {
  '1': 'MeshEnvelope',
  '2': [
    {'1': 'object_id', '3': 1, '4': 1, '5': 4, '10': 'objectId'},
    {'1': 'event_id', '3': 2, '4': 1, '5': 9, '10': 'eventId'},
    {'1': 'site_id', '3': 3, '4': 1, '5': 9, '10': 'siteId'},
    {'1': 'room_id', '3': 4, '4': 1, '5': 9, '10': 'roomId'},
    {'1': 'created_at_ms', '3': 5, '4': 1, '5': 3, '10': 'createdAtMs'},
    {'1': 'expires_at_ms', '3': 6, '4': 1, '5': 3, '10': 'expiresAtMs'},
    {'1': 'hop_count', '3': 7, '4': 1, '5': 13, '10': 'hopCount'},
    {'1': 'hop_limit', '3': 8, '4': 1, '5': 13, '10': 'hopLimit'},
    {
      '1': 'priority',
      '3': 9,
      '4': 1,
      '5': 14,
      '6': '.meshsetu.v1.Priority',
      '10': 'priority'
    },
    {
      '1': 'payload_type',
      '3': 10,
      '4': 1,
      '5': 14,
      '6': '.meshsetu.v1.PayloadType',
      '10': 'payloadType'
    },
    {'1': 'payload', '3': 11, '4': 1, '5': 12, '10': 'payload'},
    {
      '1': 'origin_ephemeral_id',
      '3': 12,
      '4': 1,
      '5': 4,
      '10': 'originEphemeralId'
    },
    {'1': 'trace_id', '3': 13, '4': 1, '5': 12, '10': 'traceId'},
  ],
};

/// Descriptor for `MeshEnvelope`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List meshEnvelopeDescriptor = $convert.base64Decode(
    'CgxNZXNoRW52ZWxvcGUSGwoJb2JqZWN0X2lkGAEgASgEUghvYmplY3RJZBIZCghldmVudF9pZB'
    'gCIAEoCVIHZXZlbnRJZBIXCgdzaXRlX2lkGAMgASgJUgZzaXRlSWQSFwoHcm9vbV9pZBgEIAEo'
    'CVIGcm9vbUlkEiIKDWNyZWF0ZWRfYXRfbXMYBSABKANSC2NyZWF0ZWRBdE1zEiIKDWV4cGlyZX'
    'NfYXRfbXMYBiABKANSC2V4cGlyZXNBdE1zEhsKCWhvcF9jb3VudBgHIAEoDVIIaG9wQ291bnQS'
    'GwoJaG9wX2xpbWl0GAggASgNUghob3BMaW1pdBIxCghwcmlvcml0eRgJIAEoDjIVLm1lc2hzZX'
    'R1LnYxLlByaW9yaXR5Ughwcmlvcml0eRI7CgxwYXlsb2FkX3R5cGUYCiABKA4yGC5tZXNoc2V0'
    'dS52MS5QYXlsb2FkVHlwZVILcGF5bG9hZFR5cGUSGAoHcGF5bG9hZBgLIAEoDFIHcGF5bG9hZB'
    'IuChNvcmlnaW5fZXBoZW1lcmFsX2lkGAwgASgEUhFvcmlnaW5FcGhlbWVyYWxJZBIZCgh0cmFj'
    'ZV9pZBgNIAEoDFIHdHJhY2VJZA==');
