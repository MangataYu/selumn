import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_http/moodiary_http.dart';

void main() {
  // moodiary_rust/hook/build.dart builds host native assets only on Windows.
  // Linux/macOS host tests intentionally skip that hook and cannot load FRB.
  final skip = io.Platform.isWindows
      ? false
      : 'Native HTTP integration requires Windows host assets; '
            'moodiary_rust skips Linux/macOS host builds.';
  for (final status in [307, 308]) {
    test(
      'maxRedirects zero does not forward POST credentials on $status',
      () async {
        final endpoints = await _RedirectEndpoints.start(status);
        addTearDown(endpoints.close);
        final client = RustHttpClient(maxRedirects: 0);

        final response = await client.requestBytes(
          HttpMethod.post,
          endpoints.originUrl,
          body: HttpBody.json(const {'password': 'test-only-password'}),
          headers: const {'Authorization': 'Bearer test-only-token'},
          throwOnStatus: false,
          silent: true,
        );

        expect(response.statusCode, status);
        expect(endpoints.originRequests, 1);
        expect(endpoints.destinationRequests, isEmpty);
      },
      skip: skip,
    );

    test(
      'default client retains existing POST redirect behavior on $status',
      () async {
        final endpoints = await _RedirectEndpoints.start(status);
        addTearDown(endpoints.close);
        final client = RustHttpClient();
        const payload = {'example': 'ordinary-request'};

        final response = await client.requestBytes(
          HttpMethod.post,
          endpoints.originUrl,
          body: HttpBody.json(payload),
          throwOnStatus: false,
          silent: true,
        );

        expect(response.statusCode, 200);
        expect(endpoints.originRequests, 1);
        expect(endpoints.destinationRequests, hasLength(1));
        expect(endpoints.destinationRequests.single.method, 'POST');
        expect(endpoints.destinationRequests.single.body, payload);
      },
      skip: skip,
    );
  }
}

class _RedirectEndpoints {
  _RedirectEndpoints(this.origin, this.destination);

  final io.HttpServer origin;
  final io.HttpServer destination;
  int originRequests = 0;
  final destinationRequests = <({String method, Object? body})>[];

  String get originUrl => 'http://127.0.0.1:${origin.port}/v1/auth/login';

  static Future<_RedirectEndpoints> start(int status) async {
    final destination = await io.HttpServer.bind(
      io.InternetAddress.loopbackIPv4,
      0,
    );
    final io.HttpServer origin;
    try {
      origin = await io.HttpServer.bind(io.InternetAddress.loopbackIPv4, 0);
    } catch (_) {
      await destination.close(force: true);
      rethrow;
    }
    final endpoints = _RedirectEndpoints(origin, destination);
    destination.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      endpoints.destinationRequests.add((
        method: request.method,
        body: jsonDecode(body),
      ));
      request.response
        ..statusCode = 200
        ..headers.contentType = io.ContentType.json
        ..write('{"received":true}');
      await request.response.close();
    });
    origin.listen((request) async {
      endpoints.originRequests++;
      await request.drain<void>();
      request.response
        ..statusCode = status
        ..headers.set(
          io.HttpHeaders.locationHeader,
          'http://127.0.0.1:${destination.port}/destination',
        );
      await request.response.close();
    });
    return endpoints;
  }

  Future<void> close() async {
    await origin.close(force: true);
    await destination.close(force: true);
  }
}
