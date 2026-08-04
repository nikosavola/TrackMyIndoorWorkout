import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:track_my_indoor_exercise/export/fit/fit_export.dart';
import 'package:track_my_indoor_exercise/upload/strava/constants.dart';
import 'package:track_my_indoor_exercise/upload/strava/strava.dart';
import 'package:track_my_indoor_exercise/upload/strava/strava_status_code.dart';
import 'package:track_my_indoor_exercise/upload/strava/strava_token.dart';

import '../upload_test_helpers.dart';

class MockHttpClient extends Mock implements http.Client {}

void main() {
  late MockHttpClient mockClient;

  setUpAll(() {
    registerFallbackValue(http.Request('GET', Uri.parse('https://example.com')));
    registerFallbackValue(Uri.parse('https://example.com'));
  });

  setUp(() async {
    mockClient = MockHttpClient();
    await setUpUploadTestEnvironment();
  });

  tearDown(() {
    Get.reset();
  });

  group('Strava uploadActivity', () {
    test(
      'constructs the documented multipart upload request and processes a successful response',
      () async {
        Get.put<StravaToken>(StravaToken(accessToken: 'active-access-token'), permanent: true);

        final activity = buildTestActivity();
        final exporter = FitExport();
        final fileContent = [1, 2, 3, 4, 5];

        when(() => mockClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            Stream.value(
              utf8.encode(
                jsonEncode({
                  'id': 987654321,
                  'external_id': 'strava_flutter',
                  'error': '',
                  'status': 'Your activity is uploaded.',
                }),
              ),
            ),
            201,
            reasonPhrase: 'Created',
          ),
        );
        when(() => mockClient.get(any(), headers: any(named: 'headers'))).thenAnswer(
          (_) async => http.Response(
            jsonEncode({
              'id': 987654321,
              'external_id': 'strava_flutter',
              'error': '',
              'status': 'Your activity is ready.',
              'activity_id': 555,
            }),
            200,
            reasonPhrase: 'Your activity is ready.',
          ),
        );

        final strava = Strava('client-id', 'client-secret');
        final fault = await strava.uploadActivity(
          activity,
          fileContent,
          exporter,
          client: mockClient,
        );

        expect(fault.statusCode, 201);

        // Verify the multipart request matches Strava's documented upload
        // contract: https://developers.strava.com/docs/uploads/
        final sentRequest =
            verify(() => mockClient.send(captureAny())).captured.single as http.MultipartRequest;
        expect(sentRequest.method, 'POST');
        expect(sentRequest.url, Uri.parse(uploadsEndpoint));
        expect(sentRequest.headers['Authorization'], 'Bearer active-access-token');
        expect(sentRequest.fields['data_type'], 'fit.gz');
        expect(sentRequest.fields['trainer'], 'false');
        expect(sentRequest.fields['commute'], 'false');
        expect(sentRequest.fields['external_id'], 'strava_flutter');
        expect(sentRequest.files, hasLength(1));
        expect(sentRequest.files.single.field, 'file');
        expect(sentRequest.files.single.contentType.mimeType, 'application/x-gzip');

        // The activity is marked as uploaded/initiated once Strava accepts it.
        expect(activity.uploaded, isTrue);
        expect(activity.stravaId, 987654321);
      },
    );

    test(
      'returns statusTokenNotKnownYet without making a network call when no token exists',
      () async {
        final activity = buildTestActivity();
        final exporter = FitExport();

        final fault = await Strava(
          'client-id',
          'client-secret',
        ).uploadActivity(activity, [1, 2, 3], exporter, client: mockClient);

        expect(fault.statusCode, StravaStatusCode.statusTokenNotKnownYet);
        verifyNever(() => mockClient.send(any()));
      },
    );

    test('surfaces a non-2xx initial response as a Fault without polling for status', () async {
      Get.put<StravaToken>(StravaToken(accessToken: 'active-access-token'), permanent: true);

      when(() => mockClient.send(any())).thenAnswer(
        (_) async => http.StreamedResponse(
          Stream.value(utf8.encode('{"message":"Activity already exists"}')),
          400,
          reasonPhrase: 'Bad Request',
        ),
      );

      final activity = buildTestActivity();
      final exporter = FitExport();
      final fault = await Strava(
        'client-id',
        'client-secret',
      ).uploadActivity(activity, [1, 2, 3], exporter, client: mockClient);

      expect(fault.statusCode, 400);
      verifyNever(() => mockClient.get(any(), headers: any(named: 'headers')));
    });

    test('an unexpected 201 response body (missing fields) is handled without throwing', () async {
      Get.put<StravaToken>(StravaToken(accessToken: 'active-access-token'), permanent: true);

      when(() => mockClient.send(any())).thenAnswer(
        (_) async =>
            http.StreamedResponse(Stream.value(utf8.encode('{}')), 201, reasonPhrase: 'Created'),
      );

      final activity = buildTestActivity();
      final exporter = FitExport();

      await expectLater(
        Strava(
          'client-id',
          'client-secret',
        ).uploadActivity(activity, [1, 2, 3], exporter, client: mockClient),
        completes,
      );

      // decodedResponse.id defaults to 0, so the activity is never marked as
      // initiated/uploaded, but no exception propagates.
      expect(activity.uploaded, isFalse);
      verifyNever(() => mockClient.get(any(), headers: any(named: 'headers')));
    });
  });
}
