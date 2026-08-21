import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshsetu_mobile/core/ble/gatt_server.dart';
import 'package:meshsetu_mobile/core/ble/mesh_gatt.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:universal_ble/src/universal_ble.g.dart' show PeripheralService;

class _DelayedPeripheral extends UniversalBlePeripheralUnsupported {
  PeripheralService? requestedService;
  OnPeripheralWriteRequest? writeRequestHandler;
  Completer<void>? notificationGate;
  bool emitNotificationCallback = true;

  @override
  void setWriteRequestHandler(OnPeripheralWriteRequest? handler) {
    writeRequestHandler = handler;
  }

  @override
  Future<void> addService(
    PeripheralService service, {
    bool primary = true,
    Duration? timeout,
  }) async {
    requestedService = service;
  }

  @override
  Future<void> clearServices() async {}

  @override
  Future<void> updateCharacteristicValueWithId({
    required String characteristicId,
    required Uint8List value,
    required int notificationId,
    String? deviceId,
  }) async {
    await notificationGate?.future;
    if (emitNotificationCallback && deviceId != null) {
      updateNotificationSent(
        BlePeripheralNotificationSent(deviceId, 0, notificationId, value),
      );
    }
  }

  void completeService([String? error]) {
    final service = requestedService;
    if (service == null) throw StateError('addService was not called');
    updateServiceAdded(BlePeripheralServiceAdded(service.uuid, error));
  }
}

Future<void> _subscribe(
  _DelayedPeripheral peripheral, [
  String id = 'peer',
]) async {
  peripheral.updateConnectionState(
    BlePeripheralConnectionStateChanged(id, true),
  );
  peripheral.updateCharacteristicSubscription(
    BlePeripheralCharacteristicSubscriptionChanged(
      deviceId: id,
      characteristicId: MeshGatt.tx,
      isSubscribed: true,
      name: null,
    ),
  );
  await Future<void>.delayed(Duration.zero);
}

Future<void> _startServer(
  MeshGattServer server,
  _DelayedPeripheral peripheral,
) async {
  final start = server.start();
  await Future<void>.delayed(Duration.zero);
  peripheral.completeService();
  await start;
}

void main() {
  test('server does not complete startup until serviceAdded arrives', () async {
    final peripheral = _DelayedPeripheral();
    UniversalBlePeripheral.setInstance(peripheral);
    addTearDown(
      () => UniversalBlePeripheral.setInstance(
        UniversalBlePeripheralUnsupported(),
      ),
    );

    final server = MeshGattServer();
    var completed = false;
    final start = server.start().then((_) => completed = true);
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);

    peripheral.completeService();
    await start;
    expect(completed, isTrue);
    await server.stop();
  });

  test('service registration failure never reports a ready server', () async {
    final peripheral = _DelayedPeripheral();
    UniversalBlePeripheral.setInstance(peripheral);
    addTearDown(
      () => UniversalBlePeripheral.setInstance(
        UniversalBlePeripheralUnsupported(),
      ),
    );

    final server = MeshGattServer();
    final start = server.start();
    await Future<void>.delayed(Duration.zero);
    peripheral.completeService('gatt_service_registration_failed');
    await expectLater(start, throwsA(isA<StateError>()));
    await server.stop();
  });

  test('RX requires admission and enforces length and queue bounds', () async {
    final peripheral = _DelayedPeripheral();
    UniversalBlePeripheral.setInstance(peripheral);
    addTearDown(
      () => UniversalBlePeripheral.setInstance(
        UniversalBlePeripheralUnsupported(),
      ),
    );
    final server = MeshGattServer();
    final received = <IncomingGattFrame>[];
    final subscription = server.incoming.listen(received.add);
    await _startServer(server, peripheral);
    await _subscribe(peripheral);

    expect(
      peripheral.writeRequestHandler?.call(
        'peer',
        MeshGatt.rx,
        0,
        Uint8List.fromList([1]),
      ),
      isNotNull,
    );
    expect(server.admitPeer('peer'), isTrue);
    for (final invalidLength in [0, MeshGatt.maxAttributeValueBytes + 1]) {
      expect(
        peripheral.writeRequestHandler
            ?.call('peer', MeshGatt.rx, 0, Uint8List(invalidLength))
            ?.status,
        13,
      );
    }
    expect(
      peripheral.writeRequestHandler?.call(
        'peer',
        MeshGatt.rx,
        0,
        Uint8List(MeshGatt.maxAttributeValueBytes),
      ),
      isNull,
    );
    await Future<void>.delayed(Duration.zero);
    server.acknowledge(received.single);

    for (var index = 0; index < 64; index++) {
      expect(
        peripheral.writeRequestHandler?.call(
          'peer',
          MeshGatt.rx,
          0,
          Uint8List.fromList([index]),
        ),
        isNull,
      );
    }
    expect(
      peripheral.writeRequestHandler
          ?.call('peer', MeshGatt.rx, 0, Uint8List.fromList([65]))
          ?.status,
      1,
    );
    await Future<void>.delayed(Duration.zero);
    server.acknowledge(received.last);
    expect(
      peripheral.writeRequestHandler?.call(
        'peer',
        MeshGatt.rx,
        0,
        Uint8List.fromList([66]),
      ),
      isNull,
    );

    await subscription.cancel();
    await server.stop();
  });

  test('disconnect during an Android notification returns false', () async {
    final peripheral = _DelayedPeripheral()
      ..notificationGate = Completer<void>();
    UniversalBlePeripheral.setInstance(peripheral);
    final previousTarget = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = previousTarget;
      UniversalBlePeripheral.setInstance(UniversalBlePeripheralUnsupported());
    });
    final server = MeshGattServer();
    await _startServer(server, peripheral);
    await _subscribe(peripheral);
    expect(server.admitPeer('peer'), isTrue);

    final notification = server.notifyAwait('peer', Uint8List.fromList([1]));
    await Future<void>.delayed(Duration.zero);
    peripheral.updateConnectionState(
      BlePeripheralConnectionStateChanged('peer', false),
    );
    peripheral.notificationGate!.complete();

    expect(await notification, isFalse);
    await server.stop();
  });

  test('unsubscribe during an Android notification returns false', () async {
    final peripheral = _DelayedPeripheral()
      ..notificationGate = Completer<void>();
    UniversalBlePeripheral.setInstance(peripheral);
    final previousTarget = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = previousTarget;
      UniversalBlePeripheral.setInstance(UniversalBlePeripheralUnsupported());
    });
    final server = MeshGattServer();
    await _startServer(server, peripheral);
    await _subscribe(peripheral);
    expect(server.admitPeer('peer'), isTrue);

    final notification = server.notifyAwait('peer', Uint8List.fromList([1]));
    await Future<void>.delayed(Duration.zero);
    peripheral.updateCharacteristicSubscription(
      BlePeripheralCharacteristicSubscriptionChanged(
        deviceId: 'peer',
        characteristicId: MeshGatt.tx,
        isSubscribed: false,
        name: null,
      ),
    );
    peripheral.notificationGate!.complete();

    expect(await notification, isFalse);
    await server.stop();
  });

  test('Android notification callback timeout is configurable', () async {
    final diagnostics = <String>[];
    final peripheral = _DelayedPeripheral()..emitNotificationCallback = false;
    UniversalBlePeripheral.setInstance(peripheral);
    final previousTarget = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = previousTarget;
      UniversalBlePeripheral.setInstance(UniversalBlePeripheralUnsupported());
    });
    final server = MeshGattServer(
      notificationTimeout: const Duration(milliseconds: 1),
      onDiagnostic: (kind, _, {detail, value}) {
        if (detail != null) diagnostics.add(detail);
      },
    );
    await _startServer(server, peripheral);
    await _subscribe(peripheral);
    expect(server.admitPeer('peer'), isTrue);

    expect(await server.notifyAwait('peer', Uint8List.fromList([1])), isFalse);
    expect(diagnostics, contains('callback_timeout'));
    await server.stop();
  });
}
