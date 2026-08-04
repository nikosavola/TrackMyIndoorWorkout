import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:track_my_indoor_exercise/export/fit/fit_export.dart';
import 'package:track_my_indoor_exercise/secret.dart';
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

  group('Suunto uploadActivity', () {
    test('constructs the documented init/blob/status requests and processes success', () async {
      Get.put<SuuntoToken>(SuuntoToken(accessToken: 'active-access-token'), permanent: true);

      const blobUrl = 'https://blob.suunto.com/container/upload-123';
      when(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => http.Response('{"id":"upload-123","url":"$blobUrl"}', 200));
      when(
        () => mockClient.put(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => http.Response('', 201));
      when(() => mockClient.get(any(), headers: any(named: 'headers'))).thenAnswer(
        (_) async =>
            http.Response('{"webUrl":"https://sports-tracker.com/workout/upload-123"}', 200),
      );

      final activity = buildTestActivity();
      final exporter = FitExport();
      final fileContent = [10, 20, 30, 40];

      final suunto = Suunto('client-id', 'client-secret', 'subscription-key');
      final statusCode = await suunto.uploadActivity(
        activity,
        fileContent,
        exporter,
        client: mockClient,
      );

      expect(statusCode, 200);

      // Init POST must follow Suunto's documented upload contract:
      // https://apizone.suunto.com/how-to-workout-upload
      final initCall = verify(
        () => mockClient.post(
          captureAny(),
          headers: captureAny(named: 'headers'),
          body: captureAny(named: 'body'),
        ),
      ).captured;
      expect(initCall[0], Uri.parse(uploadsEndpoint));
      final initHeaders = initCall[1] as Map<String, String>;
      expect(initHeaders['Authorization'], 'Bearer active-access-token');
      // The upload mixin authorizes with the compiled-in subscription key
      // (from secret.dart), not the instance's constructor argument.
      expect(initHeaders['Ocp-Apim-Subscription-Key'], suuntoSubscriptionPrimaryKey);
      expect(initHeaders['Content-Type'], 'application/json');

      final putCall = verify(
        () => mockClient.put(
          captureAny(),
          headers: captureAny(named: 'headers'),
          body: captureAny(named: 'body'),
        ),
      ).captured;
      expect(putCall[0], Uri.parse(blobUrl));
      final putHeaders = putCall[1] as Map<String, String>;
      expect(putHeaders['x-ms-blob-type'], 'BlockBlob');
      expect(putCall[2], fileContent);

      final getCall = verify(
        () => mockClient.get(captureAny(), headers: captureAny(named: 'headers')),
      ).captured;
      expect(getCall[0], Uri.parse('$uploadsEndpoint/upload-123'));

      expect(activity.suuntoUploadIdentifier, 'upload-123');
      expect(activity.suuntoWorkoutUrl, 'https://sports-tracker.com/workout/upload-123');
      expect(activity.suuntoUploaded, isTrue);
    });

    test('returns 0 without making a network call when no token exists', () async {
      final activity = buildTestActivity();
      final exporter = FitExport();

      final statusCode = await Suunto(
        'client-id',
        'client-secret',
        'subscription-key',
      ).uploadActivity(activity, [1, 2, 3], exporter, client: mockClient);

      expect(statusCode, 0);
      verifyNever(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      );
    });

    test('surfaces a non-2xx init response without attempting the blob upload', () async {
      Get.put<SuuntoToken>(SuuntoToken(accessToken: 'active-access-token'), permanent: true);

      when(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => http.Response('{"message":"Bad Request"}', 400));

      final activity = buildTestActivity();
      final exporter = FitExport();
      final statusCode = await Suunto(
        'client-id',
        'client-secret',
        'subscription-key',
      ).uploadActivity(activity, [1, 2, 3], exporter, client: mockClient);

      expect(statusCode, 400);
      verifyNever(
        () => mockClient.put(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      );
    });

    test(
      'an unexpected 200 init response (missing the blob url) is handled without throwing',
      () async {
        Get.put<SuuntoToken>(SuuntoToken(accessToken: 'active-access-token'), permanent: true);

        when(
          () => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer((_) async => http.Response('{"id":"upload-123"}', 200));

        final activity = buildTestActivity();
        final exporter = FitExport();

        final statusCode = await Suunto(
          'client-id',
          'client-secret',
          'subscription-key',
        ).uploadActivity(activity, [1, 2, 3], exporter, client: mockClient);

        expect(statusCode, 0);
        verifyNever(
          () => mockClient.put(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        );
      },
    );
  });
}
