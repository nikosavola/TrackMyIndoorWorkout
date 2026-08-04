import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:pref/pref.dart';
import 'package:track_my_indoor_exercise/upload/training_peaks/constants.dart';
import 'package:track_my_indoor_exercise/upload/training_peaks/training_peaks.dart';
import 'package:track_my_indoor_exercise/upload/training_peaks/training_peaks_token.dart';

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

  group('TrainingPeaks OAuth token refresh', () {
    test('a successful refresh persists the new access/refresh tokens', () async {
      final prefService = Get.find<BasePrefService>();
      await prefService.set<String>(trainingPeaksAccessTokenTag, 'old-access-token');
      await prefService.set<String>(trainingPeaksRefreshTokenTag, 'old-refresh-token');
      await prefService.set<int>(trainingPeaksExpiresAtTag, 100); // Long expired.
      await prefService.set<String>(trainingPeaksTokenScopeTag, 'file:write');

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

      final trainingPeaks = TrainingPeaks('client-id', 'client-secret');
      final result = await trainingPeaks.oauth(
        'client-id',
        'client-secret',
        'file:write',
        client: mockClient,
      );

      expect(result, isTrue);
      expect(prefService.get<String>(trainingPeaksAccessTokenTag), 'new-access-token');
      expect(prefService.get<String>(trainingPeaksRefreshTokenTag), 'new-refresh-token');
      expect(Get.find<TrainingPeaksToken>().accessToken, 'new-access-token');

      // The refresh request must follow TrainingPeaks' documented token
      // contract: https://github.com/TrainingPeaks/PartnersAPI/wiki/OAuth2
      final captured = verify(
        () => mockClient.post(
          captureAny(),
          headers: captureAny(named: 'headers'),
          body: captureAny(named: 'body'),
        ),
      ).captured;
      expect(captured[0], Uri.parse('${getUrlBaseForTest()}$tokenPath'));
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
        await prefService.set<String>(trainingPeaksAccessTokenTag, 'old-access-token');
        await prefService.set<String>(trainingPeaksRefreshTokenTag, 'old-refresh-token');
        await prefService.set<int>(trainingPeaksExpiresAtTag, 100);
        await prefService.set<String>(trainingPeaksTokenScopeTag, 'file:write');

        when(
          () => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer((_) async => http.Response('invalid_grant', 400));

        final trainingPeaks = TrainingPeaks('client-id', 'client-secret');
        await trainingPeaks.oauth('client-id', 'client-secret', 'file:write', client: mockClient);

        // A failed refresh must not overwrite the previously stored tokens.
        expect(prefService.get<String>(trainingPeaksAccessTokenTag), 'old-access-token');
        expect(prefService.get<String>(trainingPeaksRefreshTokenTag), 'old-refresh-token');
      },
    );

    test(
      'an unexpected 200 response body (missing access/refresh tokens) is handled without throwing',
      () async {
        final prefService = Get.find<BasePrefService>();
        await prefService.set<String>(trainingPeaksAccessTokenTag, 'old-access-token');
        await prefService.set<String>(trainingPeaksRefreshTokenTag, 'old-refresh-token');
        await prefService.set<int>(trainingPeaksExpiresAtTag, 100);
        await prefService.set<String>(trainingPeaksTokenScopeTag, 'file:write');

        when(
          () => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer((_) async => http.Response(jsonEncode({'expires_in': 3600}), 200));

        final trainingPeaks = TrainingPeaks('client-id', 'client-secret');

        await expectLater(
          trainingPeaks.oauth('client-id', 'client-secret', 'file:write', client: mockClient),
          completes,
        );

        expect(prefService.get<String>(trainingPeaksAccessTokenTag), '');
      },
    );
  });

  group('TrainingPeaks deAuthorize', () {
    test('sends a bearer-authorized POST and clears the stored token on success', () async {
      final prefService = Get.find<BasePrefService>();
      await prefService.set<String>(trainingPeaksAccessTokenTag, 'active-access-token');
      await prefService.set<String>(trainingPeaksRefreshTokenTag, 'active-refresh-token');
      await prefService.set<int>(trainingPeaksExpiresAtTag, 9999999999);

      when(
        () => mockClient.post(any(), headers: any(named: 'headers')),
      ).thenAnswer((_) async => http.Response('{}', 200));

      final trainingPeaks = TrainingPeaks('client-id', 'client-secret');
      final success = await trainingPeaks.deAuthorize(client: mockClient);

      expect(success, isTrue);

      final captured = verify(
        () => mockClient.post(captureAny(), headers: captureAny(named: 'headers')),
      ).captured;
      expect((captured[0] as Uri).toString(), '${getUrlBaseForTest()}$deauthorizationPath');
      final headers = captured[1] as Map<String, String>;
      expect(headers['Authorization'], 'Bearer active-access-token');
      expect(prefService.get<String>(trainingPeaksAccessTokenTag), '');
    });

    test('reports failure when TrainingPeaks rejects the deauthorize request', () async {
      final prefService = Get.find<BasePrefService>();
      await prefService.set<String>(trainingPeaksAccessTokenTag, 'active-access-token');

      when(
        () => mockClient.post(any(), headers: any(named: 'headers')),
      ).thenAnswer((_) async => http.Response('{"message":"Unauthorized"}', 401));

      final trainingPeaks = TrainingPeaks('client-id', 'client-secret');
      final success = await trainingPeaks.deAuthorize(client: mockClient);

      expect(success, isFalse);
    });

    test('skips the network call entirely when there is no stored token', () async {
      final trainingPeaks = TrainingPeaks('client-id', 'client-secret');
      final success = await trainingPeaks.deAuthorize(client: mockClient);

      expect(success, isTrue);
      verifyNever(() => mockClient.post(any(), headers: any(named: 'headers')));
    });
  });
}

/// TrainingPeaks always resolves to the production OAuth base regardless of
/// the (dead) sandbox constants, see lib/upload/training_peaks/oauth.dart.
String getUrlBaseForTest() => tpProductionOAuthUrlBase;
