// Regression coverage for the writeTxnSync -> writeTxn (async) conversion
// on FitnessEquipment's moving/not-moving transition path (see
// processRecord's WorkoutState.waitingForFirstMove branch).
//
// The write there persists an already-inserted Activity's updated `start`
// timestamp; nothing in processRecord (or its return value) depends on the
// write's completion, since the activity's id was already assigned before
// this code runs. These tests assert:
//  1. processRecord's synchronous return/state-transition behavior is
//     unaffected by the write now being asynchronous and fire-and-forget.
//  2. The write still actually lands in the database (no data is silently
//     dropped just because the transaction isn't awaited inline).
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:isar_community/isar.dart';
import 'package:mock_data/mock_data.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:track_my_indoor_exercise/devices/device_factory.dart';
import 'package:track_my_indoor_exercise/devices/device_fourcc.dart';
import 'package:track_my_indoor_exercise/devices/gadgets/fitness_equipment.dart';
import 'package:track_my_indoor_exercise/persistence/activity.dart';
import 'package:track_my_indoor_exercise/persistence/record.dart';
import 'package:track_my_indoor_exercise/utils/init_preferences.dart';

import 'database/in_memory_database.dart';

class MockBluetoothDevice extends Mock implements BluetoothDevice {}

void main() {
  setUpAll(() async {
    await initPrefServiceForTest();
  });

  tearDown(() {
    // Isar is registered only for the second half of the test below (right
    // before the write-under-test runs), specifically to avoid
    // FitnessEquipment.setActivity's readConfiguration()/refreshFactors()
    // call touching unrelated powerTunes/calorieTunes collections that
    // this lightweight in-memory fake doesn't provide.
    if (Get.isRegistered<Isar>()) {
      Get.delete<Isar>();
    }
  });

  test('processRecord persists the moving-transition activity write asynchronously '
      'without changing its synchronous return value', () async {
    final descriptor = DeviceFactory.getSchwinnIcBike();
    final longAgo = DateTime.now().subtract(const Duration(minutes: 5));
    final activity = Activity(
      deviceId: mPowerImportDeviceId,
      deviceName: descriptor.modelName,
      hrmId: "",
      start: longAgo,
      fourCC: descriptor.fourCC,
      sport: descriptor.sport,
      powerFactor: 1.0,
      calorieFactor: 1.0,
      hrCalorieFactor: 1.0,
      hrmCalorieFactor: 1.0,
      hrBasedCalories: false,
      timeZone: "America/Los_Angeles",
    );

    final mockDevice = MockBluetoothDevice();
    when(() => mockDevice.remoteId).thenReturn(const DeviceIdentifier("TEST_ID"));
    // Isar isn't registered yet, so both the constructor's
    // readConfiguration() and setActivity's own readConfiguration() call
    // skip refreshFactors (it early-returns when Isar isn't registered),
    // matching how the other FitnessEquipment tests avoid needing a full
    // database for unrelated collections.
    final equipment = FitnessEquipment(descriptor: descriptor, device: mockDevice);
    equipment.initPower2SpeedConstants();
    await equipment.setActivity(activity);

    // Now bring up Isar and mimic _startMeasurement: the activity is
    // inserted (and its id assigned) before the moving-transition write
    // we're testing ever runs. This matches production ordering, where
    // the activity is always persisted - and its id assigned - well
    // before FitnessEquipment's processRecord touches it.
    final database = InMemoryDatabase(mockUUID());
    Get.put<Isar>(database);
    final assignedId = await database.activitys.put(activity);
    expect(assignedId, isNot(Isar.autoIncrement));
    expect(activity.id, assignedId);

    equipment.workoutState = WorkoutState.waitingForFirstMove;
    final record = equipment.processRecord(RecordWithSport(sport: descriptor.sport, speed: 8.0));

    // Synchronous behavior must be identical to the old writeTxnSync
    // version: the state machine has already transitioned and the
    // in-memory activity start has already been bumped, even though the
    // DB commit for that bump is still pending in the background.
    expect(equipment.workoutState, WorkoutState.startedMoving);
    expect(activity.start.isAfter(longAgo), true);
    expect(record.sport, descriptor.sport);

    // Let the fire-and-forget writeTxn's microtasks flush.
    await Future.delayed(Duration.zero);
    await Future.delayed(Duration.zero);

    final persisted = await database.activitys.get(assignedId);
    expect(persisted, isNotNull);
    expect(persisted!.start, activity.start);
  });
}
