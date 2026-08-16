// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $OutboxEventsTable extends OutboxEvents
    with TableInfo<$OutboxEventsTable, OutboxEvent> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OutboxEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _eventIdMeta = const VerificationMeta(
    'eventId',
  );
  @override
  late final GeneratedColumn<String> eventId = GeneratedColumn<String>(
    'event_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _objectIdMeta = const VerificationMeta(
    'objectId',
  );
  @override
  late final GeneratedColumn<int> objectId = GeneratedColumn<int>(
    'object_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _siteIdMeta = const VerificationMeta('siteId');
  @override
  late final GeneratedColumn<String> siteId = GeneratedColumn<String>(
    'site_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _roomIdMeta = const VerificationMeta('roomId');
  @override
  late final GeneratedColumn<String> roomId = GeneratedColumn<String>(
    'room_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadTypeMeta = const VerificationMeta(
    'payloadType',
  );
  @override
  late final GeneratedColumn<String> payloadType = GeneratedColumn<String>(
    'payload_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _inputModeMeta = const VerificationMeta(
    'inputMode',
  );
  @override
  late final GeneratedColumn<String> inputMode = GeneratedColumn<String>(
    'input_mode',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rawTextMeta = const VerificationMeta(
    'rawText',
  );
  @override
  late final GeneratedColumn<String> rawText = GeneratedColumn<String>(
    'raw_text',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _transcriptMeta = const VerificationMeta(
    'transcript',
  );
  @override
  late final GeneratedColumn<String> transcript = GeneratedColumn<String>(
    'transcript',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _triageJsonMeta = const VerificationMeta(
    'triageJson',
  );
  @override
  late final GeneratedColumn<String> triageJson = GeneratedColumn<String>(
    'triage_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _voicePathMeta = const VerificationMeta(
    'voicePath',
  );
  @override
  late final GeneratedColumn<String> voicePath = GeneratedColumn<String>(
    'voice_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _priorityMeta = const VerificationMeta(
    'priority',
  );
  @override
  late final GeneratedColumn<String> priority = GeneratedColumn<String>(
    'priority',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<Uint8List> payload = GeneratedColumn<Uint8List>(
    'payload',
    aliasedName,
    true,
    type: DriftSqlType.blob,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('created'),
  );
  static const VerificationMeta _createdAtMsMeta = const VerificationMeta(
    'createdAtMs',
  );
  @override
  late final GeneratedColumn<int> createdAtMs = GeneratedColumn<int>(
    'created_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMsMeta = const VerificationMeta(
    'updatedAtMs',
  );
  @override
  late final GeneratedColumn<int> updatedAtMs = GeneratedColumn<int>(
    'updated_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _expiresAtMsMeta = const VerificationMeta(
    'expiresAtMs',
  );
  @override
  late final GeneratedColumn<int> expiresAtMs = GeneratedColumn<int>(
    'expires_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    eventId,
    objectId,
    siteId,
    roomId,
    payloadType,
    inputMode,
    rawText,
    transcript,
    triageJson,
    voicePath,
    priority,
    payload,
    state,
    createdAtMs,
    updatedAtMs,
    expiresAtMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'outbox_events';
  @override
  VerificationContext validateIntegrity(
    Insertable<OutboxEvent> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('event_id')) {
      context.handle(
        _eventIdMeta,
        eventId.isAcceptableOrUnknown(data['event_id']!, _eventIdMeta),
      );
    } else if (isInserting) {
      context.missing(_eventIdMeta);
    }
    if (data.containsKey('object_id')) {
      context.handle(
        _objectIdMeta,
        objectId.isAcceptableOrUnknown(data['object_id']!, _objectIdMeta),
      );
    }
    if (data.containsKey('site_id')) {
      context.handle(
        _siteIdMeta,
        siteId.isAcceptableOrUnknown(data['site_id']!, _siteIdMeta),
      );
    } else if (isInserting) {
      context.missing(_siteIdMeta);
    }
    if (data.containsKey('room_id')) {
      context.handle(
        _roomIdMeta,
        roomId.isAcceptableOrUnknown(data['room_id']!, _roomIdMeta),
      );
    } else if (isInserting) {
      context.missing(_roomIdMeta);
    }
    if (data.containsKey('payload_type')) {
      context.handle(
        _payloadTypeMeta,
        payloadType.isAcceptableOrUnknown(
          data['payload_type']!,
          _payloadTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadTypeMeta);
    }
    if (data.containsKey('input_mode')) {
      context.handle(
        _inputModeMeta,
        inputMode.isAcceptableOrUnknown(data['input_mode']!, _inputModeMeta),
      );
    }
    if (data.containsKey('raw_text')) {
      context.handle(
        _rawTextMeta,
        rawText.isAcceptableOrUnknown(data['raw_text']!, _rawTextMeta),
      );
    }
    if (data.containsKey('transcript')) {
      context.handle(
        _transcriptMeta,
        transcript.isAcceptableOrUnknown(data['transcript']!, _transcriptMeta),
      );
    }
    if (data.containsKey('triage_json')) {
      context.handle(
        _triageJsonMeta,
        triageJson.isAcceptableOrUnknown(data['triage_json']!, _triageJsonMeta),
      );
    }
    if (data.containsKey('voice_path')) {
      context.handle(
        _voicePathMeta,
        voicePath.isAcceptableOrUnknown(data['voice_path']!, _voicePathMeta),
      );
    }
    if (data.containsKey('priority')) {
      context.handle(
        _priorityMeta,
        priority.isAcceptableOrUnknown(data['priority']!, _priorityMeta),
      );
    } else if (isInserting) {
      context.missing(_priorityMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    }
    if (data.containsKey('created_at_ms')) {
      context.handle(
        _createdAtMsMeta,
        createdAtMs.isAcceptableOrUnknown(
          data['created_at_ms']!,
          _createdAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtMsMeta);
    }
    if (data.containsKey('updated_at_ms')) {
      context.handle(
        _updatedAtMsMeta,
        updatedAtMs.isAcceptableOrUnknown(
          data['updated_at_ms']!,
          _updatedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMsMeta);
    }
    if (data.containsKey('expires_at_ms')) {
      context.handle(
        _expiresAtMsMeta,
        expiresAtMs.isAcceptableOrUnknown(
          data['expires_at_ms']!,
          _expiresAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_expiresAtMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {eventId};
  @override
  OutboxEvent map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OutboxEvent(
      eventId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_id'],
      )!,
      objectId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}object_id'],
      ),
      siteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}site_id'],
      )!,
      roomId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}room_id'],
      )!,
      payloadType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_type'],
      )!,
      inputMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}input_mode'],
      ),
      rawText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}raw_text'],
      ),
      transcript: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}transcript'],
      ),
      triageJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}triage_json'],
      ),
      voicePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}voice_path'],
      ),
      priority: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}priority'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}payload'],
      ),
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      createdAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_ms'],
      )!,
      updatedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_ms'],
      )!,
      expiresAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}expires_at_ms'],
      )!,
    );
  }

  @override
  $OutboxEventsTable createAlias(String alias) {
    return $OutboxEventsTable(attachedDatabase, alias);
  }
}

class OutboxEvent extends DataClass implements Insertable<OutboxEvent> {
  final String eventId;
  final int? objectId;
  final String siteId;
  final String roomId;
  final String payloadType;
  final String? inputMode;
  final String? rawText;
  final String? transcript;
  final String? triageJson;
  final String? voicePath;
  final String priority;
  final Uint8List? payload;
  final String state;
  final int createdAtMs;
  final int updatedAtMs;
  final int expiresAtMs;
  const OutboxEvent({
    required this.eventId,
    this.objectId,
    required this.siteId,
    required this.roomId,
    required this.payloadType,
    this.inputMode,
    this.rawText,
    this.transcript,
    this.triageJson,
    this.voicePath,
    required this.priority,
    this.payload,
    required this.state,
    required this.createdAtMs,
    required this.updatedAtMs,
    required this.expiresAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['event_id'] = Variable<String>(eventId);
    if (!nullToAbsent || objectId != null) {
      map['object_id'] = Variable<int>(objectId);
    }
    map['site_id'] = Variable<String>(siteId);
    map['room_id'] = Variable<String>(roomId);
    map['payload_type'] = Variable<String>(payloadType);
    if (!nullToAbsent || inputMode != null) {
      map['input_mode'] = Variable<String>(inputMode);
    }
    if (!nullToAbsent || rawText != null) {
      map['raw_text'] = Variable<String>(rawText);
    }
    if (!nullToAbsent || transcript != null) {
      map['transcript'] = Variable<String>(transcript);
    }
    if (!nullToAbsent || triageJson != null) {
      map['triage_json'] = Variable<String>(triageJson);
    }
    if (!nullToAbsent || voicePath != null) {
      map['voice_path'] = Variable<String>(voicePath);
    }
    map['priority'] = Variable<String>(priority);
    if (!nullToAbsent || payload != null) {
      map['payload'] = Variable<Uint8List>(payload);
    }
    map['state'] = Variable<String>(state);
    map['created_at_ms'] = Variable<int>(createdAtMs);
    map['updated_at_ms'] = Variable<int>(updatedAtMs);
    map['expires_at_ms'] = Variable<int>(expiresAtMs);
    return map;
  }

  OutboxEventsCompanion toCompanion(bool nullToAbsent) {
    return OutboxEventsCompanion(
      eventId: Value(eventId),
      objectId: objectId == null && nullToAbsent
          ? const Value.absent()
          : Value(objectId),
      siteId: Value(siteId),
      roomId: Value(roomId),
      payloadType: Value(payloadType),
      inputMode: inputMode == null && nullToAbsent
          ? const Value.absent()
          : Value(inputMode),
      rawText: rawText == null && nullToAbsent
          ? const Value.absent()
          : Value(rawText),
      transcript: transcript == null && nullToAbsent
          ? const Value.absent()
          : Value(transcript),
      triageJson: triageJson == null && nullToAbsent
          ? const Value.absent()
          : Value(triageJson),
      voicePath: voicePath == null && nullToAbsent
          ? const Value.absent()
          : Value(voicePath),
      priority: Value(priority),
      payload: payload == null && nullToAbsent
          ? const Value.absent()
          : Value(payload),
      state: Value(state),
      createdAtMs: Value(createdAtMs),
      updatedAtMs: Value(updatedAtMs),
      expiresAtMs: Value(expiresAtMs),
    );
  }

  factory OutboxEvent.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OutboxEvent(
      eventId: serializer.fromJson<String>(json['eventId']),
      objectId: serializer.fromJson<int?>(json['objectId']),
      siteId: serializer.fromJson<String>(json['siteId']),
      roomId: serializer.fromJson<String>(json['roomId']),
      payloadType: serializer.fromJson<String>(json['payloadType']),
      inputMode: serializer.fromJson<String?>(json['inputMode']),
      rawText: serializer.fromJson<String?>(json['rawText']),
      transcript: serializer.fromJson<String?>(json['transcript']),
      triageJson: serializer.fromJson<String?>(json['triageJson']),
      voicePath: serializer.fromJson<String?>(json['voicePath']),
      priority: serializer.fromJson<String>(json['priority']),
      payload: serializer.fromJson<Uint8List?>(json['payload']),
      state: serializer.fromJson<String>(json['state']),
      createdAtMs: serializer.fromJson<int>(json['createdAtMs']),
      updatedAtMs: serializer.fromJson<int>(json['updatedAtMs']),
      expiresAtMs: serializer.fromJson<int>(json['expiresAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'eventId': serializer.toJson<String>(eventId),
      'objectId': serializer.toJson<int?>(objectId),
      'siteId': serializer.toJson<String>(siteId),
      'roomId': serializer.toJson<String>(roomId),
      'payloadType': serializer.toJson<String>(payloadType),
      'inputMode': serializer.toJson<String?>(inputMode),
      'rawText': serializer.toJson<String?>(rawText),
      'transcript': serializer.toJson<String?>(transcript),
      'triageJson': serializer.toJson<String?>(triageJson),
      'voicePath': serializer.toJson<String?>(voicePath),
      'priority': serializer.toJson<String>(priority),
      'payload': serializer.toJson<Uint8List?>(payload),
      'state': serializer.toJson<String>(state),
      'createdAtMs': serializer.toJson<int>(createdAtMs),
      'updatedAtMs': serializer.toJson<int>(updatedAtMs),
      'expiresAtMs': serializer.toJson<int>(expiresAtMs),
    };
  }

  OutboxEvent copyWith({
    String? eventId,
    Value<int?> objectId = const Value.absent(),
    String? siteId,
    String? roomId,
    String? payloadType,
    Value<String?> inputMode = const Value.absent(),
    Value<String?> rawText = const Value.absent(),
    Value<String?> transcript = const Value.absent(),
    Value<String?> triageJson = const Value.absent(),
    Value<String?> voicePath = const Value.absent(),
    String? priority,
    Value<Uint8List?> payload = const Value.absent(),
    String? state,
    int? createdAtMs,
    int? updatedAtMs,
    int? expiresAtMs,
  }) => OutboxEvent(
    eventId: eventId ?? this.eventId,
    objectId: objectId.present ? objectId.value : this.objectId,
    siteId: siteId ?? this.siteId,
    roomId: roomId ?? this.roomId,
    payloadType: payloadType ?? this.payloadType,
    inputMode: inputMode.present ? inputMode.value : this.inputMode,
    rawText: rawText.present ? rawText.value : this.rawText,
    transcript: transcript.present ? transcript.value : this.transcript,
    triageJson: triageJson.present ? triageJson.value : this.triageJson,
    voicePath: voicePath.present ? voicePath.value : this.voicePath,
    priority: priority ?? this.priority,
    payload: payload.present ? payload.value : this.payload,
    state: state ?? this.state,
    createdAtMs: createdAtMs ?? this.createdAtMs,
    updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    expiresAtMs: expiresAtMs ?? this.expiresAtMs,
  );
  OutboxEvent copyWithCompanion(OutboxEventsCompanion data) {
    return OutboxEvent(
      eventId: data.eventId.present ? data.eventId.value : this.eventId,
      objectId: data.objectId.present ? data.objectId.value : this.objectId,
      siteId: data.siteId.present ? data.siteId.value : this.siteId,
      roomId: data.roomId.present ? data.roomId.value : this.roomId,
      payloadType: data.payloadType.present
          ? data.payloadType.value
          : this.payloadType,
      inputMode: data.inputMode.present ? data.inputMode.value : this.inputMode,
      rawText: data.rawText.present ? data.rawText.value : this.rawText,
      transcript: data.transcript.present
          ? data.transcript.value
          : this.transcript,
      triageJson: data.triageJson.present
          ? data.triageJson.value
          : this.triageJson,
      voicePath: data.voicePath.present ? data.voicePath.value : this.voicePath,
      priority: data.priority.present ? data.priority.value : this.priority,
      payload: data.payload.present ? data.payload.value : this.payload,
      state: data.state.present ? data.state.value : this.state,
      createdAtMs: data.createdAtMs.present
          ? data.createdAtMs.value
          : this.createdAtMs,
      updatedAtMs: data.updatedAtMs.present
          ? data.updatedAtMs.value
          : this.updatedAtMs,
      expiresAtMs: data.expiresAtMs.present
          ? data.expiresAtMs.value
          : this.expiresAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OutboxEvent(')
          ..write('eventId: $eventId, ')
          ..write('objectId: $objectId, ')
          ..write('siteId: $siteId, ')
          ..write('roomId: $roomId, ')
          ..write('payloadType: $payloadType, ')
          ..write('inputMode: $inputMode, ')
          ..write('rawText: $rawText, ')
          ..write('transcript: $transcript, ')
          ..write('triageJson: $triageJson, ')
          ..write('voicePath: $voicePath, ')
          ..write('priority: $priority, ')
          ..write('payload: $payload, ')
          ..write('state: $state, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('expiresAtMs: $expiresAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    eventId,
    objectId,
    siteId,
    roomId,
    payloadType,
    inputMode,
    rawText,
    transcript,
    triageJson,
    voicePath,
    priority,
    $driftBlobEquality.hash(payload),
    state,
    createdAtMs,
    updatedAtMs,
    expiresAtMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OutboxEvent &&
          other.eventId == this.eventId &&
          other.objectId == this.objectId &&
          other.siteId == this.siteId &&
          other.roomId == this.roomId &&
          other.payloadType == this.payloadType &&
          other.inputMode == this.inputMode &&
          other.rawText == this.rawText &&
          other.transcript == this.transcript &&
          other.triageJson == this.triageJson &&
          other.voicePath == this.voicePath &&
          other.priority == this.priority &&
          $driftBlobEquality.equals(other.payload, this.payload) &&
          other.state == this.state &&
          other.createdAtMs == this.createdAtMs &&
          other.updatedAtMs == this.updatedAtMs &&
          other.expiresAtMs == this.expiresAtMs);
}

class OutboxEventsCompanion extends UpdateCompanion<OutboxEvent> {
  final Value<String> eventId;
  final Value<int?> objectId;
  final Value<String> siteId;
  final Value<String> roomId;
  final Value<String> payloadType;
  final Value<String?> inputMode;
  final Value<String?> rawText;
  final Value<String?> transcript;
  final Value<String?> triageJson;
  final Value<String?> voicePath;
  final Value<String> priority;
  final Value<Uint8List?> payload;
  final Value<String> state;
  final Value<int> createdAtMs;
  final Value<int> updatedAtMs;
  final Value<int> expiresAtMs;
  final Value<int> rowid;
  const OutboxEventsCompanion({
    this.eventId = const Value.absent(),
    this.objectId = const Value.absent(),
    this.siteId = const Value.absent(),
    this.roomId = const Value.absent(),
    this.payloadType = const Value.absent(),
    this.inputMode = const Value.absent(),
    this.rawText = const Value.absent(),
    this.transcript = const Value.absent(),
    this.triageJson = const Value.absent(),
    this.voicePath = const Value.absent(),
    this.priority = const Value.absent(),
    this.payload = const Value.absent(),
    this.state = const Value.absent(),
    this.createdAtMs = const Value.absent(),
    this.updatedAtMs = const Value.absent(),
    this.expiresAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OutboxEventsCompanion.insert({
    required String eventId,
    this.objectId = const Value.absent(),
    required String siteId,
    required String roomId,
    required String payloadType,
    this.inputMode = const Value.absent(),
    this.rawText = const Value.absent(),
    this.transcript = const Value.absent(),
    this.triageJson = const Value.absent(),
    this.voicePath = const Value.absent(),
    required String priority,
    this.payload = const Value.absent(),
    this.state = const Value.absent(),
    required int createdAtMs,
    required int updatedAtMs,
    required int expiresAtMs,
    this.rowid = const Value.absent(),
  }) : eventId = Value(eventId),
       siteId = Value(siteId),
       roomId = Value(roomId),
       payloadType = Value(payloadType),
       priority = Value(priority),
       createdAtMs = Value(createdAtMs),
       updatedAtMs = Value(updatedAtMs),
       expiresAtMs = Value(expiresAtMs);
  static Insertable<OutboxEvent> custom({
    Expression<String>? eventId,
    Expression<int>? objectId,
    Expression<String>? siteId,
    Expression<String>? roomId,
    Expression<String>? payloadType,
    Expression<String>? inputMode,
    Expression<String>? rawText,
    Expression<String>? transcript,
    Expression<String>? triageJson,
    Expression<String>? voicePath,
    Expression<String>? priority,
    Expression<Uint8List>? payload,
    Expression<String>? state,
    Expression<int>? createdAtMs,
    Expression<int>? updatedAtMs,
    Expression<int>? expiresAtMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (eventId != null) 'event_id': eventId,
      if (objectId != null) 'object_id': objectId,
      if (siteId != null) 'site_id': siteId,
      if (roomId != null) 'room_id': roomId,
      if (payloadType != null) 'payload_type': payloadType,
      if (inputMode != null) 'input_mode': inputMode,
      if (rawText != null) 'raw_text': rawText,
      if (transcript != null) 'transcript': transcript,
      if (triageJson != null) 'triage_json': triageJson,
      if (voicePath != null) 'voice_path': voicePath,
      if (priority != null) 'priority': priority,
      if (payload != null) 'payload': payload,
      if (state != null) 'state': state,
      if (createdAtMs != null) 'created_at_ms': createdAtMs,
      if (updatedAtMs != null) 'updated_at_ms': updatedAtMs,
      if (expiresAtMs != null) 'expires_at_ms': expiresAtMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OutboxEventsCompanion copyWith({
    Value<String>? eventId,
    Value<int?>? objectId,
    Value<String>? siteId,
    Value<String>? roomId,
    Value<String>? payloadType,
    Value<String?>? inputMode,
    Value<String?>? rawText,
    Value<String?>? transcript,
    Value<String?>? triageJson,
    Value<String?>? voicePath,
    Value<String>? priority,
    Value<Uint8List?>? payload,
    Value<String>? state,
    Value<int>? createdAtMs,
    Value<int>? updatedAtMs,
    Value<int>? expiresAtMs,
    Value<int>? rowid,
  }) {
    return OutboxEventsCompanion(
      eventId: eventId ?? this.eventId,
      objectId: objectId ?? this.objectId,
      siteId: siteId ?? this.siteId,
      roomId: roomId ?? this.roomId,
      payloadType: payloadType ?? this.payloadType,
      inputMode: inputMode ?? this.inputMode,
      rawText: rawText ?? this.rawText,
      transcript: transcript ?? this.transcript,
      triageJson: triageJson ?? this.triageJson,
      voicePath: voicePath ?? this.voicePath,
      priority: priority ?? this.priority,
      payload: payload ?? this.payload,
      state: state ?? this.state,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      expiresAtMs: expiresAtMs ?? this.expiresAtMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (eventId.present) {
      map['event_id'] = Variable<String>(eventId.value);
    }
    if (objectId.present) {
      map['object_id'] = Variable<int>(objectId.value);
    }
    if (siteId.present) {
      map['site_id'] = Variable<String>(siteId.value);
    }
    if (roomId.present) {
      map['room_id'] = Variable<String>(roomId.value);
    }
    if (payloadType.present) {
      map['payload_type'] = Variable<String>(payloadType.value);
    }
    if (inputMode.present) {
      map['input_mode'] = Variable<String>(inputMode.value);
    }
    if (rawText.present) {
      map['raw_text'] = Variable<String>(rawText.value);
    }
    if (transcript.present) {
      map['transcript'] = Variable<String>(transcript.value);
    }
    if (triageJson.present) {
      map['triage_json'] = Variable<String>(triageJson.value);
    }
    if (voicePath.present) {
      map['voice_path'] = Variable<String>(voicePath.value);
    }
    if (priority.present) {
      map['priority'] = Variable<String>(priority.value);
    }
    if (payload.present) {
      map['payload'] = Variable<Uint8List>(payload.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (createdAtMs.present) {
      map['created_at_ms'] = Variable<int>(createdAtMs.value);
    }
    if (updatedAtMs.present) {
      map['updated_at_ms'] = Variable<int>(updatedAtMs.value);
    }
    if (expiresAtMs.present) {
      map['expires_at_ms'] = Variable<int>(expiresAtMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OutboxEventsCompanion(')
          ..write('eventId: $eventId, ')
          ..write('objectId: $objectId, ')
          ..write('siteId: $siteId, ')
          ..write('roomId: $roomId, ')
          ..write('payloadType: $payloadType, ')
          ..write('inputMode: $inputMode, ')
          ..write('rawText: $rawText, ')
          ..write('transcript: $transcript, ')
          ..write('triageJson: $triageJson, ')
          ..write('voicePath: $voicePath, ')
          ..write('priority: $priority, ')
          ..write('payload: $payload, ')
          ..write('state: $state, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('expiresAtMs: $expiresAtMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $InboxEventsTable extends InboxEvents
    with TableInfo<$InboxEventsTable, InboxEvent> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $InboxEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _objectIdMeta = const VerificationMeta(
    'objectId',
  );
  @override
  late final GeneratedColumn<int> objectId = GeneratedColumn<int>(
    'object_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _eventIdMeta = const VerificationMeta(
    'eventId',
  );
  @override
  late final GeneratedColumn<String> eventId = GeneratedColumn<String>(
    'event_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _siteIdMeta = const VerificationMeta('siteId');
  @override
  late final GeneratedColumn<String> siteId = GeneratedColumn<String>(
    'site_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _roomIdMeta = const VerificationMeta('roomId');
  @override
  late final GeneratedColumn<String> roomId = GeneratedColumn<String>(
    'room_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadTypeMeta = const VerificationMeta(
    'payloadType',
  );
  @override
  late final GeneratedColumn<String> payloadType = GeneratedColumn<String>(
    'payload_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<Uint8List> payload = GeneratedColumn<Uint8List>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _peerIdMeta = const VerificationMeta('peerId');
  @override
  late final GeneratedColumn<String> peerId = GeneratedColumn<String>(
    'peer_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _receivedAtMsMeta = const VerificationMeta(
    'receivedAtMs',
  );
  @override
  late final GeneratedColumn<int> receivedAtMs = GeneratedColumn<int>(
    'received_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    objectId,
    eventId,
    siteId,
    roomId,
    payloadType,
    payload,
    peerId,
    receivedAtMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'inbox_events';
  @override
  VerificationContext validateIntegrity(
    Insertable<InboxEvent> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('object_id')) {
      context.handle(
        _objectIdMeta,
        objectId.isAcceptableOrUnknown(data['object_id']!, _objectIdMeta),
      );
    }
    if (data.containsKey('event_id')) {
      context.handle(
        _eventIdMeta,
        eventId.isAcceptableOrUnknown(data['event_id']!, _eventIdMeta),
      );
    } else if (isInserting) {
      context.missing(_eventIdMeta);
    }
    if (data.containsKey('site_id')) {
      context.handle(
        _siteIdMeta,
        siteId.isAcceptableOrUnknown(data['site_id']!, _siteIdMeta),
      );
    } else if (isInserting) {
      context.missing(_siteIdMeta);
    }
    if (data.containsKey('room_id')) {
      context.handle(
        _roomIdMeta,
        roomId.isAcceptableOrUnknown(data['room_id']!, _roomIdMeta),
      );
    } else if (isInserting) {
      context.missing(_roomIdMeta);
    }
    if (data.containsKey('payload_type')) {
      context.handle(
        _payloadTypeMeta,
        payloadType.isAcceptableOrUnknown(
          data['payload_type']!,
          _payloadTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadTypeMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('peer_id')) {
      context.handle(
        _peerIdMeta,
        peerId.isAcceptableOrUnknown(data['peer_id']!, _peerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_peerIdMeta);
    }
    if (data.containsKey('received_at_ms')) {
      context.handle(
        _receivedAtMsMeta,
        receivedAtMs.isAcceptableOrUnknown(
          data['received_at_ms']!,
          _receivedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_receivedAtMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {objectId};
  @override
  InboxEvent map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return InboxEvent(
      objectId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}object_id'],
      )!,
      eventId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_id'],
      )!,
      siteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}site_id'],
      )!,
      roomId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}room_id'],
      )!,
      payloadType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_type'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}payload'],
      )!,
      peerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}peer_id'],
      )!,
      receivedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}received_at_ms'],
      )!,
    );
  }

  @override
  $InboxEventsTable createAlias(String alias) {
    return $InboxEventsTable(attachedDatabase, alias);
  }
}

class InboxEvent extends DataClass implements Insertable<InboxEvent> {
  final int objectId;
  final String eventId;
  final String siteId;
  final String roomId;
  final String payloadType;
  final Uint8List payload;
  final String peerId;
  final int receivedAtMs;
  const InboxEvent({
    required this.objectId,
    required this.eventId,
    required this.siteId,
    required this.roomId,
    required this.payloadType,
    required this.payload,
    required this.peerId,
    required this.receivedAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['object_id'] = Variable<int>(objectId);
    map['event_id'] = Variable<String>(eventId);
    map['site_id'] = Variable<String>(siteId);
    map['room_id'] = Variable<String>(roomId);
    map['payload_type'] = Variable<String>(payloadType);
    map['payload'] = Variable<Uint8List>(payload);
    map['peer_id'] = Variable<String>(peerId);
    map['received_at_ms'] = Variable<int>(receivedAtMs);
    return map;
  }

  InboxEventsCompanion toCompanion(bool nullToAbsent) {
    return InboxEventsCompanion(
      objectId: Value(objectId),
      eventId: Value(eventId),
      siteId: Value(siteId),
      roomId: Value(roomId),
      payloadType: Value(payloadType),
      payload: Value(payload),
      peerId: Value(peerId),
      receivedAtMs: Value(receivedAtMs),
    );
  }

  factory InboxEvent.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return InboxEvent(
      objectId: serializer.fromJson<int>(json['objectId']),
      eventId: serializer.fromJson<String>(json['eventId']),
      siteId: serializer.fromJson<String>(json['siteId']),
      roomId: serializer.fromJson<String>(json['roomId']),
      payloadType: serializer.fromJson<String>(json['payloadType']),
      payload: serializer.fromJson<Uint8List>(json['payload']),
      peerId: serializer.fromJson<String>(json['peerId']),
      receivedAtMs: serializer.fromJson<int>(json['receivedAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'objectId': serializer.toJson<int>(objectId),
      'eventId': serializer.toJson<String>(eventId),
      'siteId': serializer.toJson<String>(siteId),
      'roomId': serializer.toJson<String>(roomId),
      'payloadType': serializer.toJson<String>(payloadType),
      'payload': serializer.toJson<Uint8List>(payload),
      'peerId': serializer.toJson<String>(peerId),
      'receivedAtMs': serializer.toJson<int>(receivedAtMs),
    };
  }

  InboxEvent copyWith({
    int? objectId,
    String? eventId,
    String? siteId,
    String? roomId,
    String? payloadType,
    Uint8List? payload,
    String? peerId,
    int? receivedAtMs,
  }) => InboxEvent(
    objectId: objectId ?? this.objectId,
    eventId: eventId ?? this.eventId,
    siteId: siteId ?? this.siteId,
    roomId: roomId ?? this.roomId,
    payloadType: payloadType ?? this.payloadType,
    payload: payload ?? this.payload,
    peerId: peerId ?? this.peerId,
    receivedAtMs: receivedAtMs ?? this.receivedAtMs,
  );
  InboxEvent copyWithCompanion(InboxEventsCompanion data) {
    return InboxEvent(
      objectId: data.objectId.present ? data.objectId.value : this.objectId,
      eventId: data.eventId.present ? data.eventId.value : this.eventId,
      siteId: data.siteId.present ? data.siteId.value : this.siteId,
      roomId: data.roomId.present ? data.roomId.value : this.roomId,
      payloadType: data.payloadType.present
          ? data.payloadType.value
          : this.payloadType,
      payload: data.payload.present ? data.payload.value : this.payload,
      peerId: data.peerId.present ? data.peerId.value : this.peerId,
      receivedAtMs: data.receivedAtMs.present
          ? data.receivedAtMs.value
          : this.receivedAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('InboxEvent(')
          ..write('objectId: $objectId, ')
          ..write('eventId: $eventId, ')
          ..write('siteId: $siteId, ')
          ..write('roomId: $roomId, ')
          ..write('payloadType: $payloadType, ')
          ..write('payload: $payload, ')
          ..write('peerId: $peerId, ')
          ..write('receivedAtMs: $receivedAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    objectId,
    eventId,
    siteId,
    roomId,
    payloadType,
    $driftBlobEquality.hash(payload),
    peerId,
    receivedAtMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is InboxEvent &&
          other.objectId == this.objectId &&
          other.eventId == this.eventId &&
          other.siteId == this.siteId &&
          other.roomId == this.roomId &&
          other.payloadType == this.payloadType &&
          $driftBlobEquality.equals(other.payload, this.payload) &&
          other.peerId == this.peerId &&
          other.receivedAtMs == this.receivedAtMs);
}

class InboxEventsCompanion extends UpdateCompanion<InboxEvent> {
  final Value<int> objectId;
  final Value<String> eventId;
  final Value<String> siteId;
  final Value<String> roomId;
  final Value<String> payloadType;
  final Value<Uint8List> payload;
  final Value<String> peerId;
  final Value<int> receivedAtMs;
  const InboxEventsCompanion({
    this.objectId = const Value.absent(),
    this.eventId = const Value.absent(),
    this.siteId = const Value.absent(),
    this.roomId = const Value.absent(),
    this.payloadType = const Value.absent(),
    this.payload = const Value.absent(),
    this.peerId = const Value.absent(),
    this.receivedAtMs = const Value.absent(),
  });
  InboxEventsCompanion.insert({
    this.objectId = const Value.absent(),
    required String eventId,
    required String siteId,
    required String roomId,
    required String payloadType,
    required Uint8List payload,
    required String peerId,
    required int receivedAtMs,
  }) : eventId = Value(eventId),
       siteId = Value(siteId),
       roomId = Value(roomId),
       payloadType = Value(payloadType),
       payload = Value(payload),
       peerId = Value(peerId),
       receivedAtMs = Value(receivedAtMs);
  static Insertable<InboxEvent> custom({
    Expression<int>? objectId,
    Expression<String>? eventId,
    Expression<String>? siteId,
    Expression<String>? roomId,
    Expression<String>? payloadType,
    Expression<Uint8List>? payload,
    Expression<String>? peerId,
    Expression<int>? receivedAtMs,
  }) {
    return RawValuesInsertable({
      if (objectId != null) 'object_id': objectId,
      if (eventId != null) 'event_id': eventId,
      if (siteId != null) 'site_id': siteId,
      if (roomId != null) 'room_id': roomId,
      if (payloadType != null) 'payload_type': payloadType,
      if (payload != null) 'payload': payload,
      if (peerId != null) 'peer_id': peerId,
      if (receivedAtMs != null) 'received_at_ms': receivedAtMs,
    });
  }

  InboxEventsCompanion copyWith({
    Value<int>? objectId,
    Value<String>? eventId,
    Value<String>? siteId,
    Value<String>? roomId,
    Value<String>? payloadType,
    Value<Uint8List>? payload,
    Value<String>? peerId,
    Value<int>? receivedAtMs,
  }) {
    return InboxEventsCompanion(
      objectId: objectId ?? this.objectId,
      eventId: eventId ?? this.eventId,
      siteId: siteId ?? this.siteId,
      roomId: roomId ?? this.roomId,
      payloadType: payloadType ?? this.payloadType,
      payload: payload ?? this.payload,
      peerId: peerId ?? this.peerId,
      receivedAtMs: receivedAtMs ?? this.receivedAtMs,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (objectId.present) {
      map['object_id'] = Variable<int>(objectId.value);
    }
    if (eventId.present) {
      map['event_id'] = Variable<String>(eventId.value);
    }
    if (siteId.present) {
      map['site_id'] = Variable<String>(siteId.value);
    }
    if (roomId.present) {
      map['room_id'] = Variable<String>(roomId.value);
    }
    if (payloadType.present) {
      map['payload_type'] = Variable<String>(payloadType.value);
    }
    if (payload.present) {
      map['payload'] = Variable<Uint8List>(payload.value);
    }
    if (peerId.present) {
      map['peer_id'] = Variable<String>(peerId.value);
    }
    if (receivedAtMs.present) {
      map['received_at_ms'] = Variable<int>(receivedAtMs.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('InboxEventsCompanion(')
          ..write('objectId: $objectId, ')
          ..write('eventId: $eventId, ')
          ..write('siteId: $siteId, ')
          ..write('roomId: $roomId, ')
          ..write('payloadType: $payloadType, ')
          ..write('payload: $payload, ')
          ..write('peerId: $peerId, ')
          ..write('receivedAtMs: $receivedAtMs')
          ..write(')'))
        .toString();
  }
}

class $SiteManifestsTable extends SiteManifests
    with TableInfo<$SiteManifestsTable, SiteManifest> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SiteManifestsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _siteIdMeta = const VerificationMeta('siteId');
  @override
  late final GeneratedColumn<String> siteId = GeneratedColumn<String>(
    'site_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _siteNameMeta = const VerificationMeta(
    'siteName',
  );
  @override
  late final GeneratedColumn<String> siteName = GeneratedColumn<String>(
    'site_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _meshCodeMeta = const VerificationMeta(
    'meshCode',
  );
  @override
  late final GeneratedColumn<String> meshCode = GeneratedColumn<String>(
    'mesh_code',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _gatewayHintMeta = const VerificationMeta(
    'gatewayHint',
  );
  @override
  late final GeneratedColumn<String> gatewayHint = GeneratedColumn<String>(
    'gateway_hint',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _validFromMsMeta = const VerificationMeta(
    'validFromMs',
  );
  @override
  late final GeneratedColumn<int> validFromMs = GeneratedColumn<int>(
    'valid_from_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _validUntilMsMeta = const VerificationMeta(
    'validUntilMs',
  );
  @override
  late final GeneratedColumn<int> validUntilMs = GeneratedColumn<int>(
    'valid_until_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _roomsJsonMeta = const VerificationMeta(
    'roomsJson',
  );
  @override
  late final GeneratedColumn<String> roomsJson = GeneratedColumn<String>(
    'rooms_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _joinedAtMsMeta = const VerificationMeta(
    'joinedAtMs',
  );
  @override
  late final GeneratedColumn<int> joinedAtMs = GeneratedColumn<int>(
    'joined_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    siteId,
    siteName,
    meshCode,
    gatewayHint,
    validFromMs,
    validUntilMs,
    roomsJson,
    joinedAtMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'site_manifests';
  @override
  VerificationContext validateIntegrity(
    Insertable<SiteManifest> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('site_id')) {
      context.handle(
        _siteIdMeta,
        siteId.isAcceptableOrUnknown(data['site_id']!, _siteIdMeta),
      );
    } else if (isInserting) {
      context.missing(_siteIdMeta);
    }
    if (data.containsKey('site_name')) {
      context.handle(
        _siteNameMeta,
        siteName.isAcceptableOrUnknown(data['site_name']!, _siteNameMeta),
      );
    } else if (isInserting) {
      context.missing(_siteNameMeta);
    }
    if (data.containsKey('mesh_code')) {
      context.handle(
        _meshCodeMeta,
        meshCode.isAcceptableOrUnknown(data['mesh_code']!, _meshCodeMeta),
      );
    } else if (isInserting) {
      context.missing(_meshCodeMeta);
    }
    if (data.containsKey('gateway_hint')) {
      context.handle(
        _gatewayHintMeta,
        gatewayHint.isAcceptableOrUnknown(
          data['gateway_hint']!,
          _gatewayHintMeta,
        ),
      );
    }
    if (data.containsKey('valid_from_ms')) {
      context.handle(
        _validFromMsMeta,
        validFromMs.isAcceptableOrUnknown(
          data['valid_from_ms']!,
          _validFromMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_validFromMsMeta);
    }
    if (data.containsKey('valid_until_ms')) {
      context.handle(
        _validUntilMsMeta,
        validUntilMs.isAcceptableOrUnknown(
          data['valid_until_ms']!,
          _validUntilMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_validUntilMsMeta);
    }
    if (data.containsKey('rooms_json')) {
      context.handle(
        _roomsJsonMeta,
        roomsJson.isAcceptableOrUnknown(data['rooms_json']!, _roomsJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_roomsJsonMeta);
    }
    if (data.containsKey('joined_at_ms')) {
      context.handle(
        _joinedAtMsMeta,
        joinedAtMs.isAcceptableOrUnknown(
          data['joined_at_ms']!,
          _joinedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_joinedAtMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {siteId};
  @override
  SiteManifest map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SiteManifest(
      siteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}site_id'],
      )!,
      siteName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}site_name'],
      )!,
      meshCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mesh_code'],
      )!,
      gatewayHint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}gateway_hint'],
      ),
      validFromMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}valid_from_ms'],
      )!,
      validUntilMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}valid_until_ms'],
      )!,
      roomsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rooms_json'],
      )!,
      joinedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}joined_at_ms'],
      )!,
    );
  }

  @override
  $SiteManifestsTable createAlias(String alias) {
    return $SiteManifestsTable(attachedDatabase, alias);
  }
}

class SiteManifest extends DataClass implements Insertable<SiteManifest> {
  final String siteId;
  final String siteName;
  final String meshCode;
  final String? gatewayHint;
  final int validFromMs;
  final int validUntilMs;
  final String roomsJson;
  final int joinedAtMs;
  const SiteManifest({
    required this.siteId,
    required this.siteName,
    required this.meshCode,
    this.gatewayHint,
    required this.validFromMs,
    required this.validUntilMs,
    required this.roomsJson,
    required this.joinedAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['site_id'] = Variable<String>(siteId);
    map['site_name'] = Variable<String>(siteName);
    map['mesh_code'] = Variable<String>(meshCode);
    if (!nullToAbsent || gatewayHint != null) {
      map['gateway_hint'] = Variable<String>(gatewayHint);
    }
    map['valid_from_ms'] = Variable<int>(validFromMs);
    map['valid_until_ms'] = Variable<int>(validUntilMs);
    map['rooms_json'] = Variable<String>(roomsJson);
    map['joined_at_ms'] = Variable<int>(joinedAtMs);
    return map;
  }

  SiteManifestsCompanion toCompanion(bool nullToAbsent) {
    return SiteManifestsCompanion(
      siteId: Value(siteId),
      siteName: Value(siteName),
      meshCode: Value(meshCode),
      gatewayHint: gatewayHint == null && nullToAbsent
          ? const Value.absent()
          : Value(gatewayHint),
      validFromMs: Value(validFromMs),
      validUntilMs: Value(validUntilMs),
      roomsJson: Value(roomsJson),
      joinedAtMs: Value(joinedAtMs),
    );
  }

  factory SiteManifest.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SiteManifest(
      siteId: serializer.fromJson<String>(json['siteId']),
      siteName: serializer.fromJson<String>(json['siteName']),
      meshCode: serializer.fromJson<String>(json['meshCode']),
      gatewayHint: serializer.fromJson<String?>(json['gatewayHint']),
      validFromMs: serializer.fromJson<int>(json['validFromMs']),
      validUntilMs: serializer.fromJson<int>(json['validUntilMs']),
      roomsJson: serializer.fromJson<String>(json['roomsJson']),
      joinedAtMs: serializer.fromJson<int>(json['joinedAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'siteId': serializer.toJson<String>(siteId),
      'siteName': serializer.toJson<String>(siteName),
      'meshCode': serializer.toJson<String>(meshCode),
      'gatewayHint': serializer.toJson<String?>(gatewayHint),
      'validFromMs': serializer.toJson<int>(validFromMs),
      'validUntilMs': serializer.toJson<int>(validUntilMs),
      'roomsJson': serializer.toJson<String>(roomsJson),
      'joinedAtMs': serializer.toJson<int>(joinedAtMs),
    };
  }

  SiteManifest copyWith({
    String? siteId,
    String? siteName,
    String? meshCode,
    Value<String?> gatewayHint = const Value.absent(),
    int? validFromMs,
    int? validUntilMs,
    String? roomsJson,
    int? joinedAtMs,
  }) => SiteManifest(
    siteId: siteId ?? this.siteId,
    siteName: siteName ?? this.siteName,
    meshCode: meshCode ?? this.meshCode,
    gatewayHint: gatewayHint.present ? gatewayHint.value : this.gatewayHint,
    validFromMs: validFromMs ?? this.validFromMs,
    validUntilMs: validUntilMs ?? this.validUntilMs,
    roomsJson: roomsJson ?? this.roomsJson,
    joinedAtMs: joinedAtMs ?? this.joinedAtMs,
  );
  SiteManifest copyWithCompanion(SiteManifestsCompanion data) {
    return SiteManifest(
      siteId: data.siteId.present ? data.siteId.value : this.siteId,
      siteName: data.siteName.present ? data.siteName.value : this.siteName,
      meshCode: data.meshCode.present ? data.meshCode.value : this.meshCode,
      gatewayHint: data.gatewayHint.present
          ? data.gatewayHint.value
          : this.gatewayHint,
      validFromMs: data.validFromMs.present
          ? data.validFromMs.value
          : this.validFromMs,
      validUntilMs: data.validUntilMs.present
          ? data.validUntilMs.value
          : this.validUntilMs,
      roomsJson: data.roomsJson.present ? data.roomsJson.value : this.roomsJson,
      joinedAtMs: data.joinedAtMs.present
          ? data.joinedAtMs.value
          : this.joinedAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SiteManifest(')
          ..write('siteId: $siteId, ')
          ..write('siteName: $siteName, ')
          ..write('meshCode: $meshCode, ')
          ..write('gatewayHint: $gatewayHint, ')
          ..write('validFromMs: $validFromMs, ')
          ..write('validUntilMs: $validUntilMs, ')
          ..write('roomsJson: $roomsJson, ')
          ..write('joinedAtMs: $joinedAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    siteId,
    siteName,
    meshCode,
    gatewayHint,
    validFromMs,
    validUntilMs,
    roomsJson,
    joinedAtMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SiteManifest &&
          other.siteId == this.siteId &&
          other.siteName == this.siteName &&
          other.meshCode == this.meshCode &&
          other.gatewayHint == this.gatewayHint &&
          other.validFromMs == this.validFromMs &&
          other.validUntilMs == this.validUntilMs &&
          other.roomsJson == this.roomsJson &&
          other.joinedAtMs == this.joinedAtMs);
}

class SiteManifestsCompanion extends UpdateCompanion<SiteManifest> {
  final Value<String> siteId;
  final Value<String> siteName;
  final Value<String> meshCode;
  final Value<String?> gatewayHint;
  final Value<int> validFromMs;
  final Value<int> validUntilMs;
  final Value<String> roomsJson;
  final Value<int> joinedAtMs;
  final Value<int> rowid;
  const SiteManifestsCompanion({
    this.siteId = const Value.absent(),
    this.siteName = const Value.absent(),
    this.meshCode = const Value.absent(),
    this.gatewayHint = const Value.absent(),
    this.validFromMs = const Value.absent(),
    this.validUntilMs = const Value.absent(),
    this.roomsJson = const Value.absent(),
    this.joinedAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SiteManifestsCompanion.insert({
    required String siteId,
    required String siteName,
    required String meshCode,
    this.gatewayHint = const Value.absent(),
    required int validFromMs,
    required int validUntilMs,
    required String roomsJson,
    required int joinedAtMs,
    this.rowid = const Value.absent(),
  }) : siteId = Value(siteId),
       siteName = Value(siteName),
       meshCode = Value(meshCode),
       validFromMs = Value(validFromMs),
       validUntilMs = Value(validUntilMs),
       roomsJson = Value(roomsJson),
       joinedAtMs = Value(joinedAtMs);
  static Insertable<SiteManifest> custom({
    Expression<String>? siteId,
    Expression<String>? siteName,
    Expression<String>? meshCode,
    Expression<String>? gatewayHint,
    Expression<int>? validFromMs,
    Expression<int>? validUntilMs,
    Expression<String>? roomsJson,
    Expression<int>? joinedAtMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (siteId != null) 'site_id': siteId,
      if (siteName != null) 'site_name': siteName,
      if (meshCode != null) 'mesh_code': meshCode,
      if (gatewayHint != null) 'gateway_hint': gatewayHint,
      if (validFromMs != null) 'valid_from_ms': validFromMs,
      if (validUntilMs != null) 'valid_until_ms': validUntilMs,
      if (roomsJson != null) 'rooms_json': roomsJson,
      if (joinedAtMs != null) 'joined_at_ms': joinedAtMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SiteManifestsCompanion copyWith({
    Value<String>? siteId,
    Value<String>? siteName,
    Value<String>? meshCode,
    Value<String?>? gatewayHint,
    Value<int>? validFromMs,
    Value<int>? validUntilMs,
    Value<String>? roomsJson,
    Value<int>? joinedAtMs,
    Value<int>? rowid,
  }) {
    return SiteManifestsCompanion(
      siteId: siteId ?? this.siteId,
      siteName: siteName ?? this.siteName,
      meshCode: meshCode ?? this.meshCode,
      gatewayHint: gatewayHint ?? this.gatewayHint,
      validFromMs: validFromMs ?? this.validFromMs,
      validUntilMs: validUntilMs ?? this.validUntilMs,
      roomsJson: roomsJson ?? this.roomsJson,
      joinedAtMs: joinedAtMs ?? this.joinedAtMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (siteId.present) {
      map['site_id'] = Variable<String>(siteId.value);
    }
    if (siteName.present) {
      map['site_name'] = Variable<String>(siteName.value);
    }
    if (meshCode.present) {
      map['mesh_code'] = Variable<String>(meshCode.value);
    }
    if (gatewayHint.present) {
      map['gateway_hint'] = Variable<String>(gatewayHint.value);
    }
    if (validFromMs.present) {
      map['valid_from_ms'] = Variable<int>(validFromMs.value);
    }
    if (validUntilMs.present) {
      map['valid_until_ms'] = Variable<int>(validUntilMs.value);
    }
    if (roomsJson.present) {
      map['rooms_json'] = Variable<String>(roomsJson.value);
    }
    if (joinedAtMs.present) {
      map['joined_at_ms'] = Variable<int>(joinedAtMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SiteManifestsCompanion(')
          ..write('siteId: $siteId, ')
          ..write('siteName: $siteName, ')
          ..write('meshCode: $meshCode, ')
          ..write('gatewayHint: $gatewayHint, ')
          ..write('validFromMs: $validFromMs, ')
          ..write('validUntilMs: $validUntilMs, ')
          ..write('roomsJson: $roomsJson, ')
          ..write('joinedAtMs: $joinedAtMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$MeshDatabase extends GeneratedDatabase {
  _$MeshDatabase(QueryExecutor e) : super(e);
  $MeshDatabaseManager get managers => $MeshDatabaseManager(this);
  late final $OutboxEventsTable outboxEvents = $OutboxEventsTable(this);
  late final $InboxEventsTable inboxEvents = $InboxEventsTable(this);
  late final $SiteManifestsTable siteManifests = $SiteManifestsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    outboxEvents,
    inboxEvents,
    siteManifests,
  ];
}

typedef $$OutboxEventsTableCreateCompanionBuilder =
    OutboxEventsCompanion Function({
      required String eventId,
      Value<int?> objectId,
      required String siteId,
      required String roomId,
      required String payloadType,
      Value<String?> inputMode,
      Value<String?> rawText,
      Value<String?> transcript,
      Value<String?> triageJson,
      Value<String?> voicePath,
      required String priority,
      Value<Uint8List?> payload,
      Value<String> state,
      required int createdAtMs,
      required int updatedAtMs,
      required int expiresAtMs,
      Value<int> rowid,
    });
typedef $$OutboxEventsTableUpdateCompanionBuilder =
    OutboxEventsCompanion Function({
      Value<String> eventId,
      Value<int?> objectId,
      Value<String> siteId,
      Value<String> roomId,
      Value<String> payloadType,
      Value<String?> inputMode,
      Value<String?> rawText,
      Value<String?> transcript,
      Value<String?> triageJson,
      Value<String?> voicePath,
      Value<String> priority,
      Value<Uint8List?> payload,
      Value<String> state,
      Value<int> createdAtMs,
      Value<int> updatedAtMs,
      Value<int> expiresAtMs,
      Value<int> rowid,
    });

class $$OutboxEventsTableFilterComposer
    extends Composer<_$MeshDatabase, $OutboxEventsTable> {
  $$OutboxEventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get eventId => $composableBuilder(
    column: $table.eventId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get objectId => $composableBuilder(
    column: $table.objectId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get siteId => $composableBuilder(
    column: $table.siteId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get roomId => $composableBuilder(
    column: $table.roomId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadType => $composableBuilder(
    column: $table.payloadType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get inputMode => $composableBuilder(
    column: $table.inputMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rawText => $composableBuilder(
    column: $table.rawText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get transcript => $composableBuilder(
    column: $table.transcript,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get triageJson => $composableBuilder(
    column: $table.triageJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get voicePath => $composableBuilder(
    column: $table.voicePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get expiresAtMs => $composableBuilder(
    column: $table.expiresAtMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OutboxEventsTableOrderingComposer
    extends Composer<_$MeshDatabase, $OutboxEventsTable> {
  $$OutboxEventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get eventId => $composableBuilder(
    column: $table.eventId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get objectId => $composableBuilder(
    column: $table.objectId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get siteId => $composableBuilder(
    column: $table.siteId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get roomId => $composableBuilder(
    column: $table.roomId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadType => $composableBuilder(
    column: $table.payloadType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get inputMode => $composableBuilder(
    column: $table.inputMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rawText => $composableBuilder(
    column: $table.rawText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get transcript => $composableBuilder(
    column: $table.transcript,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get triageJson => $composableBuilder(
    column: $table.triageJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get voicePath => $composableBuilder(
    column: $table.voicePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get expiresAtMs => $composableBuilder(
    column: $table.expiresAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OutboxEventsTableAnnotationComposer
    extends Composer<_$MeshDatabase, $OutboxEventsTable> {
  $$OutboxEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get eventId =>
      $composableBuilder(column: $table.eventId, builder: (column) => column);

  GeneratedColumn<int> get objectId =>
      $composableBuilder(column: $table.objectId, builder: (column) => column);

  GeneratedColumn<String> get siteId =>
      $composableBuilder(column: $table.siteId, builder: (column) => column);

  GeneratedColumn<String> get roomId =>
      $composableBuilder(column: $table.roomId, builder: (column) => column);

  GeneratedColumn<String> get payloadType => $composableBuilder(
    column: $table.payloadType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get inputMode =>
      $composableBuilder(column: $table.inputMode, builder: (column) => column);

  GeneratedColumn<String> get rawText =>
      $composableBuilder(column: $table.rawText, builder: (column) => column);

  GeneratedColumn<String> get transcript => $composableBuilder(
    column: $table.transcript,
    builder: (column) => column,
  );

  GeneratedColumn<String> get triageJson => $composableBuilder(
    column: $table.triageJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get voicePath =>
      $composableBuilder(column: $table.voicePath, builder: (column) => column);

  GeneratedColumn<String> get priority =>
      $composableBuilder(column: $table.priority, builder: (column) => column);

  GeneratedColumn<Uint8List> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get expiresAtMs => $composableBuilder(
    column: $table.expiresAtMs,
    builder: (column) => column,
  );
}

class $$OutboxEventsTableTableManager
    extends
        RootTableManager<
          _$MeshDatabase,
          $OutboxEventsTable,
          OutboxEvent,
          $$OutboxEventsTableFilterComposer,
          $$OutboxEventsTableOrderingComposer,
          $$OutboxEventsTableAnnotationComposer,
          $$OutboxEventsTableCreateCompanionBuilder,
          $$OutboxEventsTableUpdateCompanionBuilder,
          (
            OutboxEvent,
            BaseReferences<_$MeshDatabase, $OutboxEventsTable, OutboxEvent>,
          ),
          OutboxEvent,
          PrefetchHooks Function()
        > {
  $$OutboxEventsTableTableManager(_$MeshDatabase db, $OutboxEventsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OutboxEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OutboxEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OutboxEventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> eventId = const Value.absent(),
                Value<int?> objectId = const Value.absent(),
                Value<String> siteId = const Value.absent(),
                Value<String> roomId = const Value.absent(),
                Value<String> payloadType = const Value.absent(),
                Value<String?> inputMode = const Value.absent(),
                Value<String?> rawText = const Value.absent(),
                Value<String?> transcript = const Value.absent(),
                Value<String?> triageJson = const Value.absent(),
                Value<String?> voicePath = const Value.absent(),
                Value<String> priority = const Value.absent(),
                Value<Uint8List?> payload = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<int> createdAtMs = const Value.absent(),
                Value<int> updatedAtMs = const Value.absent(),
                Value<int> expiresAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OutboxEventsCompanion(
                eventId: eventId,
                objectId: objectId,
                siteId: siteId,
                roomId: roomId,
                payloadType: payloadType,
                inputMode: inputMode,
                rawText: rawText,
                transcript: transcript,
                triageJson: triageJson,
                voicePath: voicePath,
                priority: priority,
                payload: payload,
                state: state,
                createdAtMs: createdAtMs,
                updatedAtMs: updatedAtMs,
                expiresAtMs: expiresAtMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String eventId,
                Value<int?> objectId = const Value.absent(),
                required String siteId,
                required String roomId,
                required String payloadType,
                Value<String?> inputMode = const Value.absent(),
                Value<String?> rawText = const Value.absent(),
                Value<String?> transcript = const Value.absent(),
                Value<String?> triageJson = const Value.absent(),
                Value<String?> voicePath = const Value.absent(),
                required String priority,
                Value<Uint8List?> payload = const Value.absent(),
                Value<String> state = const Value.absent(),
                required int createdAtMs,
                required int updatedAtMs,
                required int expiresAtMs,
                Value<int> rowid = const Value.absent(),
              }) => OutboxEventsCompanion.insert(
                eventId: eventId,
                objectId: objectId,
                siteId: siteId,
                roomId: roomId,
                payloadType: payloadType,
                inputMode: inputMode,
                rawText: rawText,
                transcript: transcript,
                triageJson: triageJson,
                voicePath: voicePath,
                priority: priority,
                payload: payload,
                state: state,
                createdAtMs: createdAtMs,
                updatedAtMs: updatedAtMs,
                expiresAtMs: expiresAtMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OutboxEventsTableProcessedTableManager =
    ProcessedTableManager<
      _$MeshDatabase,
      $OutboxEventsTable,
      OutboxEvent,
      $$OutboxEventsTableFilterComposer,
      $$OutboxEventsTableOrderingComposer,
      $$OutboxEventsTableAnnotationComposer,
      $$OutboxEventsTableCreateCompanionBuilder,
      $$OutboxEventsTableUpdateCompanionBuilder,
      (
        OutboxEvent,
        BaseReferences<_$MeshDatabase, $OutboxEventsTable, OutboxEvent>,
      ),
      OutboxEvent,
      PrefetchHooks Function()
    >;
typedef $$InboxEventsTableCreateCompanionBuilder =
    InboxEventsCompanion Function({
      Value<int> objectId,
      required String eventId,
      required String siteId,
      required String roomId,
      required String payloadType,
      required Uint8List payload,
      required String peerId,
      required int receivedAtMs,
    });
typedef $$InboxEventsTableUpdateCompanionBuilder =
    InboxEventsCompanion Function({
      Value<int> objectId,
      Value<String> eventId,
      Value<String> siteId,
      Value<String> roomId,
      Value<String> payloadType,
      Value<Uint8List> payload,
      Value<String> peerId,
      Value<int> receivedAtMs,
    });

class $$InboxEventsTableFilterComposer
    extends Composer<_$MeshDatabase, $InboxEventsTable> {
  $$InboxEventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get objectId => $composableBuilder(
    column: $table.objectId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get eventId => $composableBuilder(
    column: $table.eventId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get siteId => $composableBuilder(
    column: $table.siteId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get roomId => $composableBuilder(
    column: $table.roomId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadType => $composableBuilder(
    column: $table.payloadType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get peerId => $composableBuilder(
    column: $table.peerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get receivedAtMs => $composableBuilder(
    column: $table.receivedAtMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$InboxEventsTableOrderingComposer
    extends Composer<_$MeshDatabase, $InboxEventsTable> {
  $$InboxEventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get objectId => $composableBuilder(
    column: $table.objectId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get eventId => $composableBuilder(
    column: $table.eventId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get siteId => $composableBuilder(
    column: $table.siteId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get roomId => $composableBuilder(
    column: $table.roomId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadType => $composableBuilder(
    column: $table.payloadType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get peerId => $composableBuilder(
    column: $table.peerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get receivedAtMs => $composableBuilder(
    column: $table.receivedAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$InboxEventsTableAnnotationComposer
    extends Composer<_$MeshDatabase, $InboxEventsTable> {
  $$InboxEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get objectId =>
      $composableBuilder(column: $table.objectId, builder: (column) => column);

  GeneratedColumn<String> get eventId =>
      $composableBuilder(column: $table.eventId, builder: (column) => column);

  GeneratedColumn<String> get siteId =>
      $composableBuilder(column: $table.siteId, builder: (column) => column);

  GeneratedColumn<String> get roomId =>
      $composableBuilder(column: $table.roomId, builder: (column) => column);

  GeneratedColumn<String> get payloadType => $composableBuilder(
    column: $table.payloadType,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<String> get peerId =>
      $composableBuilder(column: $table.peerId, builder: (column) => column);

  GeneratedColumn<int> get receivedAtMs => $composableBuilder(
    column: $table.receivedAtMs,
    builder: (column) => column,
  );
}

class $$InboxEventsTableTableManager
    extends
        RootTableManager<
          _$MeshDatabase,
          $InboxEventsTable,
          InboxEvent,
          $$InboxEventsTableFilterComposer,
          $$InboxEventsTableOrderingComposer,
          $$InboxEventsTableAnnotationComposer,
          $$InboxEventsTableCreateCompanionBuilder,
          $$InboxEventsTableUpdateCompanionBuilder,
          (
            InboxEvent,
            BaseReferences<_$MeshDatabase, $InboxEventsTable, InboxEvent>,
          ),
          InboxEvent,
          PrefetchHooks Function()
        > {
  $$InboxEventsTableTableManager(_$MeshDatabase db, $InboxEventsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$InboxEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$InboxEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$InboxEventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> objectId = const Value.absent(),
                Value<String> eventId = const Value.absent(),
                Value<String> siteId = const Value.absent(),
                Value<String> roomId = const Value.absent(),
                Value<String> payloadType = const Value.absent(),
                Value<Uint8List> payload = const Value.absent(),
                Value<String> peerId = const Value.absent(),
                Value<int> receivedAtMs = const Value.absent(),
              }) => InboxEventsCompanion(
                objectId: objectId,
                eventId: eventId,
                siteId: siteId,
                roomId: roomId,
                payloadType: payloadType,
                payload: payload,
                peerId: peerId,
                receivedAtMs: receivedAtMs,
              ),
          createCompanionCallback:
              ({
                Value<int> objectId = const Value.absent(),
                required String eventId,
                required String siteId,
                required String roomId,
                required String payloadType,
                required Uint8List payload,
                required String peerId,
                required int receivedAtMs,
              }) => InboxEventsCompanion.insert(
                objectId: objectId,
                eventId: eventId,
                siteId: siteId,
                roomId: roomId,
                payloadType: payloadType,
                payload: payload,
                peerId: peerId,
                receivedAtMs: receivedAtMs,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$InboxEventsTableProcessedTableManager =
    ProcessedTableManager<
      _$MeshDatabase,
      $InboxEventsTable,
      InboxEvent,
      $$InboxEventsTableFilterComposer,
      $$InboxEventsTableOrderingComposer,
      $$InboxEventsTableAnnotationComposer,
      $$InboxEventsTableCreateCompanionBuilder,
      $$InboxEventsTableUpdateCompanionBuilder,
      (
        InboxEvent,
        BaseReferences<_$MeshDatabase, $InboxEventsTable, InboxEvent>,
      ),
      InboxEvent,
      PrefetchHooks Function()
    >;
typedef $$SiteManifestsTableCreateCompanionBuilder =
    SiteManifestsCompanion Function({
      required String siteId,
      required String siteName,
      required String meshCode,
      Value<String?> gatewayHint,
      required int validFromMs,
      required int validUntilMs,
      required String roomsJson,
      required int joinedAtMs,
      Value<int> rowid,
    });
typedef $$SiteManifestsTableUpdateCompanionBuilder =
    SiteManifestsCompanion Function({
      Value<String> siteId,
      Value<String> siteName,
      Value<String> meshCode,
      Value<String?> gatewayHint,
      Value<int> validFromMs,
      Value<int> validUntilMs,
      Value<String> roomsJson,
      Value<int> joinedAtMs,
      Value<int> rowid,
    });

class $$SiteManifestsTableFilterComposer
    extends Composer<_$MeshDatabase, $SiteManifestsTable> {
  $$SiteManifestsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get siteId => $composableBuilder(
    column: $table.siteId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get siteName => $composableBuilder(
    column: $table.siteName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get meshCode => $composableBuilder(
    column: $table.meshCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get gatewayHint => $composableBuilder(
    column: $table.gatewayHint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get validFromMs => $composableBuilder(
    column: $table.validFromMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get validUntilMs => $composableBuilder(
    column: $table.validUntilMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get roomsJson => $composableBuilder(
    column: $table.roomsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get joinedAtMs => $composableBuilder(
    column: $table.joinedAtMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SiteManifestsTableOrderingComposer
    extends Composer<_$MeshDatabase, $SiteManifestsTable> {
  $$SiteManifestsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get siteId => $composableBuilder(
    column: $table.siteId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get siteName => $composableBuilder(
    column: $table.siteName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get meshCode => $composableBuilder(
    column: $table.meshCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get gatewayHint => $composableBuilder(
    column: $table.gatewayHint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get validFromMs => $composableBuilder(
    column: $table.validFromMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get validUntilMs => $composableBuilder(
    column: $table.validUntilMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get roomsJson => $composableBuilder(
    column: $table.roomsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get joinedAtMs => $composableBuilder(
    column: $table.joinedAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SiteManifestsTableAnnotationComposer
    extends Composer<_$MeshDatabase, $SiteManifestsTable> {
  $$SiteManifestsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get siteId =>
      $composableBuilder(column: $table.siteId, builder: (column) => column);

  GeneratedColumn<String> get siteName =>
      $composableBuilder(column: $table.siteName, builder: (column) => column);

  GeneratedColumn<String> get meshCode =>
      $composableBuilder(column: $table.meshCode, builder: (column) => column);

  GeneratedColumn<String> get gatewayHint => $composableBuilder(
    column: $table.gatewayHint,
    builder: (column) => column,
  );

  GeneratedColumn<int> get validFromMs => $composableBuilder(
    column: $table.validFromMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get validUntilMs => $composableBuilder(
    column: $table.validUntilMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get roomsJson =>
      $composableBuilder(column: $table.roomsJson, builder: (column) => column);

  GeneratedColumn<int> get joinedAtMs => $composableBuilder(
    column: $table.joinedAtMs,
    builder: (column) => column,
  );
}

class $$SiteManifestsTableTableManager
    extends
        RootTableManager<
          _$MeshDatabase,
          $SiteManifestsTable,
          SiteManifest,
          $$SiteManifestsTableFilterComposer,
          $$SiteManifestsTableOrderingComposer,
          $$SiteManifestsTableAnnotationComposer,
          $$SiteManifestsTableCreateCompanionBuilder,
          $$SiteManifestsTableUpdateCompanionBuilder,
          (
            SiteManifest,
            BaseReferences<_$MeshDatabase, $SiteManifestsTable, SiteManifest>,
          ),
          SiteManifest,
          PrefetchHooks Function()
        > {
  $$SiteManifestsTableTableManager(_$MeshDatabase db, $SiteManifestsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SiteManifestsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SiteManifestsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SiteManifestsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> siteId = const Value.absent(),
                Value<String> siteName = const Value.absent(),
                Value<String> meshCode = const Value.absent(),
                Value<String?> gatewayHint = const Value.absent(),
                Value<int> validFromMs = const Value.absent(),
                Value<int> validUntilMs = const Value.absent(),
                Value<String> roomsJson = const Value.absent(),
                Value<int> joinedAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SiteManifestsCompanion(
                siteId: siteId,
                siteName: siteName,
                meshCode: meshCode,
                gatewayHint: gatewayHint,
                validFromMs: validFromMs,
                validUntilMs: validUntilMs,
                roomsJson: roomsJson,
                joinedAtMs: joinedAtMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String siteId,
                required String siteName,
                required String meshCode,
                Value<String?> gatewayHint = const Value.absent(),
                required int validFromMs,
                required int validUntilMs,
                required String roomsJson,
                required int joinedAtMs,
                Value<int> rowid = const Value.absent(),
              }) => SiteManifestsCompanion.insert(
                siteId: siteId,
                siteName: siteName,
                meshCode: meshCode,
                gatewayHint: gatewayHint,
                validFromMs: validFromMs,
                validUntilMs: validUntilMs,
                roomsJson: roomsJson,
                joinedAtMs: joinedAtMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SiteManifestsTableProcessedTableManager =
    ProcessedTableManager<
      _$MeshDatabase,
      $SiteManifestsTable,
      SiteManifest,
      $$SiteManifestsTableFilterComposer,
      $$SiteManifestsTableOrderingComposer,
      $$SiteManifestsTableAnnotationComposer,
      $$SiteManifestsTableCreateCompanionBuilder,
      $$SiteManifestsTableUpdateCompanionBuilder,
      (
        SiteManifest,
        BaseReferences<_$MeshDatabase, $SiteManifestsTable, SiteManifest>,
      ),
      SiteManifest,
      PrefetchHooks Function()
    >;

class $MeshDatabaseManager {
  final _$MeshDatabase _db;
  $MeshDatabaseManager(this._db);
  $$OutboxEventsTableTableManager get outboxEvents =>
      $$OutboxEventsTableTableManager(_db, _db.outboxEvents);
  $$InboxEventsTableTableManager get inboxEvents =>
      $$InboxEventsTableTableManager(_db, _db.inboxEvents);
  $$SiteManifestsTableTableManager get siteManifests =>
      $$SiteManifestsTableTableManager(_db, _db.siteManifests);
}
