/// Web notifications and audio on platforms that are not the web: nothing to do (see web_notify_web.dart).
Future<bool> webNotifyRequestPermission() async => false;

void webNotifyShow(String title, String body) {}

void webAudioPlay(String url) {}

void webAudioStop() {}

/// Whether the page is in the foreground (focused and visible). Always true outside the web.
Stream<bool> webActivity() => const Stream<bool>.empty();
