import 'dart:async';
import 'dart:math';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:track_my_indoor_exercise/devices/device_factory.dart';
import 'package:track_my_indoor_exercise/devices/gadgets/fitness_equipment.dart';
import 'package:track_my_indoor_exercise/preferences/ftms_data_threshold.dart';
import 'package:track_my_indoor_exercise/utils/init_preferences.dart';
import 'package:track_my_indoor_exercise/utils/bluetooth_adapter.dart';

import 'utils.dart';

class MockBluetoothDevice extends Mock implements BluetoothDevice {}

class MockBluetoothService extends Mock implements BluetoothService {}

class MockBluetoothCharacteristic extends Mock implements BluetoothCharacteristic {}

class MockBluetoothAdapter extends Mock implements BluetoothAdapter {}

void main() {
  setUpAll(() async {
    await initPrefServiceForTest();
    if (!Get.isRegistered<BluetoothAdapter>()) {
      final mockAdapter = MockBluetoothAdapter();
      when(() => mockAdapter.isBluetoothOn()).thenAnswer((_) async => true);
      Get.put<BluetoothAdapter>(mockAdapter);
    }
  });

  group('discover', () {
    BluetoothService createMockBluetoothService({
      required String serviceUid,
      required String characteristicUid,
      List<int> characteristicData = const [],
    }) {
      final serviceMock = MockBluetoothService();
      final mockCharacteristic = MockBluetoothCharacteristic();
      final mockServiceGuid = Guid(serviceUid);
      final mockCharacteristicGuid = Guid(characteristicUid);
      when(() => serviceMock.serviceUuid).thenReturn(mockServiceGuid);
      when(() => serviceMock.characteristics).thenReturn([mockCharacteristic]);
      when(() => mockCharacteristic.characteristicUuid).thenReturn(mockCharacteristicGuid);
      when(() => mockCharacteristic.read()).thenAnswer((_) async => characteristicData);
      return serviceMock;
    }

    void stubRemoteId(MockBluetoothDevice mockDevice) {
      when(() => mockDevice.remoteId).thenReturn(const DeviceIdentifier("TEST_ID"));
    }

    BluetoothService createMockFtmsService({
      String serviceUid = '00001826-0000-1000-8000-00805f9b34fb',
      String characteristicUid = '00002ad2-0000-1000-8000-00805f9b34fb',
    }) => createMockBluetoothService(serviceUid: serviceUid, characteristicUid: characteristicUid);

    BluetoothService createMockDeviceInfoService({required String manufacturerName}) =>
        createMockBluetoothService(
          serviceUid: '0000180a-0000-1000-8000-00805f9b34fb',
          characteristicUid: '00002a29-0000-1000-8000-00805f9b34fb',
          characteristicData: manufacturerName.codeUnits,
        );

    test('handles truncated fitness machine features payload without crashing', () async {
      final mockDevice = MockBluetoothDevice();

      final mockFtmsService = MockBluetoothService();
      when(
        () => mockFtmsService.serviceUuid,
      ).thenReturn(Guid('00001826-0000-1000-8000-00805f9b34fb'));

      final mockFeatureCharacteristic = MockBluetoothCharacteristic();
      when(
        () => mockFeatureCharacteristic.characteristicUuid,
      ).thenReturn(Guid('00002acc-0000-1000-8000-00805f9b34fb'));
      when(
        () => mockFeatureCharacteristic.read(),
      ).thenAnswer((_) async => [0x01, 0x02]); // Truncated length 2

      final mockBikeCharacteristic = MockBluetoothCharacteristic();
      when(
        () => mockBikeCharacteristic.characteristicUuid,
      ).thenReturn(Guid('00002ad2-0000-1000-8000-00805f9b34fb'));
      when(() => mockBikeCharacteristic.read()).thenAnswer((_) async => <int>[]);
      when(() => mockBikeCharacteristic.lastValueStream).thenAnswer((_) => Stream.empty());

      when(
        () => mockFtmsService.characteristics,
      ).thenReturn([mockFeatureCharacteristic, mockBikeCharacteristic]);

      final mockDeviceInfoService = createMockDeviceInfoService(manufacturerName: 'FUJIAN YESOUL');

      stubRemoteId(mockDevice);
      when(
        () => mockDevice.discoverServices(subscribeToServicesChanged: false),
      ).thenAnswer((_) async => [mockFtmsService, mockDeviceInfoService]);

      final deviceDescriptor = DeviceFactory.getYesoulS3();
      final equipment = FitnessEquipment(descriptor: deviceDescriptor, device: mockDevice);
      equipment.blockManufacturerNameReading = false;
      equipment.blockFTMSFeatureRead = false;
      equipment.connected = true;

      // The test passes if this does not throw a RangeError
      expect(await equipment.discover(), true);
      expect(equipment.readFeatures, 513); // 0x01 + 256 * 0x02 = 1 + 512 = 513
      expect(equipment.writeFeatures, 0); // Padded with zeros
    });

    test('ignores case in manufacturer check', () async {
      final mockDevice = MockBluetoothDevice();
      final mockFtmsService = createMockFtmsService();
      final mockDeviceInfoService = createMockDeviceInfoService(manufacturerName: 'FUJIAN YESOUL');
      stubRemoteId(mockDevice);
      when(
        () => mockDevice.discoverServices(subscribeToServicesChanged: false),
      ).thenAnswer((_) async => [mockFtmsService, mockDeviceInfoService]);

      final deviceDescriptor = DeviceFactory.getYesoulS3();
      final equipment = FitnessEquipment(descriptor: deviceDescriptor, device: mockDevice);
      equipment.blockManufacturerNameReading = false;
      equipment.connected = true;

      expect(await equipment.discover(), true);
      expect(equipment.manufacturerName, "FUJIAN YESOUL");
    });

    test('handles manufacturer name being null in manufacturer check', () async {
      final mockDevice = MockBluetoothDevice();
      const anotherUid = '00000000-0000-1000-8000-00805f9b34fb';
      final mockFtmsService = createMockFtmsService(characteristicUid: anotherUid);
      final mockDeviceInfoService = createMockDeviceInfoService(manufacturerName: 'FUJIAN YESOUL');
      stubRemoteId(mockDevice);
      when(
        () => mockDevice.discoverServices(subscribeToServicesChanged: false),
      ).thenAnswer((_) async => [mockFtmsService, mockDeviceInfoService]);

      final deviceDescriptor = DeviceFactory.getYesoulS3();
      final equipment = FitnessEquipment(descriptor: deviceDescriptor, device: mockDevice);
      equipment.blockManufacturerNameReading = false;
      equipment.connected = true;

      expect(await equipment.discover(), false);
    });

    test('handles descriptor being null in manufacturer check', () async {
      final mockDevice = MockBluetoothDevice();
      final mockFtmsService = createMockFtmsService();
      final mockDeviceInfoService = createMockDeviceInfoService(manufacturerName: 'FUJIAN YESOUL');
      stubRemoteId(mockDevice);
      when(
        () => mockDevice.discoverServices(subscribeToServicesChanged: false),
      ).thenAnswer((_) async => [mockFtmsService, mockDeviceInfoService]);

      final equipment = FitnessEquipment(descriptor: null, device: mockDevice);
      equipment.blockManufacturerNameReading = false;
      equipment.connected = true;

      expect(await equipment.discover(), false);
    });
  });

  group('keySelector handles 1 byte flags as expected', () {
    final rnd = Random();
    getRandomInts(smallRepetition, 255, rnd).forEach((flag) {
      test('$flag', () async {
        final descriptor = DeviceFactory.getCSCBasedBike();
        final equipment = FitnessEquipment(descriptor: descriptor, device: MockBluetoothDevice());

        final selector = equipment.keySelector([flag]);

        expect(selector, flag);
      });
    });
  });

  group('keySelector handles 2 byte flags as expected', () {
    final rnd = Random();
    getRandomInts(smallRepetition, 255, rnd).forEach((flagLsb) {
      final flagMsb = rnd.nextInt(255);
      test('[$flagLsb, $flagMsb]', () async {
        final descriptor = DeviceFactory.getPowerMeterBasedBike();
        final equipment = FitnessEquipment(descriptor: descriptor, device: MockBluetoothDevice());

        final selector = equipment.keySelector([flagLsb, flagMsb]);

        expect(selector, flagLsb + 256 * flagMsb);
      });
    });
  });

  group('keySelector handles 3 byte flags as expected', () {
    final rnd = Random();
    getRandomInts(smallRepetition, 255, rnd).forEach((flagLsb) {
      final flagMid = rnd.nextInt(255);
      final flagMsb = rnd.nextInt(255);
      test('[$flagLsb, $flagMid, $flagMsb]', () async {
        final descriptor = DeviceFactory.getGenericFTMSCrossTrainer();
        final equipment = FitnessEquipment(descriptor: descriptor, device: MockBluetoothDevice());

        final selector = equipment.keySelector([flagLsb, flagMid, flagMsb]);

        expect(selector, flagLsb + 256 * flagMid + 65536 * flagMsb);
      });
    });
  });

  group('detach', () {
    // Regression test for the timer/subscription leak that caused a crash
    // when disconnecting a device without stopping the workout first
    // (see commit 78725f4, "Null check operator used on a null value...
    // disconnecting cross trainer").
    test('detach() without stopWorkout() cancels the throttle timer so no '
        'further callbacks fire after detaching', () async {
      final mockDevice = MockBluetoothDevice();
      final mockCharacteristic = MockBluetoothCharacteristic();
      final streamController = StreamController<List<int>>();
      addTearDown(streamController.close);

      when(() => mockCharacteristic.lastValueStream).thenAnswer((_) => streamController.stream);
      when(() => mockCharacteristic.setNotifyValue(any())).thenAnswer((_) async => true);

      final descriptor = DeviceFactory.getSchwinnIcBike();
      final equipment = FitnessEquipment(descriptor: descriptor, device: mockDevice);
      equipment.characteristic = mockCharacteristic;
      equipment.attached = true;
      equipment.measuring = true;

      var callbackCount = 0;
      equipment.pumpData((data) {
        callbackCount++;
      });

      // Let the stream subscription set up inside pumpData() actually attach.
      await Future.delayed(Duration.zero);

      // A real Schwinn IC4 FTMS Indoor Bike Data packet (speed, cadence,
      // power, heart rate) - taken from schwinn_ic4_test.dart. Feeding it
      // through the real data pipeline causes _startThrottlingTimer() to
      // arm the (until now leaking) `_throttleTimer`.
      streamController.add([68, 2, 94, 11, 240, 0, 122, 0, 84]);
      await Future.delayed(Duration.zero);

      expect(callbackCount, 1);

      // Detach WITHOUT calling stopWorkout() first. Before the fix this left
      // `_throttleTimer` running even though the device is no longer attached,
      // so it would keep firing and re-invoking the record handler with the
      // last buffered (now stale) data indefinitely.
      await equipment.detach();

      // Wait past the throttle interval with no further inbound data. Before
      // the fix the still-armed `_throttleTimer` would fire here and
      // re-invoke the callback with the previously buffered data, even
      // though detach() had already run and no new data arrived.
      await Future.delayed(const Duration(milliseconds: ftmsDataThresholdDefault + 300));

      expect(
        callbackCount,
        1,
        reason: 'no callback should fire from a leaked throttle timer after detach()',
      );
    });
  });
}
