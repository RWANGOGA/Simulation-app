typedef BodyPartTap = ({
  String part,
  double? x,
  double? y,
  String? partName,
  double? hitX,
  double? hitY,
  double? hitZ,
});
typedef BodyPartCallback = void Function(BodyPartTap tap);

class WebInterop {
  static void registerBodyPartListener(BodyPartCallback onBodyPart) {}
  static void unregisterBodyPartListener(BodyPartCallback onBodyPart) {}
  static void applyCameraOrbit(String elementId, String orbit) {}
  static void postToIframe(Object? iframe, Map<String, Object?> message) {}
}
