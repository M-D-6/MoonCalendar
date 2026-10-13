import 'dart:async';
import 'dart:js_interop';
import 'dart:math' as math;

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
  external void close();
}

extension type _OrientationEvent._(JSObject _) implements JSObject {
  external double? get alpha;
  external double? get beta;
  external double? get gamma;
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

@JS('navigator.userAgent')
external String get _userAgent;

@JS('navigator.maxTouchPoints')
external int get _touchPoints;

bool get _isIos => _userAgent.contains('iPhone') || _userAgent.contains('iPad') || (_userAgent.contains('Macintosh') && _touchPoints > 1);

/// Waits briefly for events that carry real sensor data ([hasData]). A real sensor reports continuously;
/// devices without the sensors (desktop browsers) fire one empty event or none, so a single event is not
/// enough to call the sensor available.
Future<bool> _probe(String eventName, bool Function(_OrientationEvent) hasData) async {
  if (_window.DeviceOrientationEvent == null) return false;
  // iOS only reports after the permission was granted, so its presence is taken as available.
  if (_isIos && _hasRequestPermission) return true;
  var count = 0;
  final found = Completer<bool>();
  final JSFunction listener = ((JSObject raw) {
    if (found.isCompleted) return;
    // The first event of a device without the sensor is empty: answer quickly instead of waiting.
    if (!hasData(raw as _OrientationEvent)) {
      // A real sensor may report an empty event while it warms up, so give it a moment to follow up.
      Timer(const Duration(milliseconds: 250), () {
        if (!found.isCompleted) found.complete(false);
      });
    } else if (++count >= 3) {
      found.complete(true);
    }
  }).toJS;
  _window.addEventListener(eventName, listener);
  final ok = await found.future.timeout(const Duration(milliseconds: 700), onTimeout: () => false);
  _window.removeEventListener(eventName, listener);
  return ok;
}

Future<bool> webCompassAvailable() => _probe(_absoluteEvent, (e) => _headingOf(e) != null);

Future<bool> webLevelAvailable() => _probe(_relativeEvent, (e) {
      final beta = e.beta, gamma = e.gamma;
      return beta != null && gamma != null && beta.isFinite && gamma.isFinite;
    });

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

/// Direction of gravity in device coordinates (x right, y up, z out of the screen), from beta / gamma.
final StreamController<(double, double, double)> _gravityController = StreamController<(double, double, double)>.broadcast(
  onListen: () {
    final listener = ((JSObject raw) {
      final e = raw as _OrientationEvent;
      final beta = e.beta, gamma = e.gamma;
      if (beta == null || gamma == null || _gravityController.isClosed) return;
      final b = beta * math.pi / 180, g = gamma * math.pi / 180;
      _gravityController.add((-math.cos(b) * math.sin(g), math.sin(b), math.cos(b) * math.cos(g)));
    }).toJS;
    _gravityListener = listener;
    _window.addEventListener(_relativeEvent, listener);
  },
  onCancel: () {
    final listener = _gravityListener;
    if (listener == null) return;
    _window.removeEventListener(_relativeEvent, listener);
    _gravityListener = null;
  },
);

JSFunction? _gravityListener;

Stream<(double, double, double)> webGravityStream() => _gravityController.stream;

/// Closes the tab/window (browsers only allow this for pages opened by script; otherwise it is a no-op).
void webCloseWindow() {
  try {
    _window.close();
  } catch (_) {}
}
