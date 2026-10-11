/// Compass on platforms that are not the web: nothing to do here (see web_compass_web.dart).
Future<bool> webCompassAvailable() async => false;

Stream<double> webCompassStream() => const Stream<double>.empty();

Future<void> webCompassStart() async {}
