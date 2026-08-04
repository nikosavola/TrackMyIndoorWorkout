// End-to-end-style widget test for the CSV import flow.
//
// This exercises the app's real production widgets (ActivitiesScreen,
// ImportFormatPickerBottomSheet, ImportForm, ActivityDetailsScreen) wired
// together the same way the app wires them (via GetX navigation), rather
// than testing each widget in isolation. It is the `flutter test` companion
// to `integration_test/app_test.dart`, which drives the same kind of flow
// against a real device/emulator (not runnable in this environment).
//
// Flow covered:
//   1. Land on the Activities screen (empty).
//   2. Open the FAB menu and start a CSV import.
//   3. Pick "Migration" format, land on the Import form.
//   4. Point the form at a real temporary CSV file (built with the same
//      CsvExport used elsewhere, see test/csv_export_import_test.dart) and
//      import it.
//   5. Navigate back to the Activities list and verify the imported
//      activity shows up.
//   6. Expand it, drill into its detail screen, and verify key fields
//      (device name, calories) render there too.
//
// What this cannot cover (needs a real device/emulator, see
// integration_test/app_test.dart instead): Bluetooth device discovery,
// the FindDevicesScreen home screen, permissions prompts, and the native
// file picker used by the "..." button on the Import form (this test enters
// the file path directly into the text field instead, which the production
// form also supports).

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:isar_community/isar.dart';
import 'package:mock_data/mock_data.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pref/pref.dart';
import 'package:track_my_indoor_exercise/devices/device_factory.dart';
import 'package:track_my_indoor_exercise/export/csv/csv_export.dart';
import 'package:track_my_indoor_exercise/export/export_model.dart';
import 'package:track_my_indoor_exercise/export/export_record.dart';
import 'package:track_my_indoor_exercise/persistence/activity.dart';
import 'package:track_my_indoor_exercise/persistence/record.dart';
import 'package:track_my_indoor_exercise/persistence/workout_summary.dart';
import 'package:track_my_indoor_exercise/ui/activities.dart';
import 'package:track_my_indoor_exercise/ui/details/activity_details.dart';
import 'package:track_my_indoor_exercise/utils/constants.dart';
import 'package:track_my_indoor_exercise/utils/init_preferences.dart';
import 'package:track_my_indoor_exercise/utils/theme_manager.dart';

import '../database/activity_collection.dart';
import '../database/record_collection.dart';

/// Minimal in-memory stand-in for the `workoutSummarys` Isar collection.
///
/// `ActivitiesScreen` unconditionally asks `DbUtils().hasLeaderboardData()`
/// (regardless of whether the leaderboard feature is enabled) while building
/// its FAB menu, so the collection has to exist even though this flow never
/// writes to it (the leaderboard feature defaults to off).
class _FakeWorkoutSummaryCollection extends IsarCollection<WorkoutSummary> {
  final List<WorkoutSummary> objs = [];
  final Isar inMemoryIsar;
  int nextId = 0;

  _FakeWorkoutSummaryCollection(this.inMemoryIsar);

  @override
  Query<R> buildQuery<R>({
    List<WhereClause> whereClauses = const [],
    bool whereDistinct = false,
    Sort whereSort = Sort.asc,
    FilterOperation? filter,
    List<SortProperty> sortBy = const [],
    List<DistinctProperty> distinctBy = const [],
    int? offset,
    int? limit,
    String? property,
  }) => throw UnimplementedError();

  @override
  Isar get isar => inMemoryIsar;

  @override
  CollectionSchema<WorkoutSummary> get schema => WorkoutSummarySchema;

  @override
  Future<void> clear() async => clearSync();

  @override
  void clearSync() => objs.clear();

  @override
  Future<int> count() async => countSync();

  @override
  int countSync() => objs.length;

  @override
  Future<int> deleteAll(List<Id> ids) async => deleteAllSync(ids);

  @override
  Future<int> deleteAllByIndex(String indexName, List<IndexKey> keys) async =>
      deleteAllByIndexSync(indexName, keys);

  @override
  int deleteAllByIndexSync(String indexName, List<IndexKey> keys) => throw UnimplementedError();

  @override
  int deleteAllSync(List<Id> ids) {
    final before = objs.length;
    objs.removeWhere((o) => ids.contains(o.id));
    return before - objs.length;
  }

  @override
  Future<List<WorkoutSummary?>> getAll(List<Id> ids) async => getAllSync(ids);

  @override
  Future<List<WorkoutSummary?>> getAllByIndex(String indexName, List<IndexKey> keys) async =>
      getAllByIndexSync(indexName, keys);

  @override
  List<WorkoutSummary?> getAllByIndexSync(String indexName, List<IndexKey> keys) =>
      throw UnimplementedError();

  @override
  List<WorkoutSummary?> getAllSync(List<Id> ids) => objs.where((o) => ids.contains(o.id)).toList();

  @override
  Future<int> getSize({bool includeIndexes = false, bool includeLinks = false}) async =>
      throw UnimplementedError();

  @override
  int getSizeSync({bool includeIndexes = false, bool includeLinks = false}) =>
      throw UnimplementedError();

  @override
  Future<void> importJson(List<Map<String, dynamic>> json) async => throw UnimplementedError();

  @override
  Future<void> importJsonRaw(Uint8List jsonBytes) async => throw UnimplementedError();

  @override
  void importJsonRawSync(Uint8List jsonBytes) => throw UnimplementedError();

  @override
  void importJsonSync(List<Map<String, dynamic>> json) => throw UnimplementedError();

  @override
  Future<List<Id>> putAll(List<WorkoutSummary> objects) async => putAllSync(objects);

  @override
  Future<List<Id>> putAllByIndex(String indexName, List<WorkoutSummary> objects) async =>
      putAllByIndexSync(indexName, objects);

  @override
  List<Id> putAllByIndexSync(
    String indexName,
    List<WorkoutSummary> objects, {
    bool saveLinks = true,
  }) => putAllSync(objects);

  @override
  List<Id> putAllSync(List<WorkoutSummary> objects, {bool saveLinks = true}) {
    final ids = <Id>[];
    for (final object in objects) {
      final id = nextId++;
      object.id = id;
      objs.add(object);
      ids.add(id);
    }
    return ids;
  }

  @override
  Future<void> verify(List<WorkoutSummary> objects) async {}

  @override
  Future<void> verifyLink(String linkName, List<int> sourceIds, List<int> targetIds) async {}

  @override
  Stream<void> watchLazy({bool fireImmediately = false}) => throw UnimplementedError();

  @override
  Stream<WorkoutSummary?> watchObject(Id id, {bool fireImmediately = false}) =>
      throw UnimplementedError();

  @override
  Stream<void> watchObjectLazy(Id id, {bool fireImmediately = false}) => throw UnimplementedError();
}

/// [ActivityCollection] (from the shared test database fake) always assigns
/// a fresh id and appends on every `putSync`, rather than upserting by id.
/// The CSV importer calls `activitys.putSync(activity)` twice for the same
/// activity (once before writing its records, once after, to persist the
/// final totals) which, with that behaviour, leaves two list entries that
/// are literally the same object/id -- fine for the already-existing tests
/// that only look records up by `activityId`, but fatal for
/// `ActivitiesScreen`, which keys each list entry by
/// `activity.uniqueIntegrationString()` and hits a duplicate-key error.
/// Override with a proper upsert so the Activities list renders sanely.
class _UpsertingActivityCollection extends ActivityCollection {
  _UpsertingActivityCollection(super.inMemoryIsar);

  @override
  List<Id> putAllSync(List<Activity> objects, {bool saveLinks = true}) {
    final ids = <Id>[];
    for (final object in objects) {
      final id = object.id == Isar.autoIncrement ? nextId++ : object.id;
      object.id = id;
      final existingIndex = objs.indexWhere((o) => o.id == id);
      if (existingIndex >= 0) {
        objs[existingIndex] = object;
      } else {
        objs.add(object);
      }
      ids.add(id);
    }
    return ids;
  }
}

/// [InMemoryDatabase] only attaches Activity + Record collections, and Isar's
/// `_collections` field can only be assigned once, so it can't be
/// re-attached after the fact. Mirror its plumbing here with a fake
/// WorkoutSummary collection added, so the Activities screen (and its FAB
/// menu, which unconditionally checks for leaderboard data) can be built
/// without touching a real Isar instance.
class _TestDatabase extends Isar {
  late final IsarCollection<Activity> activities;
  late final IsarCollection<Record> records;

  _TestDatabase(super.name) {
    activities = _UpsertingActivityCollection(this);
    records = RecordCollection(this);
    attachCollections({
      Activity: activities,
      Record: records,
      WorkoutSummary: _FakeWorkoutSummaryCollection(this),
    });
  }

  @override
  Future<void> copyToFile(String targetPath) async {}

  @override
  String? get directory => "/tmp";

  @override
  Future<int> getSize({bool includeIndexes = false, bool includeLinks = false}) async => 1;

  @override
  int getSizeSync({bool includeIndexes = false, bool includeLinks = false}) => 1;

  @override
  Future<T> txn<T>(Future<T> Function() callback) async => await callback.call();

  @override
  T txnSync<T>(T Function() callback) => callback.call();

  @override
  Future<void> verify() async {}

  @override
  Future<T> writeTxn<T>(Future<T> Function() callback, {bool silent = false}) async =>
      await callback.call();

  @override
  T writeTxnSync<T>(T Function() callback, {bool silent = false}) => callback.call();
}

Future<String> _writeSampleMigrationCsv(Directory dir) async {
  final descriptor = DeviceFactory.getSchwinnIcBike();
  final start = DateTime(2026, 1, 15, 8, 0, 0);
  const recordCount = 40;
  const calories = 321; // Distinctive value asserted on both screens.
  const distance = 8000.0; // 8 km, distinctive-ish and easy to reason about.
  final distancePerTick = distance / recordCount;
  final caloriesPerTick = calories / recordCount;

  final activity = Activity(
    deviceName: descriptor.modelName,
    deviceId: "E2E-TEST-DEVICE",
    hrmId: mockName(),
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

  // Vary power/speed/cadence across records (not just heart rate) -- the
  // detail screen bins each measurement into histogram zones based on its
  // observed min/max, and a perfectly constant value degenerates that to a
  // zero-width (empty) histogram, which then blows up when a record's value
  // is binned into it.
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
  final csvFile = File("${dir.path}/sample_activity.csv");
  await csvFile.writeAsBytes(csvBytes, flush: true);
  return csvFile.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String csvFilePath;
  late BasePrefService prefService;

  setUp(() async {
    Get.testMode = true;
    Get.reset();

    Get.put<Isar>(_TestDatabase(mockUUID()), permanent: true);
    await initPrefServiceForTest();
    prefService = Get.find<BasePrefService>();
    Get.put<ThemeManager>(ThemeManager(), permanent: true);
    Get.put<PackageInfo>(
      PackageInfo(
        appName: appName,
        packageName: "dev.csaba.track_my_indoor_exercise",
        buildNumber: "1",
        version: "1.0.0",
      ),
    );

    tempDir = await Directory.systemTemp.createTemp('csv_import_e2e_');
    csvFilePath = await _writeSampleMigrationCsv(tempDir);
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
    Get.reset();
  });

  Widget buildTestApp() {
    return PrefService(
      service: prefService,
      child: GetMaterialApp(debugShowCheckedModeBanner: false, home: const ActivitiesScreen()),
    );
  }

  testWidgets('CSV import flow: import a workout and see it in the list and details', (
    tester,
  ) async {
    await tester.pumpWidget(buildTestApp());
    await tester.pumpAndSettle();

    // Starts out empty.
    expect(find.text('No activities found'), findsOneWidget);
    expect(find.text('Schwinn IC4/IC8'), findsNothing);

    // Open the FAB circular menu and tap "Import".
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
    // The import reads a real file off disk (dart:io), which needs the real
    // event loop rather than flutter_test's fake one to actually complete, so
    // the tap (and the async handler it triggers) has to run inside
    // `runAsync`.
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(ElevatedButton, 'Import'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    // Pump (without settling) so the success snackbar is caught before its
    // own auto-dismiss timer, driven by pumpAndSettle, closes it again.
    await tester.pump();

    // Import succeeded (snackbar shown, still on the import screen).
    expect(find.text('Workout imported!'), findsOneWidget);

    // Navigate back to the Activities list the same way the app does
    // (Get.back(), as used by every "back"/"close" action in this app) --
    // the GetX success snackbar is a separate overlay on its own dismiss
    // timer and would otherwise sit on top of the AppBar's back button.
    // `Get.back()` with the default arguments only closes the still-open
    // success snackbar (GetX 4.x compatibility behaviour); ask it to close
    // overlays too so it actually pops the ImportForm route.
    Get.back(closeOverlays: true);
    await tester.pumpAndSettle();

    // The imported activity is now in the list.
    expect(find.text('Schwinn IC4/IC8'), findsOneWidget);
    expect(find.text('No activities found'), findsNothing);
    expect(find.text('321'), findsOneWidget); // calories, list view

    // The FAB circular menu we opened earlier (to start the import) is still
    // open -- selecting one of its ring items doesn't auto-close it -- and
    // its ring sits, transparent but still hit-testable, on top of much of
    // the screen. Close it the same way a user would (tap the FAB again)
    // before interacting with the list underneath.
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    // Expand the card, revealing its action row (export/tune/delete/detail
    // icons crammed into a `FitHorizontally`-shrunk row).
    await tester.tap(find.text('Schwinn IC4/IC8'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);

    // Drill into the detail screen the same way the chevron_right button
    // does (`Get.to(() => ActivityDetailsScreen(activity: ..., size: ...))`).
    // The action row packs six-plus densely-scaled icons into one line via
    // that shrink-to-fit row, which on this test harness's default surface
    // leaves several of them overlapping at the pixel level -- tapping
    // reliably lands on a neighbouring icon rather than the intended one.
    // Everything up to here (opening the app, importing, and seeing the
    // result land in the list) is exercised via real taps; only this last
    // hop uses the same navigation call the button performs, to sidestep
    // that layout-specific hit-testing flakiness rather than the CSV import
    // behaviour this test is actually about.
    final importedActivity = Get.find<Isar>().activitys.where().findFirstSync();
    expect(importedActivity, isNotNull);
    Get.to(() => ActivityDetailsScreen(activity: importedActivity!, size: Get.mediaQuery.size));
    await tester.pumpAndSettle();

    expect(find.byType(ActivityDetailsScreen), findsOneWidget);
    expect(find.text('Schwinn IC4/IC8'), findsWidgets);
    expect(find.text('321'), findsWidgets); // calories, detail view
  });
}
