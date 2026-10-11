// Port of Android Open Source Project's GeomagneticField (WMM-2020).
//
// Copyright (C) 2009 The Android Open Source Project
// Licensed under the Apache License, Version 2.0.
// See https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/core/java/android/hardware/GeomagneticField.java
//
// The implementation intentionally follows Android's GeomagneticField.java so
// that Flutter's magnetic map layers use the same WMM-2020 coefficients and
// equations as the Android Persian Calendar application.

import 'dart:math' as math;

class AospGeomagneticField {
  static const double _earthSemiMajorAxisKm = 6378.137;
  static const double _earthSemiMinorAxisKm = 6356.7523142;
  static const double _earthReferenceRadiusKm = 6371.2;
  static const int _maxN = 13;
  static final int _baseTime = DateTime.utc(2020, 1, 1).millisecondsSinceEpoch;
  static final List<List<double>> _schmidtFactors = _schmidtQuasiNormFactors(_maxN);

  static const List<List<double>> _gCoeff = [
    [0.0],
    [-29404.5, -1450.7],
    [-2500.0, 2982.0, 1676.8],
    [1363.9, -2381.0, 1236.2, 525.7],
    [903.1, 809.4, 86.2, -309.4, 47.9],
    [-234.4, 363.1, 187.8, -140.7, -151.2, 13.7],
    [65.9, 65.6, 73.0, -121.5, -36.2, 13.5, -64.7],
    [80.6, -76.8, -8.3, 56.5, 15.8, 6.4, -7.2, 9.8],
    [23.6, 9.8, -17.5, -0.4, -21.1, 15.3, 13.7, -16.5, -0.3],
    [5.0, 8.2, 2.9, -1.4, -1.1, -13.3, 1.1, 8.9, -9.3, -11.9],
    [-1.9, -6.2, -0.1, 1.7, -0.9, 0.6, -0.9, 1.9, 1.4, -2.4, -3.9],
    [3.0, -1.4, -2.5, 2.4, -0.9, 0.3, -0.7, -0.1, 1.4, -0.6, 0.2, 3.1],
    [-2.0, -0.1, 0.5, 1.3, -1.2, 0.7, 0.3, 0.5, -0.2, -0.5, 0.1, -1.1, -0.3],
  ];

  static const List<List<double>> _hCoeff = [
    [0.0],
    [0.0, 4652.9],
    [0.0, -2991.6, -734.8],
    [0.0, -82.2, 241.8, -542.9],
    [0.0, 282.0, -158.4, 199.8, -350.1],
    [0.0, 47.7, 208.4, -121.3, 32.2, 99.1],
    [0.0, -19.1, 25.0, 52.7, -64.4, 9.0, 68.1],
    [0.0, -51.4, -16.8, 2.3, 23.5, -2.2, -27.2, -1.9],
    [0.0, 8.4, -15.3, 12.8, -11.8, 14.9, 3.6, -6.9, 2.8],
    [0.0, -23.3, 11.1, 9.8, -5.1, -6.2, 7.8, 0.4, -1.5, 9.7],
    [0.0, 3.4, -0.2, 3.5, 4.8, -8.6, -0.1, -4.2, -3.4, -0.1, -8.8],
    [0.0, 0.0, 2.6, -0.5, -0.4, 0.6, -0.2, -1.7, -1.6, -3.0, -2.0, -2.6],
    [0.0, -1.2, 0.5, 1.3, -1.8, 0.1, 0.7, -0.1, 0.6, 0.2, -0.9, 0.0, 0.5],
  ];

  static const List<List<double>> _deltaGCoeff = [
    [0.0],
    [6.7, 7.7],
    [-11.5, -7.1, -2.2],
    [2.8, -6.2, 3.4, -12.2],
    [-1.1, -1.6, -6.0, 5.4, -5.5],
    [-0.3, 0.6, -0.7, 0.1, 1.2, 1.0],
    [-0.6, -0.4, 0.5, 1.4, -1.4, 0.0, 0.8],
    [-0.1, -0.3, -0.1, 0.7, 0.2, -0.5, -0.8, 1.0],
    [-0.1, 0.1, -0.1, 0.5, -0.1, 0.4, 0.5, 0.0, 0.4],
    [-0.1, -0.2, 0.0, 0.4, -0.3, 0.0, 0.3, 0.0, 0.0, -0.4],
    [0.0, 0.0, 0.0, 0.2, -0.1, -0.2, 0.0, -0.1, -0.2, -0.1, 0.0],
    [0.0, -0.1, 0.0, 0.0, 0.0, -0.1, 0.0, 0.0, -0.1, -0.1, -0.1, -0.1],
    [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, -0.1],
  ];

  static const List<List<double>> _deltaHCoeff = [
    [0.0],
    [0.0, -25.1],
    [0.0, -30.2, -23.9],
    [0.0, 5.7, -1.0, 1.1],
    [0.0, 0.2, 6.9, 3.7, -5.6],
    [0.0, 0.1, 2.5, -0.9, 3.0, 0.5],
    [0.0, 0.1, -1.8, -1.4, 0.9, 0.1, 1.0],
    [0.0, 0.5, 0.6, -0.7, -0.2, -1.2, 0.2, 0.3],
    [0.0, -0.3, 0.7, -0.2, 0.5, -0.3, -0.5, 0.4, 0.1],
    [0.0, -0.3, 0.2, -0.4, 0.4, 0.1, 0.0, -0.2, 0.5, 0.2],
    [0.0, 0.0, 0.1, -0.3, 0.1, -0.2, 0.1, 0.0, -0.1, 0.2, 0.0],
    [0.0, 0.0, 0.1, 0.0, 0.2, 0.0, 0.0, 0.1, 0.0, -0.1, 0.0, 0.0],
    [0.0, 0.0, 0.0, -0.1, 0.1, 0.0, 0.0, 0.0, 0.1, 0.0, 0.0, 0.0, -0.1],
  ];

  final double x;
  final double y;
  final double z;
  final double declination;
  final double inclination;
  final double horizontalStrength;
  final double fieldStrength;

  AospGeomagneticField._(this.x, this.y, this.z)
      : declination = math.atan2(y, x) * 180 / math.pi,
        horizontalStrength = math.sqrt(x * x + y * y),
        inclination = math.atan2(z, math.sqrt(x * x + y * y)) * 180 / math.pi,
        fieldStrength = math.sqrt(x * x + y * y + z * z);

  factory AospGeomagneticField({
    required double latitudeDeg,
    required double longitudeDeg,
    double altitudeMeters = 0,
    required int timeMillis,
  }) {
    var gdLatitudeDeg = latitudeDeg.clamp(-90.0 + 1e-5, 90.0 - 1e-5).toDouble();
    final coords = _geocentric(gdLatitudeDeg, longitudeDeg, altitudeMeters);
    final legendre = _LegendreTable(
      _maxN - 1,
      math.pi / 2 - coords.gcLatitudeRad,
    );

    final relativeRadiusPower = List<double>.filled(_maxN + 2, 0);
    relativeRadiusPower[0] = 1;
    relativeRadiusPower[1] = _earthReferenceRadiusKm / coords.gcRadiusKm;
    for (var i = 2; i < relativeRadiusPower.length; i++) {
      relativeRadiusPower[i] = relativeRadiusPower[i - 1] * relativeRadiusPower[1];
    }

    final sinMLon = List<double>.filled(_maxN, 0);
    final cosMLon = List<double>.filled(_maxN, 0);
    sinMLon[0] = 0;
    cosMLon[0] = 1;
    sinMLon[1] = math.sin(coords.gcLongitudeRad);
    cosMLon[1] = math.cos(coords.gcLongitudeRad);
    for (var m = 2; m < _maxN; m++) {
      final xIndex = m >> 1;
      sinMLon[m] = sinMLon[m - xIndex] * cosMLon[xIndex] + cosMLon[m - xIndex] * sinMLon[xIndex];
      cosMLon[m] = cosMLon[m - xIndex] * cosMLon[xIndex] - sinMLon[m - xIndex] * sinMLon[xIndex];
    }

    final inverseCosLatitude = 1 / math.cos(coords.gcLatitudeRad);
    final yearsSinceBase = (timeMillis - _baseTime) / (365 * 24 * 60 * 60 * 1000);
    var gcX = 0.0;
    var gcY = 0.0;
    var gcZ = 0.0;
    final factors = _schmidtFactors;

    for (var n = 1; n < _maxN; n++) {
      for (var m = 0; m <= n; m++) {
        final g = _gCoeff[n][m] + yearsSinceBase * _deltaGCoeff[n][m];
        final h = _hCoeff[n][m] + yearsSinceBase * _deltaHCoeff[n][m];
        final term = g * cosMLon[m] + h * sinMLon[m];
        gcX += relativeRadiusPower[n + 2] * term * legendre.pDeriv[n][m] * factors[n][m];
        gcY += relativeRadiusPower[n + 2] * m * (g * sinMLon[m] - h * cosMLon[m]) * legendre.p[n][m] * factors[n][m] * inverseCosLatitude;
        gcZ -= (n + 1) * relativeRadiusPower[n + 2] * term * legendre.p[n][m] * factors[n][m];
      }
    }

    final latDiffRad = gdLatitudeDeg * math.pi / 180 - coords.gcLatitudeRad;
    final x = gcX * math.cos(latDiffRad) + gcZ * math.sin(latDiffRad);
    final y = gcY;
    final z = -gcX * math.sin(latDiffRad) + gcZ * math.cos(latDiffRad);
    return AospGeomagneticField._(x, y, z);
  }

  static _GeoCoordinates _geocentric(double gdLatitudeDeg, double gdLongitudeDeg, double altitudeMeters) {
    final altitudeKm = altitudeMeters / 1000;
    final a2 = _earthSemiMajorAxisKm * _earthSemiMajorAxisKm;
    final b2 = _earthSemiMinorAxisKm * _earthSemiMinorAxisKm;
    final gdLatRad = gdLatitudeDeg * math.pi / 180;
    final clat = math.cos(gdLatRad);
    final slat = math.sin(gdLatRad);
    final tlat = slat / clat;
    final latRad = math.sqrt(a2 * clat * clat + b2 * slat * slat);
    final gcLat = math.atan(tlat * (latRad * altitudeKm + b2) / (latRad * altitudeKm + a2));
    final gcLon = gdLongitudeDeg * math.pi / 180;
    final radSq = altitudeKm * altitudeKm +
        2 * altitudeKm * math.sqrt(a2 * clat * clat + b2 * slat * slat) +
        (a2 * a2 * clat * clat + b2 * b2 * slat * slat) /
            (a2 * clat * clat + b2 * slat * slat);
    return _GeoCoordinates(gcLat, gcLon, math.sqrt(radSq));
  }

  static List<List<double>> _schmidtQuasiNormFactors(int maxN) {
    final out = List<List<double>>.generate(maxN + 1, (n) => List<double>.filled(n + 1, 0));
    out[0][0] = 1;
    for (var n = 1; n <= maxN; n++) {
      out[n][0] = out[n - 1][0] * (2 * n - 1) / n;
      for (var m = 1; m <= n; m++) {
        out[n][m] = out[n][m - 1] * math.sqrt((n - m + 1) * (m == 1 ? 2 : 1) / (n + m));
      }
    }
    return out;
  }
}

class _GeoCoordinates {
  final double gcLatitudeRad;
  final double gcLongitudeRad;
  final double gcRadiusKm;
  const _GeoCoordinates(this.gcLatitudeRad, this.gcLongitudeRad, this.gcRadiusKm);
}

class _LegendreTable {
  final List<List<double>> p;
  final List<List<double>> pDeriv;

  _LegendreTable(int maxN, double thetaRad)
      : p = List<List<double>>.generate(maxN + 1, (n) => List<double>.filled(n + 1, 0)),
        pDeriv = List<List<double>>.generate(maxN + 1, (n) => List<double>.filled(n + 1, 0)) {
    final cosValue = math.cos(thetaRad);
    final sinValue = math.sin(thetaRad);
    p[0][0] = 1;
    pDeriv[0][0] = 0;
    for (var n = 1; n <= maxN; n++) {
      for (var m = 0; m <= n; m++) {
        if (n == m) {
          p[n][m] = sinValue * p[n - 1][m - 1];
          pDeriv[n][m] = cosValue * p[n - 1][m - 1] + sinValue * pDeriv[n - 1][m - 1];
        } else if (n == 1 || m == n - 1) {
          p[n][m] = cosValue * p[n - 1][m];
          pDeriv[n][m] = -sinValue * p[n - 1][m] + cosValue * pDeriv[n - 1][m];
        } else {
          final k = ((n - 1) * (n - 1) - m * m) / ((2 * n - 1) * (2 * n - 3));
          p[n][m] = cosValue * p[n - 1][m] - k * p[n - 2][m];
          pDeriv[n][m] = -sinValue * p[n - 1][m] + cosValue * pDeriv[n - 1][m] - k * pDeriv[n - 2][m];
        }
      }
    }
  }
}
