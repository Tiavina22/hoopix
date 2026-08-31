/// Spacing steps on a 4pt grid, and the corner radii the app is allowed to
/// use. Keeping these named stops layouts from drifting into arbitrary
/// one-off paddings, which is what makes an interface feel loose.
abstract final class HoopixSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const xxxl = 32.0;
}

abstract final class HoopixRadius {
  static const sm = 6.0;
  static const md = 10.0;
  static const lg = 14.0;
  static const pill = 999.0;
}

/// Fixed layout dimensions shared by the shell.
abstract final class HoopixLayout {
  static const sidebarWidth = 216.0;

  /// Clears the macOS traffic lights, which float over our own chrome
  /// because the window uses a transparent full-size-content title bar.
  static const trafficLightInset = 38.0;
}
