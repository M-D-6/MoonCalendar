import 'dart:math' as math;

/// Minimal Open Location Code (Plus Code) encoder, matching what the Android
/// app's GPS dialog shows through `OpenLocationCode.encode`.
class OpenLocationCode {
  OpenLocationCode._();

  static const String _alphabet = '23456789CFGHJMPQRVWX';
  static const int _pairLength = 10;
  static const int _gridRows = 5;
  static const int _gridCols = 4;
  static const int _separatorPosition = 8;
  static const int _latMax = 90;
  static const int _lngMax = 180;
  // 8000 * 5^5 and 8000 * 4^5, the finest precision the algorithm uses.
  static const int _finalLatPrecision = 25000000;
  static const int _finalLngPrecision = 8192000;

  static String encode(double latitude, double longitude, {int codeLength = 10}) {
    var length = codeLength < 2 ? 2 : codeLength;
    if (length < _pairLength && length.isOdd) length++;
    if (length > 15) length = 15;

    var lat = latitude.clamp(-90.0, 90.0).toDouble();
    var lng = longitude;
    while (lng < -_lngMax) {
      lng += 360;
    }
    while (lng >= _lngMax) {
      lng -= 360;
    }
    if (lat >= _latMax) {
      lat -= _latPrecision(length);
    }

    var latVal = ((lat + _latMax) * _finalLatPrecision * 1e6).round() ~/ 1000000;
    var lngVal = ((lng + _lngMax) * _finalLngPrecision * 1e6).round() ~/ 1000000;
    if (latVal < 0) latVal = 0;
    if (lngVal < 0) lngVal = 0;

    final out = <String>[];
    if (length > _pairLength) {
      for (var i = 0; i < 5; i++) {
        final latDigit = latVal % _gridRows;
        final lngDigit = lngVal % _gridCols;
        out.insert(0, _alphabet[latDigit * _gridCols + lngDigit]);
        latVal ~/= _gridRows;
        lngVal ~/= _gridCols;
      }
    } else {
      latVal ~/= math.pow(_gridRows, 5).toInt();
      lngVal ~/= math.pow(_gridCols, 5).toInt();
    }
    for (var i = 0; i < 5; i++) {
      out.insert(0, _alphabet[lngVal % 20]);
      out.insert(0, _alphabet[latVal % 20]);
      latVal ~/= 20;
      lngVal ~/= 20;
    }

    var code = out.join();
    if (length < _separatorPosition) {
      code = '${code.substring(0, length)}${''.padRight(_separatorPosition - length, '0')}+';
    } else {
      code = '${code.substring(0, _separatorPosition)}+${code.substring(_separatorPosition, length)}';
    }
    return code;
  }

  static double _latPrecision(int length) {
    if (length <= _pairLength) {
      return math.pow(20, (length ~/ -2) + 2).toDouble();
    }
    return math.pow(20, -3) / math.pow(_gridRows, length - _pairLength);
  }
}
