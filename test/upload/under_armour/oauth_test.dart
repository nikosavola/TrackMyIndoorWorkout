import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:pref/pref.dart';
import 'package:track_my_indoor_exercise/upload/under_armour/constants.dart';
import 'package:track_my_indoor_exercise/upload/under_armour/under_armour.dart';
import 'package:track_my_indoor_exercise/upload/under_armour/under_armour_token.dart';

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

  group('Under Armour OAuth token refresh', () {
    test('a successful refresh persists the new access/refresh tokens', () async {
      final prefService = Get.find<BasePrefService>();
      await prefService.set<String>(underArmourAccessTokenTag, 'old-access-token');
      await prefService.set<String>(underArmourRefreshTokenTag, 'old-refresh-token');
      await prefService.set<int>(underArmourExpiresAtTag, 100); // Long expired.

      when(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
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

      final underArmour = UnderArmour('client-id', 'client-secret');
      final result = await underArmour.oauth('client-id', 'client-secret', client: mockClient);

      expect(result, isTrue);
      expect(prefService.get<String>(underArmourAccessTokenTag), 'new-access-token');
      expect(prefService.get<String>(underArmourRefreshTokenTag), 'new-refresh-token');
      expect(Get.find<UnderArmourToken>().accessToken, 'new-access-token');

      // The refresh request must follow Under Armour's documented token
      // contract: https://developer.underarmour.com/docs/OAuth2
      final captured = verify(
        () => mockClient.post(
          captureAny(),
          headers: captureAny(named: 'headers'),
          body: captureAny(named: 'body'),
        ),
      ).captured;
      expect(captured[0], Uri.parse(tokenEndpoint));
      final headers = captured[1] as Map<String, String>;
      expect(headers['Api-Key'], 'client-id');
      final body = captured[2] as Map<String, String>;
      expect(body['grant_type'], 'refresh_token');
      expect(body['client_id'], 'client-id');
      expect(body['client_secret'], 'client-secret');
      expect(body['refresh_token'], 'old-refresh-token');
    });

    test(
      'an expired/invalid refresh token produces a clear failure without corrupting storage',
      () async {
        final prefService = Get.find<BasePrefService>();
        await prefService.set<String>(underArmourAccessTokenTag, 'old-access-token');
        await prefService.set<String>(underArmourRefreshTokenTag, 'old-refresh-token');
        await prefService.set<int>(underArmourExpiresAtTag, 100);

        when(
          () => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer((_) async => http.Response('invalid_grant', 400));

        final underArmour = UnderArmour('client-id', 'client-secret');
        await underArmour.oauth('client-id', 'client-secret', client: mockClient);

        // A failed refresh must not overwrite the previously stored tokens.
        expect(prefService.get<String>(underArmourAccessTokenTag), 'old-access-token');
        expect(prefService.get<String>(underArmourRefreshTokenTag), 'old-refresh-token');
      },
    );

    test(
      'an unexpected 200 response body (missing access/refresh tokens) is handled without throwing',
      () async {
        final prefService = Get.find<BasePrefService>();
        await prefService.set<String>(underArmourAccessTokenTag, 'old-access-token');
        await prefService.set<String>(underArmourRefreshTokenTag, 'old-refresh-token');
        await prefService.set<int>(underArmourExpiresAtTag, 100);

        when(
          () => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer((_) async => http.Response(jsonEncode({'expires_in': 3600}), 200));

        final underArmour = UnderArmour('client-id', 'client-secret');

        await expectLater(
          underArmour.oauth('client-id', 'client-secret', client: mockClient),
          completes,
        );

        expect(prefService.get<String>(underArmourAccessTokenTag), '');
      },
    );
  });

  group('Under Armour deAuthorize', () {
    test('clears the stored token and never touches the network', () async {
      final prefService = Get.find<BasePrefService>();
      await prefService.set<String>(underArmourAccessTokenTag, 'active-access-token');
      await prefService.set<String>(underArmourRefreshTokenTag, 'active-refresh-token');

      final underArmour = UnderArmour('client-id', 'client-secret');
      final statusCode = await underArmour.deAuthorize('client-id');

      expect(statusCode, 200);
      expect(prefService.get<String>(underArmourAccessTokenTag), '');
      verifyNever(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      );
    });
  });
}
