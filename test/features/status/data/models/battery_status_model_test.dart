import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/status/data/models/battery_status_model.dart';

void main() {
  group('BatteryStatusModel.tryParse', () {
    test('parses a charging battery with a time estimate', () {
      const output =
          "Now drawing from 'AC Power'\n"
          " -InternalBattery-0 (id=22413411)\t88%; charging; 0:42 remaining present: true\n";

      final battery = BatteryStatusModel.tryParse(output);

      expect(battery, isNotNull);
      expect(battery!.percent, 88);
      expect(battery.isCharging, isTrue);
      expect(battery.isPluggedIn, isTrue);
      expect(battery.timeRemaining, const Duration(minutes: 42));
    });

    test('parses "AC attached; not charging" as present and plugged in', () {
      // Regression: an alternation of charging/discharging/charged missed
      // this status, so a plugged-in Mac near full charge reported no battery.
      const output =
          "Now drawing from 'AC Power'\n"
          " -InternalBattery-0 (id=22413411)\t95%; AC attached; not charging present: true\n";

      final battery = BatteryStatusModel.tryParse(output);

      expect(battery, isNotNull);
      expect(battery!.percent, 95);
      expect(battery.isCharging, isFalse);
      expect(battery.isPluggedIn, isTrue);
    });

    test('parses a discharging battery without treating it as charging', () {
      const output =
          "Now drawing from 'Battery Power'\n"
          " -InternalBattery-0 (id=22413411)\t85%; discharging; 3:21 remaining present: true\n";

      final battery = BatteryStatusModel.tryParse(output);

      expect(battery, isNotNull);
      expect(battery!.isCharging, isFalse);
      expect(battery.isPluggedIn, isFalse);
      expect(battery.timeRemaining, const Duration(hours: 3, minutes: 21));
    });

    test('parses a fully charged battery', () {
      const output =
          "Now drawing from 'AC Power'\n"
          " -InternalBattery-0 (id=22413411)\t100%; charged; 0:00 remaining present: true\n";

      final battery = BatteryStatusModel.tryParse(output);

      expect(battery, isNotNull);
      expect(battery!.percent, 100);
      expect(battery.isPluggedIn, isTrue);
    });

    test('returns null when the machine has no battery', () {
      const output = "Now drawing from 'AC Power'\n";

      expect(BatteryStatusModel.tryParse(output), isNull);
    });
  });
}
