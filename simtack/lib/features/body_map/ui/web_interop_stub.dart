typedef BodyPartCallback = void Function(String part, double? x, double? y);

class WebInterop {
  static void registerBodyPartListener(BodyPartCallback onBodyPart) {}
  static void unregisterBodyPartListener(BodyPartCallback onBodyPart) {}
  static void applyCameraOrbit(String elementId, String orbit) {}
}
