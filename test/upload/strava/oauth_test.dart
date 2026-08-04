import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:pref/pref.dart';
import 'package:track_my_indoor_exercise/upload/strava/constants.dart';
import 'package:track_my_indoor_exercise/upload/strava/strava.dart';
import 'package:track_my_indoor_exercise/upload/strava/strava_status_code.dart';
import 'package:track_my_indoor_exercise/upload/strava/strava_token.dart';

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

  group('Strava OAuth token refresh', () {
    test('a successful refresh persists the new access/refresh tokens', () async {
      final prefService = Get.find<BasePrefService>();
      await prefService.set<String>(stravaAccessTokenTag, 'old-access-token');
      await prefService.set<String>(stravaRefreshTokenTag, 'old-refresh-token');
      await prefService.set<int>(stravaExpiresAtTag, 100); // Long expired.
      await prefService.set<String>(stravaTokenScopeTag, 'activity:write');

      when(() => mockClient.post(any())).thenAnswer(
        (_) async => http.Response(
          jsonEncode({
            'access_token': 'new-access-token',
            'refresh_token': 'new-refresh-token',
            'expires_at': 9999999999,
            'token_type': 'Bearer',
          }),
          200,
        ),
      );

      final strava = Strava('client-id', 'client-secret');
      final result = await strava.oauth(
        'client-id',
        'activity:write',
        'client-secret',
        'auto',
        client: mockClient,
      );

      expect(result, isTrue);
      expect(prefService.get<String>(stravaAccessTokenTag), 'new-access-token');
      expect(prefService.get<String>(stravaRefreshTokenTag), 'new-refresh-token');
      expect(Get.find<StravaToken>().accessToken, 'new-access-token');

      // The refresh request must follow Strava's documented token contract:
      // https://developers.strava.com/docs/authentication/
      final requestUri = verify(() => mockClient.post(captureAny())).captured.single as Uri;
      expect(requestUri.toString(), startsWith(tokenEndpoint));
      expect(requestUri.queryParameters['grant_type'], 'refresh_token');
      expect(requestUri.queryParameters['refresh_token'], 'old-refresh-token');
      expect(requestUri.queryParameters['client_id'], 'client-id');
      expect(requestUri.queryParameters['client_secret'], 'client-secret');
    });

    test(
      'an expired/invalid refresh token produces a clear failure without corrupting storage',
      () async {
        final prefService = Get.find<BasePrefService>();
        await prefService.set<String>(stravaAccessTokenTag, 'old-access-token');
        await prefService.set<String>(stravaRefreshTokenTag, 'old-refresh-token');
        await prefService.set<int>(stravaExpiresAtTag, 100);
        await prefService.set<String>(stravaTokenScopeTag, 'activity:write');

        when(() => mockClient.post(any())).thenAnswer(
          (_) async => http.Response(
            '{"message":"Bad Request","errors":'
            '[{"resource":"RefreshToken","field":"refresh_token","code":"invalid"}]}',
            400,
          ),
        );

        final strava = Strava('client-id', 'client-secret');
        await strava.oauth(
          'client-id',
          'activity:write',
          'client-secret',
          'auto',
          client: mockClient,
        );

        // A failed refresh must not overwrite the previously stored tokens.
        expect(prefService.get<String>(stravaAccessTokenTag), 'old-access-token');
        expect(prefService.get<String>(stravaRefreshTokenTag), 'old-refresh-token');
      },
    );

    test('an unexpected 200 response body is parsed without throwing', () async {
      final prefService = Get.find<BasePrefService>();
      await prefService.set<String>(stravaAccessTokenTag, 'old-access-token');
      await prefService.set<String>(stravaRefreshTokenTag, 'old-refresh-token');
      await prefService.set<int>(stravaExpiresAtTag, 100);
      await prefService.set<String>(stravaTokenScopeTag, 'activity:write');

      // Strava responds 200 but with a body missing every expected field.
      when(() => mockClient.post(any())).thenAnswer((_) async => http.Response('{}', 200));

      final strava = Strava('client-id', 'client-secret');

      await expectLater(
        strava.oauth('client-id', 'activity:write', 'client-secret', 'auto', client: mockClient),
        completes,
      );

      // Missing fields decode to null, which is then persisted as an empty
      // string rather than crashing the refresh flow.
      expect(prefService.get<String>(stravaAccessTokenTag), '');
    });
  });

  group('Strava deAuthorize', () {
    test('sends a bearer-authorized POST and clears the stored token on success', () async {
      final prefService = Get.find<BasePrefService>();
      await prefService.set<String>(stravaAccessTokenTag, 'active-access-token');
      await prefService.set<String>(stravaRefreshTokenTag, 'active-refresh-token');
      await prefService.set<int>(stravaExpiresAtTag, 9999999999);
      await prefService.set<String>(stravaTokenScopeTag, 'activity:write');

      when(
        () => mockClient.post(any(), headers: any(named: 'headers')),
      ).thenAnswer((_) async => http.Response('{}', 200));

      final strava = Strava('client-id', 'client-secret');
      final fault = await strava.deAuthorize(client: mockClient);

      expect(fault.statusCode, StravaStatusCode.statusOk);

      final captured = verify(
        () => mockClient.post(captureAny(), headers: captureAny(named: 'headers')),
      ).captured;
      expect(captured[0], Uri.parse(deauthorizationEndpoint));
      expect((captured[1] as Map)['Authorization'], 'Bearer active-access-token');
      expect(prefService.get<String>(stravaAccessTokenTag), '');
    });

    test('reports statusDeAuthorizeError when Strava rejects the request', () async {
      final prefService = Get.find<BasePrefService>();
      await prefService.set<String>(stravaAccessTokenTag, 'active-access-token');

      when(
        () => mockClient.post(any(), headers: any(named: 'headers')),
      ).thenAnswer((_) async => http.Response('{"message":"Unauthorized"}', 401));

      final strava = Strava('client-id', 'client-secret');
      final fault = await strava.deAuthorize(client: mockClient);

      expect(fault.statusCode, StravaStatusCode.statusDeAuthorizeError);
    });

    test('skips the network call entirely when there is no stored token', () async {
      final strava = Strava('client-id', 'client-secret');
      final fault = await strava.deAuthorize(client: mockClient);

      expect(fault.statusCode, StravaStatusCode.statusNoAuthenticationYet);
      verifyNever(() => mockClient.post(any(), headers: any(named: 'headers')));
    });
  });
}
