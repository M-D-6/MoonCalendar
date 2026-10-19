import 'package:flutter_test/flutter_test.dart';
import 'package:mooncalendar/core/update_service.dart';

void main() {
  group('UpdateService.compareVersions', () {
    test('compares numeric components rather than strings', () {
      expect(UpdateService.compareVersions('1.1.10', '1.1.9'), 1);
      expect(UpdateService.compareVersions('1.2.0', '1.11.0'), -1);
    });

    test('ignores a leading v and Android build metadata', () {
      expect(UpdateService.compareVersions('v1.1.7', '1.1.7'), 0);
      expect(UpdateService.compareVersions('1.1.7+12', '1.1.7'), 0);
      expect(UpdateService.compareVersions('V1.1.8+2', 'v1.1.7+99'), 1);
    });

    test('orders pre-release tags below stable releases', () {
      expect(UpdateService.compareVersions('1.1.7-rc.2', '1.1.7'), -1);
      expect(UpdateService.compareVersions('1.1.7-alpha.10', '1.1.7-alpha.2'), 1);
      expect(UpdateService.compareVersions('1.1.7-beta', '1.1.7-alpha'), 1);
    });

    test('treats omitted trailing zero components as equal', () {
      expect(UpdateService.compareVersions('1.1', '1.1.0'), 0);
    });
  });
}
