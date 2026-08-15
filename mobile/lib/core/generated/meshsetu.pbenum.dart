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

import 'package:protobuf/protobuf.dart' as $pb;

class Priority extends $pb.ProtobufEnum {
  static const Priority P_UNSPECIFIED =
      Priority._(0, _omitEnumNames ? '' : 'P_UNSPECIFIED');
  static const Priority P0_CRITICAL =
      Priority._(1, _omitEnumNames ? '' : 'P0_CRITICAL');
  static const Priority P1_HIGH =
      Priority._(2, _omitEnumNames ? '' : 'P1_HIGH');
  static const Priority P2_NORMAL =
      Priority._(3, _omitEnumNames ? '' : 'P2_NORMAL');
  static const Priority P3_BULK =
      Priority._(4, _omitEnumNames ? '' : 'P3_BULK');

  static const $core.List<Priority> values = <Priority>[
    P_UNSPECIFIED,
    P0_CRITICAL,
    P1_HIGH,
    P2_NORMAL,
    P3_BULK,
  ];

  static final $core.List<Priority?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 4);
  static Priority? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const Priority._(super.value, super.name);
}

class PayloadType extends $pb.ProtobufEnum {
  static const PayloadType PT_UNSPECIFIED =
      PayloadType._(0, _omitEnumNames ? '' : 'PT_UNSPECIFIED');
  static const PayloadType STRUCTURED_SOS =
      PayloadType._(1, _omitEnumNames ? '' : 'STRUCTURED_SOS');
  static const PayloadType ROOM_MESSAGE =
      PayloadType._(2, _omitEnumNames ? '' : 'ROOM_MESSAGE');
  static const PayloadType VOICE_MANIFEST =
      PayloadType._(3, _omitEnumNames ? '' : 'VOICE_MANIFEST');
  static const PayloadType VOICE_OBJECT =
      PayloadType._(4, _omitEnumNames ? '' : 'VOICE_OBJECT');
  static const PayloadType ACK = PayloadType._(5, _omitEnumNames ? '' : 'ACK');
  static const PayloadType RESPONDER_UPDATE =
      PayloadType._(6, _omitEnumNames ? '' : 'RESPONDER_UPDATE');
  static const PayloadType BEACON_OBSERVATION =
      PayloadType._(7, _omitEnumNames ? '' : 'BEACON_OBSERVATION');

  static const $core.List<PayloadType> values = <PayloadType>[
    PT_UNSPECIFIED,
    STRUCTURED_SOS,
    ROOM_MESSAGE,
    VOICE_MANIFEST,
    VOICE_OBJECT,
    ACK,
    RESPONDER_UPDATE,
    BEACON_OBSERVATION,
  ];

  static final $core.List<PayloadType?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 7);
  static PayloadType? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const PayloadType._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
