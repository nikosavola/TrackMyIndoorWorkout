import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:track_my_indoor_exercise/export/fit/fit_export.dart';
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

  group('TrainingPeaks uploadActivity', () {
    test('constructs the documented upload/status requests and processes success', () async {
      Get.put<TrainingPeaksToken>(
        TrainingPeaksToken(accessToken: 'active-access-token'),
        permanent: true,
      );

      when(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          '',
          202,
          headers: {'location': '$tpProductionApiUrlBase${uploadStatusPath}abc-123'},
        ),
      );
      when(() => mockClient.get(any(), headers: any(named: 'headers'))).thenAnswer(
        (_) async => http.Response('{"Completed":true,"Status":"Uploaded","WorkoutIds":[42]}', 200),
      );

      final activity = buildTestActivity();
      final exporter = FitExport();
      final fileContent = [1, 2, 3, 4];

      final trainingPeaks = TrainingPeaks('client-id', 'client-secret');
      final statusCode = await trainingPeaks.uploadActivity(
        activity,
        fileContent,
        exporter,
        'client-id',
        client: mockClient,
      );

      expect(statusCode, 202);

      // The upload POST must follow TrainingPeaks' documented file-upload
      // contract: https://github.com/TrainingPeaks/PartnersAPI/wiki/Upload-a-File
      final postCall = verify(
        () => mockClient.post(
          captureAny(),
          headers: captureAny(named: 'headers'),
          body: captureAny(named: 'body'),
        ),
      ).captured;
      expect(postCall[0], Uri.parse('$tpProductionApiUrlBase$uploadPath'));
      final postHeaders = postCall[1] as Map<String, String>;
      expect(postHeaders['Authorization'], 'Bearer active-access-token');
      expect(postHeaders['Content-Type'], 'application/json');
      expect(postHeaders['User-Agent'], 'client-id/1.0');
      final bodyMap = jsonDecode(postCall[2] as String) as Map<String, dynamic>;
      expect(bodyMap['UploadClient'], isNotEmpty);
      expect(bodyMap['Filename'], isNotEmpty);
      expect(bodyMap['Data'], base64Encode(fileContent));
      expect(bodyMap['Type'], 'Bike');

      final getCall = verify(
        () => mockClient.get(captureAny(), headers: captureAny(named: 'headers')),
      ).captured;
      expect((getCall[0] as Uri).toString(), '$tpProductionApiUrlBase${uploadStatusPath}abc-123');

      expect(activity.trainingPeaksFileTrackingUuid, 'abc-123');
      expect(activity.trainingPeaksUploaded, isTrue);
      expect(activity.trainingPeaksWorkoutId, 42);
    });

    test('returns 401 without making a network call when no token exists', () async {
      final activity = buildTestActivity();
      final exporter = FitExport();

      final statusCode = await TrainingPeaks(
        'client-id',
        'client-secret',
      ).uploadActivity(activity, [1, 2, 3], exporter, 'client-id', client: mockClient);

      expect(statusCode, 401);
      verifyNever(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      );
    });

    test('surfaces a non-2xx initial response without polling for status', () async {
      Get.put<TrainingPeaksToken>(
        TrainingPeaksToken(accessToken: 'active-access-token'),
        permanent: true,
      );

      when(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => http.Response('{"message":"Bad Request"}', 400));

      final activity = buildTestActivity();
      final exporter = FitExport();
      final statusCode = await TrainingPeaks(
        'client-id',
        'client-secret',
      ).uploadActivity(activity, [1, 2, 3], exporter, 'client-id', client: mockClient);

      expect(statusCode, 400);
      verifyNever(() => mockClient.get(any(), headers: any(named: 'headers')));
    });

    test('a success response missing the location header returns without polling', () async {
      Get.put<TrainingPeaksToken>(
        TrainingPeaksToken(accessToken: 'active-access-token'),
        permanent: true,
      );

      when(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => http.Response('', 202));

      final activity = buildTestActivity();
      final exporter = FitExport();

      final statusCode = await TrainingPeaks(
        'client-id',
        'client-secret',
      ).uploadActivity(activity, [1, 2, 3], exporter, 'client-id', client: mockClient);

      expect(statusCode, 202);
      verifyNever(() => mockClient.get(any(), headers: any(named: 'headers')));
    });

    test('a 404 on the first status poll ends the loop without throwing', () async {
      Get.put<TrainingPeaksToken>(
        TrainingPeaksToken(accessToken: 'active-access-token'),
        permanent: true,
      );

      when(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          '',
          202,
          headers: {'location': '$tpProductionApiUrlBase${uploadStatusPath}abc-123'},
        ),
      );
      when(
        () => mockClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer((_) async => http.Response('Not Found', 404));

      final activity = buildTestActivity();
      final exporter = FitExport();

      final statusCode = await TrainingPeaks(
        'client-id',
        'client-secret',
      ).uploadActivity(activity, [1, 2, 3], exporter, 'client-id', client: mockClient);

      expect(statusCode, 202);
      expect(activity.trainingPeaksUploaded, isFalse);
    });
  });
}
