import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:pref/pref.dart';
import 'package:track_my_indoor_exercise/upload/suunto/constants.dart';
import 'package:track_my_indoor_exercise/upload/suunto/suunto.dart';
import 'package:track_my_indoor_exercise/upload/suunto/suunto_token.dart';

import '../upload_test_helpers.dart';

class MockHttpClient extends Mock implements http.Client {}

void main() {
  late MockHttpClient mockClient;

  setUpAll(() {
    registerFallbackValue(Uri.parse('https://example.com'));
  });

  setUp(() async {
    mockClient = MockHttpClient();
    await setUpUploadTestEnvironment();
  });

  tearDown(() {
    Get.reset();
  });

  group('Suunto OAuth token refresh', () {
    test('a successful refresh persists the new access/refresh tokens', () async {
      final prefService = Get.find<BasePrefService>();
      await prefService.set<String>(suuntoAccessTokenTag, 'old-access-token');
      await prefService.set<String>(suuntoRefreshTokenTag, 'old-refresh-token');
      await prefService.set<int>(suuntoExpiresAtTag, 100); // Long expired.

      when(() => mockClient.post(any(), headers: any(named: 'headers'))).thenAnswer(
        (_) async => http.Response(
          jsonEncode({
            'access_token': 'new-access-token',
            'refresh_token': 'new-refresh-token',
            'expires_in': 3600,
            'token_type': 'Bearer',
          }),
          200,
        ),
      );

      final suunto = Suunto('client-id', 'client-secret', 'subscription-key');
      final result = await suunto.oauth(
        'client-id',
        'client-secret',
        'subscription-key',
        client: mockClient,
      );

      expect(result, isTrue);
      expect(prefService.get<String>(suuntoAccessTokenTag), 'new-access-token');
      expect(prefService.get<String>(suuntoRefreshTokenTag), 'new-refresh-token');
      expect(Get.find<SuuntoToken>().accessToken, 'new-access-token');

      // The refresh request must follow Suunto's documented token contract:
      // https://apizone.suunto.com/how-to-authentication
      final captured = verify(
        () => mockClient.post(captureAny(), headers: captureAny(named: 'headers')),
      ).captured;
      final requestUri = captured[0] as Uri;
      final headers = captured[1] as Map<String, String>;
      expect(requestUri.toString(), startsWith(tokenEndpoint));
      expect(requestUri.queryParameters['grant_type'], 'refresh_token');
      expect(requestUri.queryParameters['refresh_token'], 'old-refresh-token');
      final expectedBasicAuth = 'Basic ${base64Encode(utf8.encode('client-id:client-secret'))}';
      expect(headers['Authorization'], expectedBasicAuth);
    });

    test(
      'an expired/invalid refresh token produces a clear failure without corrupting storage',
      () async {
        final prefService = Get.find<BasePrefService>();
        await prefService.set<String>(suuntoAccessTokenTag, 'old-access-token');
        await prefService.set<String>(suuntoRefreshTokenTag, 'old-refresh-token');
        await prefService.set<int>(suuntoExpiresAtTag, 100);

        when(
          () => mockClient.post(any(), headers: any(named: 'headers')),
        ).thenAnswer((_) async => http.Response('invalid_grant: refresh token expired', 401));

        final suunto = Suunto('client-id', 'client-secret', 'subscription-key');
        await suunto.oauth('client-id', 'client-secret', 'subscription-key', client: mockClient);

        // A failed refresh must not overwrite the previously stored tokens.
        expect(prefService.get<String>(suuntoAccessTokenTag), 'old-access-token');
        expect(prefService.get<String>(suuntoRefreshTokenTag), 'old-refresh-token');
      },
    );

    test(
      'an unexpected 200 response body (missing access/refresh tokens) is handled without throwing',
      () async {
        final prefService = Get.find<BasePrefService>();
        await prefService.set<String>(suuntoAccessTokenTag, 'old-access-token');
        await prefService.set<String>(suuntoRefreshTokenTag, 'old-refresh-token');
        await prefService.set<int>(suuntoExpiresAtTag, 100);

        // Suunto responds 200 but the body only carries `expires_in`.
        when(
          () => mockClient.post(any(), headers: any(named: 'headers')),
        ).thenAnswer((_) async => http.Response(jsonEncode({'expires_in': 3600}), 200));

        final suunto = Suunto('client-id', 'client-secret', 'subscription-key');

        await expectLater(
          suunto.oauth('client-id', 'client-secret', 'subscription-key', client: mockClient),
          completes,
        );

        // Missing tokens decode to null, which is then persisted as an empty
        // string rather than crashing the refresh flow.
        expect(prefService.get<String>(suuntoAccessTokenTag), '');
      },
    );
  });

  group('Suunto deAuthorize', () {
    test('sends a bearer-authorized POST and clears the stored token on success', () async {
      final prefService = Get.find<BasePrefService>();
      await prefService.set<String>(suuntoAccessTokenTag, 'active-access-token');
      await prefService.set<String>(suuntoRefreshTokenTag, 'active-refresh-token');
      await prefService.set<int>(suuntoExpiresAtTag, 9999999999);

      when(
        () => mockClient.post(any(), headers: any(named: 'headers')),
      ).thenAnswer((_) async => http.Response('{}', 200));

      final suunto = Suunto('client-id', 'client-secret', 'subscription-key');
      final success = await suunto.deAuthorize('client-id', 'subscription-key', client: mockClient);

      expect(success, isTrue);

      final captured = verify(
        () => mockClient.post(captureAny(), headers: captureAny(named: 'headers')),
      ).captured;
      expect((captured[0] as Uri).toString(), '$deauthorizationEndpoint?client_id=client-id');
      final headers = captured[1] as Map<String, String>;
      expect(headers['Authorization'], 'Bearer active-access-token');
      expect(headers['Ocp-Apim-Subscription-Key'], 'subscription-key');
      expect(prefService.get<String>(suuntoAccessTokenTag), '');
    });

    test('reports failure when Suunto rejects the deauthorize request', () async {
      final prefService = Get.find<BasePrefService>();
      await prefService.set<String>(suuntoAccessTokenTag, 'active-access-token');

      when(
        () => mockClient.post(any(), headers: any(named: 'headers')),
      ).thenAnswer((_) async => http.Response('{"message":"Unauthorized"}', 401));

      final suunto = Suunto('client-id', 'client-secret', 'subscription-key');
      final success = await suunto.deAuthorize('client-id', 'subscription-key', client: mockClient);

      expect(success, isFalse);
    });

    test('skips the network call entirely when there is no stored token', () async {
      final suunto = Suunto('client-id', 'client-secret', 'subscription-key');
      final success = await suunto.deAuthorize('client-id', 'subscription-key', client: mockClient);

      expect(success, isTrue);
      verifyNever(() => mockClient.post(any(), headers: any(named: 'headers')));
    });
  });
}
