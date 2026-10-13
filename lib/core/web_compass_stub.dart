/// Compass on platforms that are not the web: nothing to do here (see web_compass_web.dart).
Future<bool> webCompassAvailable() async => false;

Stream<double> webCompassStream() => const Stream<double>.empty();

Future<void> webCompassStart() async {}

Future<bool> webLevelAvailable() async => false;

Stream<(double, double, double)> webGravityStream() => const Stream<(double, double, double)>.empty();

void webCloseWindow() {}
