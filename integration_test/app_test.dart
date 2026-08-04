// End-to-end integration test for the CSV import flow, run against a real
// device/emulator (or a configured browser target for web) via `flutter
// drive` or `flutter test integration_test/app_test.dart -d <device>`.
//
// NOTE: this test needs an attached Android/iOS device, an emulator, or a
// configured `flutter drive` web/desktop target -- it cannot run in a plain
// `flutter test` invocation and was not executable in the sandbox this test
// was authored in. See test/ui/csv_import_activity_flow_test.dart for the
// `flutter test`-runnable widget-test counterpart of this same flow, which
// *was* run and verified there.
//
// Flow covered (mirrors test/ui/csv_import_activity_flow_test.dart):
//   1. Boot the real app (app.main()), landing on the real home screen
//      (FindDevicesScreen -- this needs no actual Bluetooth hardware to
//      just sit there and let us navigate away from it).
//   2. Navigate to the Activities screen via the find-devices FAB menu.
//   3. Open the Activities FAB menu and start a CSV import.
//   4. Pick "Migration" format, land on the Import form.
//   5. Point the form at a real temporary CSV file (built with the same
//      CsvExport used by test/csv_export_import_test.dart) and import it.
//   6. Verify the imported activity shows up back in the Activities list.
//   7. Expand it and drill into its detail screen, verifying key fields
//      (device name, calories) render there too.
//
// Unlike the widget-test counterpart, this drives the real app: a real Isar
// database (persisted on the test device -- this is a mutating test, not an
// isolated one), real preferences, and the real FindDevicesScreen home
// screen (Bluetooth permissions prompts on first launch are a real risk on
// a fresh device/emulator and are not handled here).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:track_my_indoor_exercise/devices/device_factory.dart';
import 'package:track_my_indoor_exercise/export/csv/csv_export.dart';
import 'package:track_my_indoor_exercise/export/export_model.dart';
import 'package:track_my_indoor_exercise/export/export_record.dart';
import 'package:track_my_indoor_exercise/persistence/activity.dart';
import 'package:track_my_indoor_exercise/persistence/record.dart';
import 'package:track_my_indoor_exercise/ui/activities.dart';
import 'package:track_my_indoor_exercise/ui/details/activity_details.dart';
import 'package:track_my_indoor_exercise/utils/constants.dart';

import 'package:track_my_indoor_exercise/main.dart' as app;

/// Builds a small, valid migration-format CSV (same shape as
/// test/csv_export_import_test.dart and the CSV importer expects) and writes
/// it to a real file in the device's temporary directory, returning its
/// path.
Future<String> _writeSampleMigrationCsv() async {
  final descriptor = DeviceFactory.getSchwinnIcBike();
  final start = DateTime(2026, 1, 15, 8, 0, 0);
  const recordCount = 40;
  const calories = 321; // Distinctive value asserted on both screens.
  const distance = 8000.0; // 8 km.
  final distancePerTick = distance / recordCount;
  final caloriesPerTick = calories / recordCount;

  final activity = Activity(
    deviceName: descriptor.modelName,
    deviceId: "E2E-INTEGRATION-TEST-DEVICE",
    hrmId: "",
    start: start,
    end: start.add(const Duration(seconds: recordCount)),
    distance: distance,
    elapsed: recordCount,
    movingTime: recordCount * 1000,
    calories: calories,
    fourCC: descriptor.fourCC,
    sport: descriptor.sport,
    powerFactor: 1.0,
    calorieFactor: 1.0,
    hrCalorieFactor: 1.0,
    hrmCalorieFactor: 1.0,
    hrBasedCalories: false,
    timeZone: "America/Los_Angeles",
  );

  // Vary power/speed/cadence across records -- a perfectly constant value
  // degenerates the detail screen's histogram binning to a zero-width
  // (empty) histogram and crashes when a record is binned into it.
  final records = List<ExportRecord>.generate(
    recordCount,
    (index) => ExportRecord(
      record: Record(
        activityId: activity.id,
        timeStamp: activity.start.add(Duration(seconds: index)),
        distance: distancePerTick * index,
        elapsed: index,
        calories: (caloriesPerTick * index).round(),
        power: 120 + index,
        speed: 20.0 + (index % 10),
        cadence: 80 + (index % 15),
        heartRate: 130 + (index % 20),
        elapsedMillis: index * 1000,
        sport: descriptor.sport,
      ),
    ),
  );

  final exportModel = ExportModel(
    activity: activity,
    rawData: true,
    calculateGps: false,
    descriptor: descriptor,
    author: "Csaba Consulting",
    name: appName,
    swVersionMajor: "1",
    swVersionMinor: "0",
    buildVersionMajor: "1",
    buildVersionMinor: "0",
    langID: "en-US",
    partNumber: "0",
    altitude: 0.0,
    records: records,
  );

  final csvBytes = await CsvExport().getFileCore(exportModel);
  final tempDir = await getTemporaryDirectory();
  final csvFile = File("${tempDir.path}/sample_activity_integration_test.csv");
  await csvFile.writeAsBytes(csvBytes, flush: true);
  return csvFile.path;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('CSV import flow: import a workout and see it in the list and details', (
    tester,
  ) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 5));

    final csvFilePath = await _writeSampleMigrationCsv();

    // From the real home screen (FindDevicesScreen), navigate to Activities
    // via its FAB menu -- no Bluetooth hardware needed for this hop.
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.list_alt));
    await tester.pumpAndSettle();
    expect(find.byType(ActivitiesScreen), findsOneWidget);

    // Starts out without our distinctive test activity.
    expect(find.text('Schwinn IC4/IC8'), findsNothing);

    // Open the Activities FAB menu and start a CSV import.
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.file_upload));
    await tester.pumpAndSettle();

    // ImportFormatPickerBottomSheet: choose "Migration" and confirm.
    expect(find.text('Migration'), findsOneWidget);
    await tester.tap(find.text('Migration'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.check));
    await tester.pumpAndSettle();

    // Now on the ImportForm (migration mode: no date/time field required).
    expect(find.text('Workout Migration Import'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, csvFilePath);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Import'));
    await tester.pumpAndSettle();

    // Import succeeded (snackbar shown, still on the import screen).
    expect(find.text('Workout imported!'), findsOneWidget);

    // `Get.back()` with the default arguments only closes the still-open
    // success snackbar (GetX 4.x compatibility behaviour); ask it to close
    // overlays too so it actually pops the ImportForm route, same as the
    // AppBar back button would.
    Get.back(closeOverlays: true);
    await tester.pumpAndSettle();

    // The imported activity is now in the list.
    expect(find.text('Schwinn IC4/IC8'), findsOneWidget);
    expect(find.text('321'), findsOneWidget); // calories, list view

    // The FAB circular menu opened earlier is still open (selecting one of
    // its ring items doesn't auto-close it); close it before interacting
    // with the list underneath.
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    // Expand the card and drill into the activity's detail screen.
    await tester.tap(find.text('Schwinn IC4/IC8'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();

    expect(find.byType(ActivityDetailsScreen), findsOneWidget);
    expect(find.text('Schwinn IC4/IC8'), findsWidgets);
    expect(find.text('321'), findsWidgets); // calories, detail view
  });
}
