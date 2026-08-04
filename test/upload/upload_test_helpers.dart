import 'package:get/get.dart';
import 'package:isar_community/isar.dart';
import 'package:mock_data/mock_data.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:track_my_indoor_exercise/persistence/activity.dart';
import 'package:track_my_indoor_exercise/utils/constants.dart';
import 'package:track_my_indoor_exercise/utils/init_preferences.dart';

import '../database/in_memory_database.dart';

/// Shared scaffolding for the upload provider tests: a real (in-memory)
/// preference service, package info, and an in-memory Isar database.
///
/// This mirrors the setup used elsewhere in the suite, see
/// test/csv_export_import_test.dart and test/data_handler_test.dart.
Future<void> setUpUploadTestEnvironment() async {
  await initPrefServiceForTest();
  Get.put<PackageInfo>(
    PackageInfo(
      appName: "Track My Indoor Workout",
      packageName: "dev.csaba.track_my_indoor_exercise",
      buildNumber: "199",
      version: "1.0.199",
    ),
  );
  Get.put<Isar>(InMemoryDatabase(mockUUID()), permanent: true);
}

/// A minimal, deterministic [Activity] usable across the upload provider
/// tests. Field values are arbitrary but stable so assertions can rely on
/// them.
Activity buildTestActivity({int id = 1}) {
  return Activity(
    id: id,
    deviceName: "Test Trainer",
    deviceId: "AA:BB:CC:DD:EE:FF",
    hrmId: "",
    start: DateTime(2026, 1, 1, 8, 0, 0),
    fourCC: "0000",
    sport: ActivityType.ride,
    powerFactor: 1.0,
    calorieFactor: 1.0,
    hrCalorieFactor: 1.0,
    hrmCalorieFactor: 1.0,
    hrBasedCalories: false,
    timeZone: "America/Los_Angeles",
  );
}
