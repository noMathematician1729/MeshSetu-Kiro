// This is a generated file - do not edit.
//
// Generated from meshsetu.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'meshsetu.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'meshsetu.pbenum.dart';

class MeshEnvelope extends $pb.GeneratedMessage {
  factory MeshEnvelope({
    $fixnum.Int64? objectId,
    $core.String? eventId,
    $core.String? siteId,
    $core.String? roomId,
    $fixnum.Int64? createdAtMs,
    $fixnum.Int64? expiresAtMs,
    $core.int? hopCount,
    $core.int? hopLimit,
    Priority? priority,
    PayloadType? payloadType,
    $core.List<$core.int>? payload,
    $fixnum.Int64? originEphemeralId,
    $core.List<$core.int>? traceId,
  }) {
    final result = create();
    if (objectId != null) result.objectId = objectId;
    if (eventId != null) result.eventId = eventId;
    if (siteId != null) result.siteId = siteId;
    if (roomId != null) result.roomId = roomId;
    if (createdAtMs != null) result.createdAtMs = createdAtMs;
    if (expiresAtMs != null) result.expiresAtMs = expiresAtMs;
    if (hopCount != null) result.hopCount = hopCount;
    if (hopLimit != null) result.hopLimit = hopLimit;
    if (priority != null) result.priority = priority;
    if (payloadType != null) result.payloadType = payloadType;
    if (payload != null) result.payload = payload;
    if (originEphemeralId != null) result.originEphemeralId = originEphemeralId;
    if (traceId != null) result.traceId = traceId;
    return result;
  }

  MeshEnvelope._();

  factory MeshEnvelope.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory MeshEnvelope.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MeshEnvelope',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'meshsetu.v1'),
      createEmptyInstance: create)
    ..a<$fixnum.Int64>(
        1, _omitFieldNames ? '' : 'objectId', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOS(2, _omitFieldNames ? '' : 'eventId')
    ..aOS(3, _omitFieldNames ? '' : 'siteId')
    ..aOS(4, _omitFieldNames ? '' : 'roomId')
    ..aInt64(5, _omitFieldNames ? '' : 'createdAtMs')
    ..aInt64(6, _omitFieldNames ? '' : 'expiresAtMs')
    ..aI(7, _omitFieldNames ? '' : 'hopCount', fieldType: $pb.PbFieldType.OU3)
    ..aI(8, _omitFieldNames ? '' : 'hopLimit', fieldType: $pb.PbFieldType.OU3)
    ..aE<Priority>(9, _omitFieldNames ? '' : 'priority',
        enumValues: Priority.values)
    ..aE<PayloadType>(10, _omitFieldNames ? '' : 'payloadType',
        enumValues: PayloadType.values)
    ..a<$core.List<$core.int>>(
        11, _omitFieldNames ? '' : 'payload', $pb.PbFieldType.OY)
    ..a<$fixnum.Int64>(
        12, _omitFieldNames ? '' : 'originEphemeralId', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$core.List<$core.int>>(
        13, _omitFieldNames ? '' : 'traceId', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MeshEnvelope clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MeshEnvelope copyWith(void Function(MeshEnvelope) updates) =>
      super.copyWith((message) => updates(message as MeshEnvelope))
          as MeshEnvelope;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MeshEnvelope create() => MeshEnvelope._();
  @$core.override
  MeshEnvelope createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static MeshEnvelope getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MeshEnvelope>(create);
  static MeshEnvelope? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get objectId => $_getI64(0);
  @$pb.TagNumber(1)
  set objectId($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasObjectId() => $_has(0);
  @$pb.TagNumber(1)
  void clearObjectId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get eventId => $_getSZ(1);
  @$pb.TagNumber(2)
  set eventId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasEventId() => $_has(1);
  @$pb.TagNumber(2)
  void clearEventId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get siteId => $_getSZ(2);
  @$pb.TagNumber(3)
  set siteId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSiteId() => $_has(2);
  @$pb.TagNumber(3)
  void clearSiteId() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get roomId => $_getSZ(3);
  @$pb.TagNumber(4)
  set roomId($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasRoomId() => $_has(3);
  @$pb.TagNumber(4)
  void clearRoomId() => $_clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get createdAtMs => $_getI64(4);
  @$pb.TagNumber(5)
  set createdAtMs($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasCreatedAtMs() => $_has(4);
  @$pb.TagNumber(5)
  void clearCreatedAtMs() => $_clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get expiresAtMs => $_getI64(5);
  @$pb.TagNumber(6)
  set expiresAtMs($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(6)
  $core.bool hasExpiresAtMs() => $_has(5);
  @$pb.TagNumber(6)
  void clearExpiresAtMs() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.int get hopCount => $_getIZ(6);
  @$pb.TagNumber(7)
  set hopCount($core.int value) => $_setUnsignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasHopCount() => $_has(6);
  @$pb.TagNumber(7)
  void clearHopCount() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.int get hopLimit => $_getIZ(7);
  @$pb.TagNumber(8)
  set hopLimit($core.int value) => $_setUnsignedInt32(7, value);
  @$pb.TagNumber(8)
  $core.bool hasHopLimit() => $_has(7);
  @$pb.TagNumber(8)
  void clearHopLimit() => $_clearField(8);

  @$pb.TagNumber(9)
  Priority get priority => $_getN(8);
  @$pb.TagNumber(9)
  set priority(Priority value) => $_setField(9, value);
  @$pb.TagNumber(9)
  $core.bool hasPriority() => $_has(8);
  @$pb.TagNumber(9)
  void clearPriority() => $_clearField(9);

  @$pb.TagNumber(10)
  PayloadType get payloadType => $_getN(9);
  @$pb.TagNumber(10)
  set payloadType(PayloadType value) => $_setField(10, value);
  @$pb.TagNumber(10)
  $core.bool hasPayloadType() => $_has(9);
  @$pb.TagNumber(10)
  void clearPayloadType() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.List<$core.int> get payload => $_getN(10);
  @$pb.TagNumber(11)
  set payload($core.List<$core.int> value) => $_setBytes(10, value);
  @$pb.TagNumber(11)
  $core.bool hasPayload() => $_has(10);
  @$pb.TagNumber(11)
  void clearPayload() => $_clearField(11);

  @$pb.TagNumber(12)
  $fixnum.Int64 get originEphemeralId => $_getI64(11);
  @$pb.TagNumber(12)
  set originEphemeralId($fixnum.Int64 value) => $_setInt64(11, value);
  @$pb.TagNumber(12)
  $core.bool hasOriginEphemeralId() => $_has(11);
  @$pb.TagNumber(12)
  void clearOriginEphemeralId() => $_clearField(12);

  @$pb.TagNumber(13)
  $core.List<$core.int> get traceId => $_getN(12);
  @$pb.TagNumber(13)
  set traceId($core.List<$core.int> value) => $_setBytes(12, value);
  @$pb.TagNumber(13)
  $core.bool hasTraceId() => $_has(12);
  @$pb.TagNumber(13)
  void clearTraceId() => $_clearField(13);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
