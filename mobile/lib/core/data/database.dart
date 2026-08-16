import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

/// Durable outbox/inbox for the Flutter app (Bible §2.5). Every locally
/// authored event (SOS draft, room message, voice manifest) has a state
/// machine `created -> ready -> relaying -> acked|expired`. This table is
/// the queue, not just UI storage: `feature/sos` and `feature/rooms` both
/// write rows here and `MeshTransportCoordinator` is fed from `ready` rows.
class OutboxEvents extends Table {
  TextColumn get eventId => text()(); // UUID, primary key
  IntColumn get objectId => integer().nullable()(); // assigned at finalize
  TextColumn get siteId => text()();
  TextColumn get roomId => text()();
  TextColumn get payloadType => text()(); // PayloadType enum name
  TextColumn get inputMode => text().nullable()(); // InputMode enum name
  TextColumn get rawText => text().nullable()();
  TextColumn get transcript => text().nullable()();
  TextColumn get triageJson => text().nullable()();
  TextColumn get voicePath => text().nullable()();
  TextColumn get priority => text()(); // PriorityBand enum name
  BlobColumn get payload => blob().nullable()(); // serialized app payload
  TextColumn get state => text().withDefault(const Constant('created'))();
  IntColumn get createdAtMs => integer()();
  IntColumn get updatedAtMs => integer()();
  IntColumn get expiresAtMs => integer()();

  @override
  Set<Column> get primaryKey => {eventId};
}

/// Reassembled objects received from peers (room chat + SOS forwarded to
/// this device), kept for UI display and dashboard/gateway evidence.
class InboxEvents extends Table {
  IntColumn get objectId => integer()();
  TextColumn get eventId => text()();
  TextColumn get siteId => text()();
  TextColumn get roomId => text()();
  TextColumn get payloadType => text()();
  BlobColumn get payload => blob()();
  TextColumn get peerId => text()();
  IntColumn get receivedAtMs => integer()();

  @override
  Set<Column> get primaryKey => {objectId};
}

/// Site manifest loaded via Mesh Code / QR join (Bible §3.1, `feature/join`).
class SiteManifests extends Table {
  TextColumn get siteId => text()();
  TextColumn get siteName => text()();
  TextColumn get meshCode => text()();
  TextColumn get gatewayHint => text().nullable()();
  IntColumn get validFromMs => integer()();
  IntColumn get validUntilMs => integer()();
  TextColumn get roomsJson => text()(); // encoded List<RoomManifest>
  IntColumn get joinedAtMs => integer()();

  @override
  Set<Column> get primaryKey => {siteId};
}

@DriftDatabase(tables: [OutboxEvents, InboxEvents, SiteManifests])
class MeshDatabase extends _$MeshDatabase {
  MeshDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  MeshDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  static QueryExecutor _open() =>
      driftDatabase(name: 'meshsetu', native: const DriftNativeOptions());

  Stream<List<OutboxEvent>> watchReady(String siteId) => (select(
    outboxEvents,
  )..where((t) => t.siteId.equals(siteId) & t.state.equals('ready'))).watch();

  Stream<List<OutboxEvent>> watchRoom(String siteId, String roomId) =>
      (select(outboxEvents)
            ..where((t) => t.siteId.equals(siteId) & t.roomId.equals(roomId))
            ..orderBy([(t) => OrderingTerm.asc(t.createdAtMs)]))
          .watch();

  Stream<List<InboxEvent>> watchInboxRoom(String siteId, String roomId) =>
      (select(inboxEvents)
            ..where((t) => t.siteId.equals(siteId) & t.roomId.equals(roomId))
            ..orderBy([(t) => OrderingTerm.asc(t.receivedAtMs)]))
          .watch();

  Stream<List<InboxEvent>> watchInboxSite(String siteId) =>
      (select(inboxEvents)
            ..where((t) => t.siteId.equals(siteId))
            ..orderBy([(t) => OrderingTerm.asc(t.receivedAtMs)]))
          .watch();

  Future<void> markState(String eventId, String state, int nowMs) =>
      (update(outboxEvents)..where((t) => t.eventId.equals(eventId))).write(
        OutboxEventsCompanion(state: Value(state), updatedAtMs: Value(nowMs)),
      );

  Future<void> expireOverdue(int nowMs) =>
      (update(outboxEvents)..where(
            (t) =>
                t.expiresAtMs.isSmallerThanValue(nowMs) &
                t.state.isNotValue('acked'),
          ))
          .write(
            OutboxEventsCompanion(
              state: const Value('expired'),
              updatedAtMs: Value(nowMs),
            ),
          );

  Future<void> insertInbox(InboxEventsCompanion row) =>
      into(inboxEvents).insertOnConflictUpdate(row);

  Future<SiteManifest?> currentSite() async {
    final rows = await (select(
      siteManifests,
    )..orderBy([(t) => OrderingTerm.desc(t.joinedAtMs)])).get();
    return rows.isEmpty ? null : rows.first;
  }
}
