import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Browser notification + audio for the athan while the site is open.
/// Notifications need a secure (https) page and the user's permission, which can only be requested
/// from a user gesture (a click in the settings).

extension type _Notification._(JSObject _) implements JSObject {
  external factory _Notification(String title, JSObject options);
  external static String get permission;
  external static JSPromise<JSString> requestPermission();
  external void close();
}

extension type _Audio._(JSObject _) implements JSObject {
  external factory _Audio(String src);
  external JSPromise<JSAny?> play();
  external void pause();
  external set currentTime(num value);
}

_Audio? _audio;
_Notification? _lastNotification;

bool get _supported =>
    globalContext.getProperty<JSAny?>('Notification'.toJS) != null;

Future<bool> webNotifyRequestPermission() async {
  if (!_supported) return false;
  try {
    if (_Notification.permission == 'granted') return true;
    if (_Notification.permission == 'denied') return false;
    final result = (await _Notification.requestPermission().toDart).toDart;
    return result == 'granted';
  } catch (_) {
    return false;
  }
}

void webNotifyShow(String title, String body) {
  if (!_supported) return;
  try {
    if (_Notification.permission != 'granted') return;
    _lastNotification?.close();
    final options = JSObject()
      ..setProperty('body'.toJS, body.toJS)
      ..setProperty('tag'.toJS, 'mooncalendar-athan'.toJS)
      ..setProperty('dir'.toJS, 'auto'.toJS);
    _lastNotification = _Notification(title, options);
  } catch (_) {}
}

void webAudioPlay(String url) {
  try {
    webAudioStop();
    final audio = _Audio(url);
    _audio = audio;
    // Autoplay can be refused until the user has interacted with the page; the notification still shows.
    audio.play().toDart.catchError((Object _) => null);
  } catch (_) {}
}

void webAudioStop() {
  try {
    _audio?.pause();
    _audio = null;
  } catch (_) {}
}

extension type _EventTarget._(JSObject _) implements JSObject {
  external void addEventListener(String type, JSFunction listener);
}

@JS('window')
external _EventTarget get _win;

@JS('document')
external _Document get _doc;

extension type _Document._(JSObject _) implements _EventTarget {
  external bool get hidden;
  external bool hasFocus();
}

/// True while the page is visible AND focused. Switching to another window or tab turns it false, so
/// the ambient animations can stop (the browser keeps running them while the window is merely unfocused).
Stream<bool> webActivity() {
  late StreamController<bool> controller;
  controller = StreamController<bool>.broadcast(
    onListen: () {
      void report() {
        if (!controller.isClosed) controller.add(!_doc.hidden && _doc.hasFocus());
      }
      final listener = ((JSAny? _) => report()).toJS;
      _win.addEventListener('focus', listener);
      _win.addEventListener('blur', listener);
      _doc.addEventListener('visibilitychange', listener);
    },
  );
  return controller.stream;
}
