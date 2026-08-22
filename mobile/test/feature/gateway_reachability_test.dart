import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshsetu_mobile/feature/gateway/gateway_bridge.dart';

void main() {
  group('control-room reachability', () {
    test(
      'allows automatic detail resolution only when the service is reachable',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((request) async {
          expect(request.uri.path, '/health');
          request.response.statusCode = HttpStatus.noContent;
          await request.response.close();
        });
        addTearDown(server.close);

        final bridge = GatewayBridge(
          baseUrl: Uri.parse('http://${server.address.address}:${server.port}'),
          demoKey: 'test-key',
        );

        expect(await bridge.canReachControlRoom(), isTrue);
      },
    );

    test(
      'keeps the compact fallback when the control room returns a server error',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((request) async {
          request.response.statusCode = HttpStatus.serviceUnavailable;
          await request.response.close();
        });
        addTearDown(server.close);

        final bridge = GatewayBridge(
          baseUrl: Uri.parse('http://${server.address.address}:${server.port}'),
          demoKey: 'test-key',
        );

        expect(await bridge.canReachControlRoom(), isFalse);
      },
    );
  });
}
