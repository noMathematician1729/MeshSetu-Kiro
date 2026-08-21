import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshsetu_mobile/core/ble/gatt_peer_session.dart';
import 'package:meshsetu_mobile/core/ble/mesh_gatt.dart';
import 'package:universal_ble/universal_ble.dart';

class _FakeCentral extends UniversalBlePlatform {
  final calls = <String>[];
  Completer<int>? mtuGate;
  bool timeoutMtu = false;
  bool failCccd = false;
  bool emitNotificationDuringCccd = false;
  String? disconnectDuring;

  final services = [
    BleService(MeshGatt.service, [
      BleCharacteristic(MeshGatt.rx, const [
        CharacteristicProperty.write,
      ], const []),
      BleCharacteristic(
        MeshGatt.tx,
        const [CharacteristicProperty.notify],
        [BleDescriptor(MeshGatt.cccd)],
      ),
    ]),
  ];

  @override
  Future<AvailabilityState> getBluetoothAvailabilityState() async =>
      AvailabilityState.poweredOn;

  @override
  Future<bool> enableBluetooth() async => true;

  @override
  Future<bool> disableBluetooth() async => true;

  @override
  Future<void> startScan({
    ScanFilter? scanFilter,
    PlatformConfig? platformConfig,
  }) async {}

  @override
  Future<void> stopScan() async {}

  @override
  Future<bool> isScanning() async => false;

  @override
  Future<void> connect(
    String deviceId, {
    Duration? connectionTimeout,
    bool autoConnect = false,
    ConnectionPlatformConfig? platformConfig,
  }) async {
    calls.add('connect');
    updateConnection(deviceId, true);
    if (disconnectDuring == 'connect') updateConnection(deviceId, false);
  }

  @override
  Future<void> disconnect(String deviceId) async {
    calls.add('disconnect');
    updateConnection(deviceId, false);
  }

  @override
  Future<List<BleService>> discoverServices(
    String deviceId,
    bool withDescriptors,
  ) async {
    calls.add('discover_services');
    if (disconnectDuring == 'discover_services') {
      updateConnection(deviceId, false);
    }
    return services;
  }

  @override
  Future<void> setNotifiable(
    String deviceId,
    String service,
    String characteristic,
    BleInputProperty bleInputProperty,
  ) async {
    calls.add('write_cccd');
    if (disconnectDuring == 'write_cccd') updateConnection(deviceId, false);
    if (failCccd) throw StateError('cccd_write_failed');
    if (emitNotificationDuringCccd) {
      updateCharacteristicValue(
        deviceId,
        MeshGatt.tx,
        Uint8List.fromList([0xAC, 0xDC]),
        null,
      );
    }
  }

  @override
  Future<Uint8List> readValue(
    String deviceId,
    String service,
    String characteristic, {
    Duration? timeout,
  }) async => Uint8List(0);

  @override
  Future<void> writeValue(
    String deviceId,
    String service,
    String characteristic,
    Uint8List value,
    BleOutputProperty bleOutputProperty,
  ) async {
    calls.add('write_rx');
  }

  @override
  Future<int> requestMtu(String deviceId, int expectedMtu) async {
    calls.add('request_mtu');
    if (disconnectDuring == 'request_mtu') {
      updateConnection(deviceId, false);
    }
    if (timeoutMtu) throw TimeoutException('mtu callback missing');
    return mtuGate?.future ?? 185;
  }

  @override
  Future<int> readRssi(String deviceId) async => -40;

  @override
  Future<void> requestConnectionPriority(
    String deviceId,
    BleConnectionPriority priority,
  ) async {}

  @override
  Future<bool> isPaired(String deviceId) async => false;

  @override
  Future<bool> pair(String deviceId) async => false;

  @override
  Future<void> unpair(String deviceId) async {}

  @override
  Future<BleConnectionState> getConnectionState(String deviceId) async =>
      BleConnectionState.connected;

  @override
  Future<List<BleDevice>> getSystemDevices(List<String>? withServices) async =>
      const [];
}

void main() {
  test(
    'client setup waits for MTU callback before discovery and CCCD',
    () async {
      final central = _FakeCentral()..mtuGate = Completer<int>();
      UniversalBle.setInstance(central);
      addTearDown(() => UniversalBle.setInstance(_FakeCentral()));

      final session = GattPeerSession.open('AA:BB:CC:DD:EE:FF');
      await Future<void>.delayed(Duration.zero);
      expect(central.calls, ['connect', 'request_mtu']);

      central.emitNotificationDuringCccd = true;
      central.mtuGate!.complete(185);
      await session.awaitReady();

      expect(central.calls, [
        'connect',
        'request_mtu',
        'discover_services',
        'write_cccd',
      ]);
      expect(session.state, PeerSessionState.ready);
      expect(session.mtu, 185);
      expect(await session.incoming.first, orderedEquals([0xAC, 0xDC]));
      await session.close();
    },
  );

  test('client rejects a MeshSetu service without a CCCD', () async {
    final central = _FakeCentral()
      ..services[0].characteristics[1].descriptors.clear();
    UniversalBle.setInstance(central);
    addTearDown(() => UniversalBle.setInstance(_FakeCentral()));

    final session = GattPeerSession.open('AA:BB:CC:DD:EE:FF');
    await expectLater(session.awaitReady(), throwsA(isA<StateError>()));
    expect(session.state, PeerSessionState.failed);
    expect(session.phase, 'validate_attributes');
    expect(session.failure, contains('cccd_missing'));
    await session.close();
  });

  test('client does not discover services after an MTU timeout', () async {
    final central = _FakeCentral()..timeoutMtu = true;
    UniversalBle.setInstance(central);
    addTearDown(() => UniversalBle.setInstance(_FakeCentral()));

    final session = GattPeerSession.open('AA:BB:CC:DD:EE:FF');
    await expectLater(session.awaitReady(), throwsA(isA<TimeoutException>()));
    expect(central.calls, ['connect', 'request_mtu']);
    expect(session.state, PeerSessionState.failed);
    await session.close();
  });

  test('client does not become ready after a CCCD write failure', () async {
    final central = _FakeCentral()..failCccd = true;
    UniversalBle.setInstance(central);
    addTearDown(() => UniversalBle.setInstance(_FakeCentral()));

    final session = GattPeerSession.open('AA:BB:CC:DD:EE:FF');
    await expectLater(session.awaitReady(), throwsA(isA<StateError>()));
    expect(session.state, PeerSessionState.failed);
    expect(session.phase, 'subscribe_notifications');
    expect(central.calls, [
      'connect',
      'request_mtu',
      'discover_services',
      'write_cccd',
    ]);
    await session.close();
  });

  test('late MTU completion cannot restart a timed-out session', () async {
    final central = _FakeCentral()..mtuGate = Completer<int>();
    UniversalBle.setInstance(central);
    addTearDown(() => UniversalBle.setInstance(_FakeCentral()));

    final session = GattPeerSession.open(
      'AA:BB:CC:DD:EE:FF',
      mtuTimeout: const Duration(milliseconds: 1),
    );
    await expectLater(session.awaitReady(), throwsA(isA<TimeoutException>()));
    central.mtuGate!.complete(517);
    await Future<void>.delayed(Duration.zero);

    expect(central.calls, ['connect', 'request_mtu']);
    expect(session.state, PeerSessionState.failed);
    expect(session.mtu, 23);
    await session.close();
  });

  test('disconnect during every setup phase prevents readiness', () async {
    for (final phase in [
      'connect',
      'request_mtu',
      'discover_services',
      'write_cccd',
    ]) {
      final central = _FakeCentral()..disconnectDuring = phase;
      UniversalBle.setInstance(central);
      final session = GattPeerSession.open('peer-$phase');

      await expectLater(session.awaitReady(), throwsA(isA<StateError>()));
      expect(session.state, PeerSessionState.disconnected, reason: phase);
      await session.close();
    }
    UniversalBle.setInstance(_FakeCentral());
  });

  test('rapid ready-close cycles leave every session disconnected', () async {
    final central = _FakeCentral();
    UniversalBle.setInstance(central);
    addTearDown(() => UniversalBle.setInstance(_FakeCentral()));

    for (var index = 0; index < 20; index++) {
      final session = GattPeerSession.open('peer-$index');
      await session.awaitReady();
      await session.close();
      expect(session.state, PeerSessionState.disconnected);
    }
    expect(central.calls.where((call) => call == 'connect'), hasLength(20));
    expect(central.calls.where((call) => call == 'disconnect'), hasLength(20));
  });
}
