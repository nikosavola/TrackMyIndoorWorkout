// Verifies the OAuth "state" parameter validation added to every provider's
// redirect handler: a redirect whose `state` matches the value generated for
// the in-flight request is allowed to proceed to the token exchange, while a
// missing/mismatched `state` is rejected *before* any token-exchange HTTP
// call is made.
//
// The providers share near-identical `Auth` mixin implementations (see
// lib/upload/oauth_state.dart for the shared state-generation/validation
// helper), so this single file exercises all four with the same shape of
// test rather than duplicating four near-identical files.
//
// Note: `onCodeReceived` is a broadcast StreamController, so
// `completeAuthorization()` (which does `await onCodeReceived.stream.first`)
// must be started *before* `handleRedirectUri()` emits onto it - a broadcast
// stream does not replay events to a listener that subscribes afterwards.
// That is also the real ordering in production: `_getXCode()` sets up its
// AppLinks subscription before `completeAuthorization()` starts waiting.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:pref/pref.dart';
import 'package:track_my_indoor_exercise/upload/strava/strava.dart';
import 'package:track_my_indoor_exercise/upload/suunto/suunto.dart';
import 'package:track_my_indoor_exercise/upload/training_peaks/training_peaks.dart';
import 'package:track_my_indoor_exercise/upload/under_armour/under_armour.dart';

class MockHttpClient extends Mock implements http.Client {}

class MockBasePrefService extends Mock implements BasePrefService {
  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) => super.toString();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The redirect handler under test calls closeInAppWebView() (url_launcher)
  // on a valid redirect; stub its method channel so that call resolves
  // instead of throwing in the test environment.
  const urlLauncherChannel = MethodChannel('plugins.flutter.io/url_launcher');

  setUpAll(() {
    registerFallbackValue(Uri.parse('https://example.com'));
  });

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      urlLauncherChannel,
      (MethodCall methodCall) async => null,
    );

    final mockPrefService = MockBasePrefService();
    when(() => mockPrefService.set<String>(any(), any())).thenAnswer((_) async => true);
    when(() => mockPrefService.set<int>(any(), any())).thenAnswer((_) async => true);
    when(() => mockPrefService.get<String>(any())).thenReturn(null);
    when(() => mockPrefService.get<int>(any())).thenReturn(null);
    Get.put<BasePrefService>(mockPrefService);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      urlLauncherChannel,
      null,
    );
    Get.reset();
  });

  group('Strava OAuth redirect state validation', () {
    test('valid state proceeds to token exchange', () async {
      final strava = Strava('client-id', 'secret');
      final mockClient = MockHttpClient();
      strava.httpClient = mockClient;
      when(() => mockClient.post(any())).thenAnswer(
        (_) async => http.Response(
          '{"access_token":"tok","refresh_token":"ref","expires_at":9999999999}',
          200,
        ),
      );
      strava.oauthState = 'expected-state';

      final resultFuture = strava.completeAuthorization('client-id', 'secret', 'scope');
      strava.handleRedirectUri(
        Uri.parse('stravaflutter://redirect?code=abc123&state=expected-state'),
        'client-id',
      );
      final result = await resultFuture;

      expect(result, true);
      verify(() => mockClient.post(any())).called(1);
    });

    test('mismatched state rejects without a token exchange call', () async {
      final strava = Strava('client-id', 'secret');
      final mockClient = MockHttpClient();
      strava.httpClient = mockClient;
      strava.oauthState = 'expected-state';

      final resultFuture = strava.completeAuthorization('client-id', 'secret', 'scope');
      strava.handleRedirectUri(
        Uri.parse('stravaflutter://redirect?code=abc123&state=WRONG-STATE'),
        'client-id',
      );
      final result = await resultFuture;

      expect(result, false);
      verifyNever(() => mockClient.post(any()));
    });

    test('missing state rejects without a token exchange call', () async {
      final strava = Strava('client-id', 'secret');
      final mockClient = MockHttpClient();
      strava.httpClient = mockClient;
      strava.oauthState = 'expected-state';

      final resultFuture = strava.completeAuthorization('client-id', 'secret', 'scope');
      strava.handleRedirectUri(Uri.parse('stravaflutter://redirect?code=abc123'), 'client-id');
      final result = await resultFuture;

      expect(result, false);
      verifyNever(() => mockClient.post(any()));
    });
  });

  group('Suunto OAuth redirect state validation', () {
    test('valid state proceeds to token exchange', () async {
      final suunto = Suunto('client-id', 'secret', 'subscription-key');
      final mockClient = MockHttpClient();
      suunto.httpClient = mockClient;
      when(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async =>
            http.Response('{"access_token":"tok","refresh_token":"ref","expires_in":3600}', 200),
      );
      suunto.oauthState = 'expected-state';

      final resultFuture = suunto.completeAuthorization('client-id', 'secret');
      suunto.handleRedirectUri(
        Uri.parse('suuntoflutter://redirect?code=abc123&state=expected-state'),
        'client-id',
      );
      final result = await resultFuture;

      expect(result, true);
      verify(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).called(1);
    });

    test('mismatched state rejects without a token exchange call', () async {
      final suunto = Suunto('client-id', 'secret', 'subscription-key');
      final mockClient = MockHttpClient();
      suunto.httpClient = mockClient;
      suunto.oauthState = 'expected-state';

      final resultFuture = suunto.completeAuthorization('client-id', 'secret');
      suunto.handleRedirectUri(
        Uri.parse('suuntoflutter://redirect?code=abc123&state=WRONG-STATE'),
        'client-id',
      );
      final result = await resultFuture;

      expect(result, false);
      verifyNever(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      );
    });
  });

  group('Training Peaks OAuth redirect state validation', () {
    test('valid state proceeds to token exchange', () async {
      final trainingPeaks = TrainingPeaks('client-id', 'secret');
      final mockClient = MockHttpClient();
      trainingPeaks.httpClient = mockClient;
      when(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async =>
            http.Response('{"access_token":"tok","refresh_token":"ref","expires_in":3600}', 200),
      );
      trainingPeaks.oauthState = 'expected-state';

      final resultFuture = trainingPeaks.completeAuthorization(
        'client-id',
        'secret',
        'workout:read',
      );
      trainingPeaks.handleRedirectUri(
        Uri.parse('trainingpeaksflutter://redirect?code=abc123&state=expected-state'),
        'client-id',
      );
      final result = await resultFuture;

      expect(result, true);
      verify(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).called(1);
    });

    test('mismatched state rejects without a token exchange call', () async {
      final trainingPeaks = TrainingPeaks('client-id', 'secret');
      final mockClient = MockHttpClient();
      trainingPeaks.httpClient = mockClient;
      trainingPeaks.oauthState = 'expected-state';

      final resultFuture = trainingPeaks.completeAuthorization(
        'client-id',
        'secret',
        'workout:read',
      );
      trainingPeaks.handleRedirectUri(
        Uri.parse('trainingpeaksflutter://redirect?code=abc123&state=WRONG-STATE'),
        'client-id',
      );
      final result = await resultFuture;

      expect(result, false);
      verifyNever(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      );
    });
  });

  group('Under Armour OAuth redirect state validation', () {
    test('valid state proceeds to token exchange', () async {
      final underArmour = UnderArmour('client-id', 'secret');
      final mockClient = MockHttpClient();
      underArmour.httpClient = mockClient;
      when(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async =>
            http.Response('{"access_token":"tok","refresh_token":"ref","expires_in":3600}', 200),
      );
      underArmour.oauthState = 'expected-state';

      final resultFuture = underArmour.completeAuthorization('client-id', 'secret');
      underArmour.handleRedirectUri(
        Uri.parse('mapmyfitnessflutter://redirect?code=abc123&state=expected-state'),
        'client-id',
      );
      final result = await resultFuture;

      expect(result, true);
      verify(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).called(1);
    });

    test('mismatched state rejects without a token exchange call', () async {
      final underArmour = UnderArmour('client-id', 'secret');
      final mockClient = MockHttpClient();
      underArmour.httpClient = mockClient;
      underArmour.oauthState = 'expected-state';

      final resultFuture = underArmour.completeAuthorization('client-id', 'secret');
      underArmour.handleRedirectUri(
        Uri.parse('mapmyfitnessflutter://redirect?code=abc123&state=WRONG-STATE'),
        'client-id',
      );
      final result = await resultFuture;

      expect(result, false);
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
