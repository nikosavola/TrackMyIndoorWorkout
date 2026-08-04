import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:track_my_indoor_exercise/export/json/json_export.dart';
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

  group('Under Armour uploadActivity', () {
    test('constructs the documented upload request and processes a successful response', () async {
      Get.put<UnderArmourToken>(
        UnderArmourToken(accessToken: 'active-access-token'),
        permanent: true,
      );

      when(
        () => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => http.Response('{"location":"/v7.1/workout/12345/"}', 201));

      final activity = buildTestActivity();
      final exporter = JsonExport();
      final fileContent = [1, 2, 3, 4, 5];

      final underArmour = UnderArmour('client-id', 'client-secret');
      final statusCode = await underArmour.uploadActivity(
        activity,
        fileContent,
        exporter,
        'client-id',
        client: mockClient,
      );

      expect(statusCode, 201);

      // The upload POST must follow Under Armour's documented workout
      // upload contract: https://developer.underarmour.com/docs
      final captured = verify(
        () => mockClient.post(
          captureAny(),
          headers: captureAny(named: 'headers'),
          body: captureAny(named: 'body'),
        ),
      ).captured;
      expect(captured[0], Uri.parse(uploadsEndpoint));
      final headers = captured[1] as Map<String, String>;
      expect(headers['Authorization'], 'Bearer active-access-token');
      expect(headers['Api-Key'], 'client-id');
      expect(headers['Content-Encoding'], 'gzip');
      expect(headers['Content-Length'], fileContent.length.toString());
      expect(captured[2], fileContent);

      expect(activity.underArmourUploaded, isTrue);
      expect(activity.uaWorkoutId, 12345);
    });

    test('returns 401 without making a network call when no token exists', () async {
      final activity = buildTestActivity();
      final exporter = JsonExport();

      final statusCode = await UnderArmour(
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

    test('surfaces a non-2xx response as the returned status code', () async {
      Get.put<UnderArmourToken>(
        UnderArmourToken(accessToken: 'active-access-token'),
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
      final exporter = JsonExport();
      final statusCode = await UnderArmour(
        'client-id',
        'client-secret',
      ).uploadActivity(activity, [1, 2, 3], exporter, 'client-id', client: mockClient);

      expect(statusCode, 400);
      expect(activity.underArmourUploaded, isFalse);
    });

    test(
      'an unexpected 2xx response body (missing the workout location) is handled without throwing',
      () async {
        Get.put<UnderArmourToken>(
          UnderArmourToken(accessToken: 'active-access-token'),
          permanent: true,
        );

        when(
          () => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer((_) async => http.Response('{}', 201));

        final activity = buildTestActivity();
        final exporter = JsonExport();

        final statusCode = await UnderArmour(
          'client-id',
          'client-secret',
        ).uploadActivity(activity, [1, 2, 3], exporter, 'client-id', client: mockClient);

        expect(statusCode, 201);
        expect(activity.underArmourUploaded, isFalse);
      },
    );
  });
}
