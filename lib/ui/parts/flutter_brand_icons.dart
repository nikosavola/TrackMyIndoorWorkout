import "package:flutter/widgets.dart";

// `IconData` became a `final` class in a recent Flutter/Dart SDK release, so
// it can no longer be subclassed. `BrandIcons` now exposes plain `IconData`
// constants instead of instances of a `BrandIconData` subclass; call sites
// that only use these as `IconData` values are unaffected.
class BrandIcons {
  static const IconData fitbit = IconData(0xe9c7, fontFamily: "brands");
  static const IconData flutter = IconData(0xe9cc, fontFamily: "brands");
  static const IconData garmin = IconData(0xe9d4, fontFamily: "brands");
  static const IconData strava = IconData(0xeb20, fontFamily: "brands");
}
