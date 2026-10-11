import 'dart:async';
import 'dart:js_interop';

/// Compass for the web build, from the browser's device-orientation events.
///
/// * Android browsers: `deviceorientationabsolute` (alpha is counter-clockwise from north).
/// * iOS Safari: `webkitCompassHeading` (clockwise from north); the permission prompt can only be shown
///   from a user gesture, so it is requested when the compass screen starts listening.
/// Browsers only expose these events on secure (https) pages and on devices that have the sensors.

@JS('window')
external _Window get _window;

extension type _Window._(JSObject _) implements JSObject {
  external void addEventListener(String type, JSFunction listener);
  external void removeEventListener(String type, JSFunction listener);
  external JSAny? get DeviceOrientationEvent;
}

extension type _OrientationEvent._(JSObject _) implements JSObject {
  external double? get alpha;
  external bool? get absolute;
  external double? get webkitCompassHeading;
}

extension type _OrientationEventClass._(JSObject _) implements JSObject {
  external JSPromise<JSString> requestPermission();
}

const String _absoluteEvent = 'deviceorientationabsolute';
const String _relativeEvent = 'deviceorientation';

/// Clockwise degrees from north, or null when the event carries no compass information.
double? _headingOf(_OrientationEvent e) {
  final ios = e.webkitCompassHeading;
  if (ios != null) return ios;
  final alpha = e.alpha;
  if (e.absolute == true && alpha != null) return (360 - alpha) % 360;
  return null;
}

bool get _hasRequestPermission {
  final cls = _window.DeviceOrientationEvent;
  return cls != null && (cls as JSObject).has('requestPermission');
}

extension on JSObject {
  bool has(String name) => _hasProperty(this, name.toJS).toDart;
}

@JS('Reflect.has')
external JSBoolean _hasProperty(JSObject target, JSString name);

Future<bool> webCompassAvailable() async {
  if (_window.DeviceOrientationEvent == null) return false;
  // iOS only reports after the permission was granted, so its presence is taken as available.
  if (_hasRequestPermission) return true;
  // Elsewhere a device without the sensors fires one event without data (or none): wait briefly for a real one.
  final found = Completer<bool>();
  final JSFunction listener = ((JSObject raw) {
    if (_headingOf(raw as _OrientationEvent) != null && !found.isCompleted) found.complete(true);
  }).toJS;
  _window.addEventListener(_absoluteEvent, listener);
  final ok = await found.future.timeout(const Duration(milliseconds: 1500), onTimeout: () => false);
  _window.removeEventListener(_absoluteEvent, listener);
  return ok;
}

JSFunction? _listener;
double? _smoothed;

final StreamController<double> _controller = StreamController<double>.broadcast(
  onListen: () {
    _smoothed = null;
    final listener = ((JSObject raw) {
      final heading = _headingOf(raw as _OrientationEvent);
      if (heading == null || _controller.isClosed) return;
      final previous = _smoothed;
      if (previous == null) {
        _smoothed = heading;
      } else {
        final delta = ((heading - previous + 540) % 360) - 180;
        _smoothed = (previous + 0.25 * delta + 360) % 360;
      }
      _controller.add(_smoothed!);
    }).toJS;
    _listener = listener;
    _window.addEventListener(_absoluteEvent, listener);
    _window.addEventListener(_relativeEvent, listener);
  },
  onCancel: () {
    final listener = _listener;
    if (listener == null) return;
    _window.removeEventListener(_absoluteEvent, listener);
    _window.removeEventListener(_relativeEvent, listener);
    _listener = null;
  },
);

Stream<double> webCompassStream() => _controller.stream;

/// Asks iOS for permission to read the sensors (a no-op elsewhere).
Future<void> webCompassStart() async {
  try {
    if (!_hasRequestPermission) return;
    final cls = _window.DeviceOrientationEvent as _OrientationEventClass;
    await cls.requestPermission().toDart;
  } catch (_) {}
}
