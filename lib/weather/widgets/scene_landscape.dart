import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/material.dart';

import '../../core/platform_info.dart';
import 'scene_light.dart' show LandscapeLight, Seasons, windAmplitude;

/// The illustrated landscape of the live scene, drawn entirely with code.
///
/// `assets/weather/scene_vec.json` holds the picture as ~1200 filled vector shapes (traced from the
/// reference illustration with tools/vectorize, sub-pixel accurate, with linear gradients).
/// Every shape knows what it is (mountain, hill, bush, tree crown, river, cabin, window ...).
/// Nothing is a bitmap, so nothing is a "statue": the wind bends the tree crown, branches, bushes,
/// pines, grass and flowers vertex by vertex, and the river ripples and flows.
/// the windows glow at night. Seasons recolour the shapes (autumn leaves, snow, bare branches,
/// ice on the river ...). The sky itself is cut out so the live sky shows through.

/// Shape kinds (order of `kinds` in scene_vec.json).
class _K {
  static const mtn = 0, grass = 1, foliage = 2, canopy = 3, bush = 4, trunk = 5, wood = 6, path = 7, rock = 8, water = 9, roof = 11, win = 13, flower = 16;
}

class _Region {
  _Region(this.p, this.color, this.kind, this.grad, this.group, this.idx, [this.ell]) {
    var minX = 1e9, maxX = -1e9, minY = 1e9, maxY = -1e9, a = 0.0;
    final n = p.length ~/ 2;
    final e = ell;
    if (e != null) {
      // a union of ellipses: cx, cy, rx, ry
      var sum = 0.0;
      for (var i = 0; i + 3 < e.length; i += 4) {
        minX = math.min(minX, e[i] - e[i + 2]);
        maxX = math.max(maxX, e[i] + e[i + 2]);
        minY = math.min(minY, e[i + 1] - e[i + 3]);
        maxY = math.max(maxY, e[i + 1] + e[i + 3]);
        sum += math.pi * e[i + 2] * e[i + 3];
      }
      area = sum * 0.7;
      cx = (minX + maxX) / 2;
      cy = (minY + maxY) / 2;
      return;
    }
    for (var i = 0; i < n; i++) {
      final x = p[i * 2], y = p[i * 2 + 1];
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
      final j = (i + 1) % n;
      a += x * p[j * 2 + 1] - p[j * 2] * y;
    }
    area = a.abs() / 2;
    cx = (minX + maxX) / 2;
    cy = (minY + maxY) / 2;
  }

  final Float32List p;

  /// Optional union of ellipses (cx, cy, rx, ry ...) instead of an outline.
  final Float32List? ell;
  final int color;
  final int kind;
  final List<double>? grad; // ax, ay, bx, by, c0, c1
  final int group;
  final int idx;
  /// Highest point of the shape (mountains are told from the lake by it).
  late final double topY = _minY();
  double _minY() {
    var m = 1e9;
    final e = ell;
    if (e != null) {
      for (var i = 1; i < e.length; i += 4) {
        m = math.min(m, e[i] - e[i + 2]);
      }
    } else {
      for (var i = 1; i < p.length; i += 2) {
        m = math.min(m, p[i].toDouble());
      }
    }
    return m;
  }

  double area = 0;
  double cx = 0;
  double cy = 0;

  /// Moves in the wind / water (decided once, see SceneData).
  bool anim = false;
  late final Path staticPath = _toPath(null);

  /// Where the shape can ever be drawn (including its movement); bounds an offscreen layer instead of the whole canvas.
  late final Rect layerBounds = _outline();

  Rect _outline() {
    var box = ell == null ? staticPath.getBounds() : Rect.fromLTRB(0, 0, 0, 0);
    final e = ell;
    if (e != null && e.length >= 4) {
      var l = 1e9, t = 1e9, rr = -1e9, b = -1e9;
      for (var i = 0; i + 3 < e.length; i += 4) {
        l = math.min(l, e[i] - e[i + 2]);
        rr = math.max(rr, e[i] + e[i + 2]);
        t = math.min(t, e[i + 1] - e[i + 3]);
        b = math.max(b, e[i + 1] + e[i + 3]);
      }
      box = Rect.fromLTRB(l, t, rr, b);
    }
    return box.inflate(80);
  }

  /// A smooth closed curve through the shape's points (quadratic curves between the mid points;
  /// corner points are stored twice so they stay sharp).
  // Scratch buffers and a path reused for every animated frame, so moving shapes allocate nothing per frame.
  Float64List? _xs;
  Float64List? _ys;
  Path? _live;

  Path _toPath(_Disp? d) {
    final n = p.length ~/ 2;
    final xs = _xs ??= Float64List(n);
    final ys = _ys ??= Float64List(n);
    for (var i = 0; i < n; i++) {
      var x = p[i * 2], y = p[i * 2 + 1];
      if (d != null) {
        final o = d(this, x, y);
        x += o.dx;
        y += o.dy;
      }
      xs[i] = x;
      ys[i] = y;
    }
    final Path path;
    if (d == null) {
      path = Path();
    } else {
      path = _live ??= Path();
      path.reset();
    }
    if (n < 3) return path;
    path.moveTo((xs[n - 1] + xs[0]) / 2, (ys[n - 1] + ys[0]) / 2);
    for (var i = 0; i < n; i++) {
      final j = (i + 1) % n;
      path.quadraticBezierTo(xs[i], ys[i], (xs[i] + xs[j]) / 2, (ys[i] + ys[j]) / 2);
    }
    path.close();
    return path;
  }

  Path livePath(_Disp d) => _toPath(d);

  /// Fills the shape (outline or ellipses) with [paint]; [d] moves the points in the wind.
  void draw(Canvas canvas, Paint paint, _Disp? d) {
    final e = ell;
    if (e == null) {
      canvas.drawPath(d == null ? staticPath : _toPath(d), paint);
      return;
    }
    for (var i = 0; i + 3 < e.length; i += 4) {
      var x = e[i], y = e[i + 1];
      if (d != null) {
        final o = d(this, x, y);
        x += o.dx;
        y += o.dy;
      }
      canvas.drawOval(Rect.fromCenter(center: Offset(x, y), width: e[i + 2] * 2, height: e[i + 3] * 2), paint);
    }
  }
}

typedef _Disp = Offset Function(_Region r, double x, double y);

class _Group {
  _Group(this.cx, this.piv, this.h, this.w, this.y0, this.kind, int i)
      : phase = _hash(i * 17 + 3) * 6.28,
        speed = 0.8 + _hash(i * 5 + 1) * 0.5 {
    if (kind == 'canopy') {
      amp = 24.0;
      speed = 0.85;
    } else if (kind == 'flower') {
      amp = 10.0;
    } else {
      amp = (2.0 + h * 0.09).clamp(2.0, 12.0).toDouble();
    }
    conifer = kind == 'foliage' && h > 70 && w < h * 1.1;
  }
  final double cx, piv, h, w, y0;
  final String kind;
  final double phase;
  double speed;
  double amp = 1;
  bool conifer = false;
}

/// Everything parsed from scene_vec.json.
class SceneData {
  SceneData._(this.regions, this.groups, this.waterPath, this.rippleClip, this.twigs, this.blossoms, this.blades, this.chimney, this.canopyGroup, this.waterHook, this.animalHook, this.hill);

  // ignore: library_private_types_in_public_api
  final List<_Region> regions;
  // ignore: library_private_types_in_public_api
  final List<_Group> groups;
  final Path waterPath;

  /// The river without the bridge, rocks and anything wooden standing in it: ripples stay inside.
  final Path rippleClip;
  final List<List<double>> twigs;
  final List<Offset> blossoms;
  final List<List<double>> blades;
  final Offset chimney;
  final int canopyGroup;

  /// Index of the last big river shape: ripples are painted right after it (under the bridge, banks and rocks).
  final int waterHook;

  /// Region after which the far animals are painted (the far meadow) and the meadow's ridge line (x, y, x, y ...).
  final int animalHook;
  final List<double> hill;

  static SceneData parse(String text) {
    final m = jsonDecode(text) as Map<String, dynamic>;
    final gl = <_Group>[];
    final gs = m['groups'] as List<dynamic>;
    for (var i = 0; i < gs.length; i++) {
      final g = gs[i] as Map<String, dynamic>;
      gl.add(_Group((g['cx'] as num).toDouble(), (g['piv'] as num).toDouble(), (g['h'] as num).toDouble(), (g['w'] as num).toDouble(), (g['y0'] as num).toDouble(), g['k'] as String, i));
    }
    final rs = <_Region>[];
    final rl = m['regions'] as List<dynamic>;
    var hook = 0;
    for (var i = 0; i < rl.length; i++) {
      final r = rl[i] as Map<String, dynamic>;
      final raw = (r['p'] ?? <dynamic>[]) as List<dynamic>;
      final pts = Float32List(raw.length);
      for (var j = 0; j < raw.length; j++) {
        pts[j] = (raw[j] as num) / 10.0;
      }
      Float32List? ell;
      final ci = r['ci'] as List<dynamic>?;
      if (ci != null) {
        ell = Float32List(ci.length);
        for (var j = 0; j < ci.length; j++) {
          ell[j] = (ci[j] as num) / 10.0;
        }
      }
      final g = r['g'] as List<dynamic>?;
      final reg = _Region(pts, r['c'] as int, r['k'] as int, g?.map((e) => (e as num).toDouble()).toList(), (r['gr'] as int?) ?? -1, i, ell);
      reg.anim = reg.group >= 0 || reg.kind == _K.trunk || (reg.kind == _K.water && reg.area < 9000);
      if (reg.kind == _K.water && reg.area >= 9000) hook = i;
      rs.add(reg);
    }
    final wp = Path();
    for (final c in m['water'] as List<dynamic>) {
      final l = (c as List<dynamic>).map((e) => (e as num).toDouble()).toList();
      for (var i = 0; i + 1 < l.length; i += 2) {
        if (i == 0) {
          wp.moveTo(l[i], l[i + 1]);
        } else {
          wp.lineTo(l[i], l[i + 1]);
        }
      }
      wp.close();
    }
    // Clip the ripples to the river only. The bridge, banks, wood and rocks are painted
    // later in scene order, so they naturally cover any ripple underneath them. Building a
    // boolean union of dozens of detailed vector paths here caused a large temporary native
    // allocation and a noticeable memory spike every time Weather was opened.
    final clip = wp;
    final tw = (m['twigs'] as List<dynamic>).map((s) => (s as List<dynamic>).map((e) => (e as num).toDouble()).toList()).toList();
    final bl = (m['blossoms'] as List<dynamic>).map((s) => Offset((s[0] as num).toDouble(), (s[1] as num).toDouble())).toList();
    final bd = (m['blades'] as List<dynamic>).map((s) => (s as List<dynamic>).map((e) => (e as num).toDouble()).toList()).toList();
    final ch = (m['chimney'] as List<dynamic>);
    final cg = gl.indexWhere((g) => g.kind == 'canopy');
    return SceneData._(rs, gl, wp, clip, tw, bl, bd, Offset((ch[0] as num).toDouble(), (ch[1] as num).toDouble()), cg, hook, (m['animalHook'] as num?)?.toInt() ?? -1, ((m['hill'] as List<dynamic>?) ?? <dynamic>[]).map((e) => (e as num).toDouble()).toList());
  }
}

/// Loads and caches the scene data.
class SceneAssets {
  SceneAssets._();

  static SceneData? data;
  static Future<void>? _loading;

  static bool get ready => data != null;

  static int _users = 0;

  /// A scene on screen asks for the artwork; the last one to leave frees it (it is several MB of paths and
  /// pictures, useless while the weather page is not open) and it is parsed again on the next visit.
  static void acquire() => _users++;

  /// Returns true when the last scene consumer has left.
  static bool release() {
    if (_users > 0) _users--;
    if (_users != 0) return false;
    data = null;
    _loading = null;
    ImageLandscapeRenderer.disposeCache();
    return true;
  }

  /// Safe to call many times; the data is parsed once.
  static Future<void> load() => _loading ??= _loadAll();

  static Future<void> _loadAll() async {
    try {
      final text = await rootBundle.loadString('assets/weather/scene_vec.json');
      data = SceneData.parse(text);
      if (_users == 0) data = null; // the page was left while this was loading
    } catch (_) {
      data = null;
    }
  }
}

/// How the 1774 x 887 artwork is placed on a screen: its bottom edge sits on the bottom of
/// the screen, the width is always covered, and on narrow (phone) screens the view is
/// centred on the bridge / cabin part of the picture.
class SceneFrame {
  const SceneFrame({required this.scale, required this.dx, required this.dy});

  static const double refWidth = 1774;
  static const double refHeight = 887;

  /// Reference x the narrow-screen crop is centred on: the middle of the cabin.
  static const double focusX = 1530;

  /// Reference y of the highest mountain top (the landscape band starts here).
  static const double bandTop = 366;

  /// Screen pixels per reference pixel.
  final double scale;

  /// Screen position of the reference origin.
  final double dx;
  final double dy;

  factory SceneFrame.fit(Size size) {
    var s = math.max(size.width / refWidth, size.height * 0.40 / (refHeight - bandTop));
    // Portrait (phones): the cabin sits exactly in the middle of the screen. The picture ends
    // 244 px to the right of the cabin, so the zoom is chosen such that this is half the view.
    if (size.height > size.width * 1.15) {
      s = math.max(s, size.width / (2 * (refWidth - focusX)));
    }
    final visible = size.width / s;
    final x0 = visible >= refWidth ? 0.0 : (focusX - visible / 2).clamp(0.0, refWidth - visible).toDouble();
    return SceneFrame(scale: s, dx: -x0 * s, dy: size.height - refHeight * s);
  }
}

double _hash(int n) {
  final x = math.sin(n * 127.1 + 311.7) * 43758.5453;
  return x - x.floorToDouble();
}

List<double> _identity() => <double>[1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0];

/// Applies [a] first and then [b].
List<double> _compose(List<double> a, List<double> b) {
  final out = List<double>.filled(20, 0);
  for (var row = 0; row < 4; row++) {
    for (var col = 0; col < 5; col++) {
      var v = 0.0;
      for (var k = 0; k < 4; k++) {
        v += b[row * 5 + k] * a[k * 5 + col];
      }
      if (col == 4) v += b[row * 5 + 4];
      out[row * 5 + col] = v;
    }
  }
  return out;
}

List<double> _diag(double r, double g, double b, [double offR = 0, double offG = 0, double offB = 0]) =>
    <double>[r, 0, 0, 0, offR, 0, g, 0, 0, offG, 0, 0, b, 0, offB, 0, 0, 0, 1, 0];

List<double> _saturation(double s) {
  const lr = 0.2126;
  const lg = 0.7152;
  const lb = 0.0722;
  return <double>[
    lr * (1 - s) + s, lg * (1 - s), lb * (1 - s), 0, 0,
    lr * (1 - s), lg * (1 - s) + s, lb * (1 - s), 0, 0,
    lr * (1 - s), lg * (1 - s), lb * (1 - s) + s, 0, 0,
    0, 0, 0, 1, 0,
  ];
}


Color _mix(Color a, Color b, double t) => t <= 0 ? a : (t >= 1 ? b : Color.lerp(a, b, t)!);

Color _scaleColor(Color c, double k) => Color.fromARGB(255, (c.r * 255 * k).round().clamp(0, 255).toInt(), (c.g * 255 * k).round().clamp(0, 255).toInt(), (c.b * 255 * k).round().clamp(0, 255).toInt());

/// Static runs of shapes are recorded once per look (season / snow / ice) and replayed.
class _Seg {
  _Seg.picture(this.picture) : live = -1;
  _Seg.live(this.live) : picture = null;
  _Seg.ripples()
      : picture = null,
        live = -2;
  final ui.Picture? picture;
  final int live;
}

class _LookCache {
  String key = '';
  // Still image of the whole landscape (used when it does not move), and what it was drawn for.
  ui.Picture? still;
  String stillKey = '';
  List<Paint?> paints = <Paint?>[];
  List<_Seg> segs = <_Seg>[];
}

class ImageLandscapeRenderer {
  ImageLandscapeRenderer({
    required this.seasons,
    required this.light,
    required this.clock,
    required this.reduced,
    required this.snow,
    required this.rain,
    required this.fog,
    required this.cloud,
    this.wind = 18,
    this.windX = 0.6,
    this.time = 0,
    this.solarDay = 0,
  });

  final Seasons seasons;
  final LandscapeLight light;
  final double clock;
  final bool reduced;
  final double snow;
  final double rain;
  final double fog;
  final double cloud;

  /// Wind speed in km/h: calm = barely a tremble, 18 km/h = the reference movement, gale = more.
  final double wind;

  /// Horizontal wind direction on screen (+1 = to the right, -1 = to the left).
  final double windX;

  /// Real time in seconds (animals walk at their own pace, not at the wind's).
  final double time;

  /// Local (solar) day number with its fraction: decides which of the four windows are lit today.
  final double solarDay;

  static final _LookCache _cache = _LookCache();

  /// Frees the recorded pictures (the next paint records them again).
  static void disposeCache() {
    for (final s in _cache.segs) {
      s.picture?.dispose();
    }
    _cache.segs = <_Seg>[];
    _cache.paints = <Paint?>[];
    _cache.key = '';
    _cache.still?.dispose();
    _cache.still = null;
    _cache.stillKey = '';
  }

  /// Ambient value of the artwork itself (golden hour): the picture is shown ungraded here.
  static const double _refAmbient = 0.62;

  /// Lit windows of the cabin (gable, porch window, side window): left, top, right, bottom, glow.
  static const List<List<double>> _windows = [
    [1463, 521, 1475, 541, 46],
    [1479, 574, 1496, 600, 70],
    [1549, 573, 1571, 601, 56],
    [1615, 576, 1631, 596, 40],
  ];

  late final double _night = ((_refAmbient - light.ambient) / _refAmbient).clamp(0.0, 1.0).toDouble();
  late final double _day = ((light.ambient - _refAmbient) / (1 - _refAmbient)).clamp(0.0, 1.0).toDouble();
  late final double _snowAmt = math.max(seasons.winter * 0.85, snow * 0.9).clamp(0.0, 1.0).toDouble();
  late final double _frozen = (seasons.winter * 0.6).clamp(0.0, 0.75).toDouble();
  late final double _wind = windAmplitude(wind) * 1.6 * (1 + rain * 0.8);
  // In winter the crown is gone completely (no halo of leaves): only branches with snow remain.
  late final double _canopyAlpha = seasons.winter > 0.12 ? 0.0 : 1.0; // leaves are either there or gone, never half transparent
  late final double _sunGlow = (light.sunVisible * (1 - light.overcast * 0.8)).clamp(0.0, 1.0).toDouble();

  /// Colour grading of the whole artwork: slightly fresher and cooler in full daylight,
  /// washed out when overcast, dark and blue at night. At the reference light it is identity.
  // The grade only changes with the light, so one filter object serves many frames.
  static ui.ColorFilter? _filterCache;
  static int _filterKey = 0;

  ui.ColorFilter _lightFilter() {
    final key = Object.hash((_day * 200).round(), (light.overcast * 200).round(), (_night * 200).round());
    final cached = _filterCache;
    if (cached != null && key == _filterKey) return cached;
    _filterKey = key;
    return _filterCache = _buildLightFilter();
  }

  ui.ColorFilter _buildLightFilter() {
    var m = _identity();
    m = _compose(m, _diag(1 + 0.02 * _day, 1 + 0.045 * _day, 1 + 0.08 * _day));
    final sat = (1 + 0.10 * _day) * (1 - 0.50 * light.overcast);
    m = _compose(m, _saturation(sat));
    final dim = 1 - 0.10 * light.overcast;
    m = _compose(m, _diag(dim, dim, dim));
    final n = 0.84 * _night;
    m = _compose(m, _diag(1 - n, 1 - n, 1 - n, 8 * n, 16 * n, 36 * n));
    return ui.ColorFilter.matrix(m);
  }

  // ---------------------------------------------------------------- seasonal colours

  double _up(SceneData d, _Region r) {
    if (r.group < 0) return 0;
    final g = d.groups[r.group];
    return ((g.piv - r.cy) / g.h).clamp(0.0, 1.0).toDouble();
  }

  Color _tone(SceneData d, _Region r, int hex, ) {
    var c = Color(0xFF000000 | hex);
    final sp = seasons.spring, au = seasons.autumn;
    const white = Color(0xFFEEF4F8);
    switch (r.kind) {
      case _K.canopy:
      case _K.bush:
      case _K.foliage:
        final g = r.group >= 0 ? d.groups[r.group] : null;
        final conifer = g?.conifer ?? false;
        c = _mix(c, const Color(0xFF9AD65A), (conifer ? 0.12 : 0.34) * sp);
        if (au > 0.01) {
          const pal = [Color(0xFFD2691E), Color(0xFFC0392B), Color(0xFFE0A526), Color(0xFFB5651D), Color(0xFFD9822B)];
          final pick = (_hash((r.group + 3) * 11) * pal.length).floor() % pal.length;
          final alt = (_hash(r.idx * 7 + 2) * pal.length).floor() % pal.length;
          final lum = (c.r * 0.3 + c.g * 0.59 + c.b * 0.11) / 0.30;
          final target = _scaleColor(_mix(pal[pick], pal[alt], 0.35), lum.clamp(0.75, 1.25).toDouble());
          c = _mix(c, target, (conifer ? 0.12 : 0.82) * au);
        }
        final up = _up(d, r);
        c = _mix(c, white, (conifer ? 0.5 * (0.4 + 0.6 * up) : (0.30 + 0.55 * up)) * _snowAmt * (r.kind == _K.canopy ? 0.45 : 1.0));
        break;
      case _K.flower:
        break;
      case _K.grass:
        c = _mix(c, const Color(0xFFA6DD5E), 0.22 * sp);
        c = _mix(c, const Color(0xFFC2A44A), 0.55 * au);
        c = _mix(c, white, 0.93 * _snowAmt);
        break;
      case _K.path:
        c = _mix(c, white, 0.75 * _snowAmt);
        break;
      case _K.mtn:
        if (r.topY < 590) {
          // the far mountains follow the season: green in the warm months, earthy in autumn
          // and winter, and covered with snow (more towards the top) in the cold
          final warm = (1 - sp - au - seasons.winter).clamp(0.0, 1.0).toDouble() + sp;
          final lum = (c.r * 0.3 + c.g * 0.59 + c.b * 0.11) / 0.62;
          final green = _scaleColor(const Color(0xFF5F9A6E), lum.clamp(0.7, 1.3).toDouble());
          final earth = _scaleColor(const Color(0xFF9A8268), lum.clamp(0.7, 1.3).toDouble());
          c = _mix(c, green, 0.5 * warm.clamp(0.0, 1.0).toDouble());
          c = _mix(c, earth, 0.62 * au + 0.72 * seasons.winter);
          final high = ((610 - r.topY) / 230).clamp(0.0, 1.0).toDouble();
          c = _mix(c, white, (0.30 + 0.45 * high) * _snowAmt + 0.10 * au * high);
        } else {
          c = _mix(c, const Color(0xFFDDE8F3), 0.40 * _snowAmt);
        }
        break;
      case _K.rock:
        c = _mix(c, white, 0.5 * _snowAmt);
        break;
      case _K.roof:
        c = _mix(c, const Color(0xFFF1F6FA), 0.95 * _snowAmt);
        break;
      case _K.wood:
        c = _mix(c, white, 0.10 * _snowAmt);
        break;
      case _K.water:
        // warm sun reflections fade with the sun
        if (c.r > c.g * 0.92) {
          c = _mix(c, const Color(0xFF4A9BE8), 1 - _sunGlow);
        }
        c = _mix(c, const Color(0xFFD9E8F2), _frozen);
        break;
      case _K.win:
        c = _mix(c, const Color(0xFFD9C79A), 0.45 * _day * (1 - _night));
        c = _mix(c, const Color(0xFFFFE2A0), 0.65 * _night);
        break;
      default:
        break;
    }
    return c;
  }

  String _lookKey() {
    int q(double v) => (v * 24).round();
    return '${q(seasons.spring)}_${q(seasons.autumn)}_${q(seasons.winter)}_${q(_snowAmt)}_${q(_frozen)}_${q(_sunGlow)}_${(_day * 10).round()}_${(_night * 10).round()}_$reduced';
  }

  Paint _paintFor(SceneData d, _Region r) {
    final p = Paint()..isAntiAlias = true;
    if (r.kind == _K.canopy) {
      p.color = _tone(d, r, r.color);
    } else if (r.kind == _K.flower) {
      p.color = Color(0xFF000000 | r.color);
    } else if (r.grad != null) {
      final g = r.grad!;
      p.shader = ui.Gradient.linear(Offset(g[0], g[1]), Offset(g[2], g[3]), [_tone(d, r, g[4].toInt()), _tone(d, r, g[5].toInt())]);
    } else {
      p.color = _tone(d, r, r.color);
    }
    return p;
  }

  void _ensureLook(SceneData d) {
    final key = _lookKey();
    if (key == _cache.key) return;
    _cache.key = key;
    _cache.paints = <Paint?>[for (final r in d.regions) _paintFor(d, r)];
    final segs = <_Seg>[];
    ui.PictureRecorder? rec;
    Canvas? c;
    for (final r in d.regions) {
      if (r.kind == _K.flower) continue; // drawn last, in front of the grass
      final live = r.anim && !reduced;
      if (live) {
        if (rec != null) {
          segs.add(_Seg.picture(rec.endRecording()));
          rec = null;
          c = null;
        }
        segs.add(_Seg.live(r.idx));
      } else {
        if (rec == null) {
          rec = ui.PictureRecorder();
          c = Canvas(rec);
        }
        final skip = (r.kind == _K.canopy && _canopyAlpha < 0.01) || (r.kind == _K.flower && seasons.winter > 0.4);
        if (!skip) r.draw(c!, _cache.paints[r.idx]!, null);
        // A recorded picture owns the static draw commands. Keep Paint/shader objects only
        // for regions repainted live and flowers drawn after the grass; retaining every
        // static Paint duplicates hundreds of Dart and native shader handles.
        _cache.paints[r.idx] = null;
      }
      if (r.idx == d.waterHook) {
        if (rec != null) {
          segs.add(_Seg.picture(rec.endRecording()));
          rec = null;
          c = null;
        }
        segs.add(_Seg.ripples());
      }
    }
    if (rec != null) segs.add(_Seg.picture(rec.endRecording()));
    for (final s in _cache.segs) {
      s.picture?.dispose();
    }
    _cache.segs = segs;
  }

  // ------------------------------------------------------------------ wind and water

  Offset _displace(_Region r, double x, double y, SceneData d) {
    switch (r.kind) {
      case _K.canopy:
      case _K.bush:
      case _K.foliage:
        return _sway(d.groups[r.group], x, y, r.kind == _K.canopy);
      case _K.flower:
        // a flower moves as one piece (petals never drift apart): every point of a shape
        // gets the movement of the shape's own centre
        final fg = d.groups[r.group];
        final inHead = (fg.piv - r.cy) / fg.h > 0.5;
        return inHead ? _sway(fg, fg.cx, fg.piv - fg.h * 0.8, false) : _sway(fg, r.cx, r.cy, false);
      case _K.grass:
        return r.group >= 0 ? _sway(d.groups[r.group], x, y, false) : Offset.zero;
      case _K.trunk:
        return d.canopyGroup >= 0 ? _sway(d.groups[d.canopyGroup], x, y, false) : Offset.zero;
      case _K.water:
        final depth = ((y - 600) / 290).clamp(0.0, 1.0).toDouble();
        final k = (1 - _frozen * 1.6).clamp(0.0, 1.0).toDouble();
        return Offset(math.sin(clock * 1.8 + y * 0.15 + x * 0.01) * (1.0 + 4.5 * depth) * k, math.sin(clock * 2.4 + x * 0.08 + y * 0.12) * 1.4 * k);
      default:
        return Offset.zero;
    }
  }

  Offset _sway(_Group g, double x, double y, bool rustle) {
    final up = ((g.piv - y) / g.h).clamp(0.0, 1.2).toDouble();
    if (up <= 0) return Offset.zero;
    final lean = math.pow(up, 1.5).toDouble();
    final gust = (0.65 + 0.35 * math.sin(clock * 0.31 + g.phase)) * _wind;
    final bend = math.sin(clock * 1.35 * g.speed + g.phase + x * 0.004) * g.amp * lean * gust;
    final flutter = math.sin(clock * 3.4 + x * 0.13 + y * 0.10 + g.phase) * 0.6 * g.amp * lean * gust;
    var dx = bend + flutter + math.sin(clock * 2.3 + x * 0.09 + y * 0.07 + g.phase) * 0.14 * g.amp * lean;
    if (rustle) dx += math.sin(clock * 1.9 + x * 0.06 + y * 0.05) * 4.0 * up * _wind;
    // The picture is cut by the left edge of the screen: fade the movement out there so the
    // crown never pulls away from the frame and shows the cut.
    final pin = (x / 90).clamp(0.0, 1.0).toDouble();
    final k = pin * pin * (3 - 2 * pin);
    return Offset(dx * k, -dx.abs() * 0.04 * k);
  }

  // ---------------------------------------------------------------------------- paint

  void paint(Canvas canvas, Size size) {
    final d = SceneAssets.data;
    if (d == null) return;
    final frame = SceneFrame.fit(size);
    final stillKey = reduced ? _stillKey() : '';

    // A reduced-motion/loading scene is static. Replay its single picture directly instead
    // of also keeping all of the component pictures and Paint/shader objects alive.
    if (reduced && _cache.still != null && _cache.stillKey == stillKey) {
      canvas.save();
      canvas.translate(frame.dx, frame.dy);
      canvas.scale(frame.scale);
      canvas.drawPicture(_cache.still!);
      canvas.restore();
      return;
    }

    // The live renderer uses the segmented pictures below; a stale full-scene picture would
    // duplicate the same vector artwork in native memory after forecast data arrives.
    if (!reduced && _cache.still != null) {
      _cache.still!.dispose();
      _cache.still = null;
      _cache.stillKey = '';
    }
    // If the reduced scene was recorded earlier, its component pictures were intentionally
    // released. Rebuild them only if that one-picture cache actually needs refreshing.
    if (reduced && _cache.segs.isEmpty) _cache.key = '';
    _ensureLook(d);

    canvas.save();
    canvas.translate(frame.dx, frame.dy);
    canvas.scale(frame.scale);
    if (reduced) {
      final recorder = ui.PictureRecorder();
      final c = Canvas(recorder);
      _graded(c, d);
      _overlays(c, d);
      _cache.still?.dispose();
      _cache.still = recorder.endRecording();
      _cache.stillKey = stillKey;

      // The recorded whole-scene picture replaces the segmented pictures in static mode.
      // Releasing both segments and their Paints avoids retaining duplicate native paths,
      // pictures and gradient shaders while the forecast is unavailable.
      for (final segment in _cache.segs) {
        segment.picture?.dispose();
      }
      _cache.segs = <_Seg>[];
      _cache.paints = <Paint?>[];
      _cache.key = '';
      canvas.drawPicture(_cache.still!);
    } else {
      _graded(canvas, d);
      _overlays(canvas, d);
    }
    canvas.restore();
  }

  /// Everything the still picture depends on (the look, the light grade and lit windows).
  String _stillKey() {
    int q(double v, [double k = 20]) => (v * k).round();
    return '${_lookKey()}|${q(light.overcast)}|${q(light.sunVisible)}|${q(light.moonVisible)}|${q(windX, 10)}|${q(_wind, 1)}|${solarDay.floor()}';
  }

  /// The colour graded part: shapes, grass, flowers, twigs and blossoms.
  void _graded(Canvas canvas, SceneData d) {
    final bounds = Rect.fromLTWH(0, 0, SceneFrame.refWidth, SceneFrame.refHeight);

    // Everything inside this layer is colour graded together.
    canvas.saveLayer(bounds, Paint()..colorFilter = _lightFilter());
    Offset disp(_Region r, double x, double y) => _displace(r, x, y, d);
    for (final s in _cache.segs) {
      if (s.picture != null) {
        canvas.drawPicture(s.picture!);
        continue;
      }
      if (s.live == -2) {
        _ripples(canvas, d);
        continue;
      }
      final r = d.regions[s.live];
      if (r.kind == _K.canopy && _canopyAlpha < 0.01) {
        // bare crown
      } else if (!(r.kind == _K.flower && seasons.winter > 0.4)) {
        final fade = r.kind == _K.canopy && _canopyAlpha < 0.99;
        if (fade) canvas.saveLayer(r.layerBounds, Paint()..color = Color.fromARGB((_canopyAlpha * 255).round().clamp(0, 255).toInt(), 255, 255, 255));
        r.draw(canvas, _cache.paints[r.idx]!, disp);
        if (fade) canvas.restore();
      }
    }
    _blades(canvas, d);
    _flowers(canvas, d, disp);
    _bareTree(canvas, d);
    _blossoms(canvas, d);
    canvas.restore();
  }

  /// Window light, drawn over the graded part.
  void _overlays(Canvas canvas, SceneData d) {
    _windowLight(canvas);
  }

  // ------------------------------------------------------------------------ river

  /// Drifting streaks and ripples painted over the river (clipped to the river, under the bridge).
  void _ripples(Canvas canvas, SceneData d) {
    if (_frozen > 0.55) return;
    canvas.save();
    canvas.clipPath(d.rippleClip);
    final p = Paint()..strokeCap = StrokeCap.round;
    const span = SceneFrame.refWidth + 300;
    final live = reduced ? 0.0 : 1.0;
    for (var i = 0; i < _rippleCount; i++) {
      final u = math.pow(_hash(i * 7 + 1), 0.9).toDouble();
      final y = 600 + u * (SceneFrame.refHeight - 600);
      final speed = live * (9 + _hash(i * 5 + 3) * 16) * (0.4 + u);
      final x = ((_hash(i * 13 + 2) * span + clock * speed) % span) - 150;
      final length = (18 + _hash(i * 3 + 9) * 70) * (0.4 + u);
      final tw = reduced ? 0.7 : 0.5 + 0.5 * math.sin(clock * 0.9 + i * 1.7);
      final a = (0.10 + 0.26 * _hash(i * 11 + 5)) * (0.4 + 0.6 * tw) * (1 - _frozen * 1.7);
      final dark = i % 3 == 0;
      p
        ..color = (dark ? const Color(0xFF1E6FD0) : const Color(0xFFFFFFFF)).withValues(alpha: (dark ? a * 1.2 : a).clamp(0.0, 1.0).toDouble())
        ..strokeWidth = 1.0 + u * 2.2;
      final path = (_scratch..reset())..moveTo(x, y);
      const n = 6;
      for (var j = 1; j <= n; j++) {
        final px = x + length * j / n;
        path.lineTo(px, y + math.sin(clock * 2.2 * live + px * 0.09 + i) * (0.8 + u * 2.0));
      }
      p.style = PaintingStyle.stroke;
      canvas.drawPath(path, p);
    }
    if (rain > 0.05 && _frozen < 0.3) {
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      for (var i = 0; i < 20; i++) {
        final t = reduced ? 0.4 : ((clock * 0.9 + _hash(i * 3 + 1) * 5) % 1.0);
        final x = 560 + _hash(i * 5 + 2) * 1200;
        final y = 700 + _hash(i * 9 + 4) * 170;
        ring.color = const Color(0xFFFFFFFF).withValues(alpha: (1 - t) * 0.45 * rain.clamp(0.0, 1.0));
        canvas.drawOval(Rect.fromCenter(center: Offset(x, y), width: 6 + t * 38, height: 2 + t * 12), ring);
      }
    }
    if (_frozen > 0.1) {
      final ice = Paint()
        ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.5 * _frozen)
        ..strokeWidth = 1.0;
      for (var i = 0; i < 26; i++) {
        final x = 520 + _hash(i * 3 + 1) * 1250;
        final y = 700 + _hash(i * 7 + 5) * 180;
        final a = _hash(i * 11 + 2) * 3.14 - 1.57;
        canvas.drawLine(Offset(x, y), Offset(x + math.cos(a) * 46, y + math.sin(a) * 12), ice);
      }
    }
    canvas.restore();
  }

  // ------------------------------------------------------------------ grass blades

  /// Hundreds of grass blades along the hill ridges; each leans and springs back in the wind.
  // The browser rasterises in WebAssembly: fewer ripple streaks there look the same at a glance.
  static final int _rippleCount = PlatformInfo.isWeb ? 32 : 60;

  // One path reused by every per-frame stroke / blade / twig (the canvas copies it when it is drawn).
  static final Path _scratch = Path();

  void _blades(Canvas canvas, SceneData d) {
    final paint = Paint()..isAntiAlias = true;
    var lastHex = -1;
    const white = Color(0xFFEEF4F8);
    for (var i = 0; i < d.blades.length; i++) {
      final b = d.blades[i];
      final x = b[0], y = b[1], h = b[2];
      final hex = b[3].toInt();
      if (hex != lastHex) {
        lastHex = hex;
        var c = Color(0xFF000000 | hex);
        c = _mix(c, const Color(0xFFA6DD5E), 0.22 * seasons.spring);
        c = _mix(c, const Color(0xFFC2A44A), 0.55 * seasons.autumn);
        c = _mix(c, white, 0.93 * _snowAmt);
        paint.color = c;
      }
      var lean = 0.0;
      if (!reduced) {
        final gust = (0.65 + 0.35 * math.sin(clock * 0.31 + x * 0.004)) * _wind;
        lean = (math.sin(clock * 1.9 + x * 0.045 + i * 0.7) * 0.55 + math.sin(clock * 3.7 + x * 0.11 + i) * 0.2) * h * 0.9 * gust;
      }
      final w = 0.9 + h * 0.12;
      final path = (_scratch..reset())
        ..moveTo(x - w, y + 1.5)
        ..quadraticBezierTo(x - w * 0.4 + lean * 0.25, y - h * 0.55, x + lean, y - h)
        ..quadraticBezierTo(x + w * 0.4 + lean * 0.25, y - h * 0.55, x + w, y + 1.5)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  // ------------------------------------------------------------- bare tree, blossoms

  /// Winter: the crown is gone and the thin twigs show, carrying snow.
  void _bareTree(Canvas canvas, SceneData d) {
    final a = seasons.winter > 0.12 ? 1.0 : 0.0;
    if (a < 0.02 || d.canopyGroup < 0) return;
    final g = d.groups[d.canopyGroup];
    final fill = Paint()
      ..isAntiAlias = true
      ..color = const Color(0xFF55423A).withValues(alpha: a);
    final snowFill = Paint()
      ..isAntiAlias = true
      ..color = const Color(0xFFF1F6FA).withValues(alpha: a * _snowAmt.clamp(0.0, 1.0));
    for (final s in d.twigs) {
      final o0 = _sway(g, s[0], s[1], false);
      final o1 = _sway(g, s[2], s[3], false);
      final a0 = Offset(s[0] + o0.dx, s[1] + o0.dy), a1 = Offset(s[2] + o1.dx, s[3] + o1.dy);
      _taper(canvas, a0, a1, s[4], s[5], fill);
      if (s[6] <= 5 && _snowAmt > 0.15 && a1.dy < a0.dy + 8) {
        // snow lies on the upper side of the branch
        final lift = Offset(0, -math.max(0.5, s[4] * 0.38));
        _taper(canvas, a0 + lift, a1 + lift, math.max(1.0, s[4] * 0.55), math.max(0.8, s[5] * 0.5), snowFill);
      }
    }
  }

  /// A branch piece that gets thinner from [w0] at [a] to [w1] at [b] (round ends, no steps).
  void _taper(Canvas canvas, Offset a, Offset b, double w0, double w1, Paint paint) {
    final d = b - a;
    final len = d.distance;
    if (len < 0.01) return;
    final n = Offset(-d.dy / len, d.dx / len);
    final path = (_scratch..reset())
      ..moveTo(a.dx + n.dx * w0 / 2, a.dy + n.dy * w0 / 2)
      ..lineTo(b.dx + n.dx * w1 / 2, b.dy + n.dy * w1 / 2)
      ..lineTo(b.dx - n.dx * w1 / 2, b.dy - n.dy * w1 / 2)
      ..lineTo(a.dx - n.dx * w0 / 2, a.dy - n.dy * w0 / 2)
      ..close();
    canvas.drawPath(path, paint);
    canvas.drawCircle(a, w0 / 2, paint);
    canvas.drawCircle(b, w1 / 2, paint);
  }

  /// Spring: pink blossoms in the crown.
  void _blossoms(Canvas canvas, SceneData d) {
    final a = (seasons.spring * 1.2).clamp(0.0, 1.0).toDouble() * _canopyAlpha;
    if (a < 0.04 || d.canopyGroup < 0) return;
    final g = d.groups[d.canopyGroup];
    final p = Paint();
    for (var i = 0; i < d.blossoms.length; i++) {
      final b = d.blossoms[i];
      final o = reduced ? Offset.zero : _sway(g, b.dx, b.dy, true);
      final white = i % 3 == 0;
      p.color = (white ? const Color(0xFFFFFFFF) : const Color(0xFFF7B3C8)).withValues(alpha: a * (0.8 + 0.2 * _hash(i)));
      // a five-petal blossom with a small golden centre
      final c = Offset(b.dx + o.dx, b.dy + o.dy);
      final r = 1.8 + _hash(i * 3 + 1) * 1.7;
      final rot = _hash(i * 7 + 5) * 6.2832;
      for (var k = 0; k < 5; k++) {
        final ang = rot + k * 1.2566;
        canvas.drawCircle(c + Offset(math.cos(ang), math.sin(ang)) * (r * 0.62), r * 0.56, p);
      }
      p.color = const Color(0xFFF2C14E).withValues(alpha: a);
      canvas.drawCircle(c, r * 0.28, p);
    }
  }

  // ------------------------------------------------------------------ cabin windows

  /// After dark the windows keep shining instead of being darkened with the rest.
  /// Which windows are lit: a different random 1-2 by day and 2-4 after dark, every day.
  List<bool> _litSet(int key, int minCount, int maxCount) {
    final count = minCount + (_hash(key * 5 + 2) * (maxCount - minCount + 1)).floor().clamp(0, maxCount - minCount);
    final order = List<int>.generate(_windows.length, (i) => i)..sort((a, b) => _hash(key * 13 + a * 5 + 3).compareTo(_hash(key * 13 + b * 5 + 3)));
    final lit = List<bool>.filled(_windows.length, false);
    for (var i = 0; i < count && i < order.length; i++) {
      lit[order[i]] = true;
    }
    return lit;
  }

  /// The cabin windows: lit ones shine warm (a lot more after dark, with a glow), the others
  /// are dark glass.
  void _windowLight(Canvas canvas) {
    final dayLit = _litSet(solarDay.floor() + 101, 1, 2);
    final nightLit = _litSet((solarDay - 0.5).floor() + 307, 2, 4);
    final nb = ((_night - 0.05) / 0.25).clamp(0.0, 1.0).toDouble();
    final dim = 1 - light.overcast * 0.2;
    final dayGlass = Color.lerp(const Color(0xFF55657A), const Color(0xFF3A4452), light.overcast)!;
    final nightGlass = const Color(0xFF151C2A);
    for (var i = 0; i < _windows.length; i++) {
      final w = _windows[i];
      final lit = (dayLit[i] ? 1.0 : 0.0) * (1 - nb) + (nightLit[i] ? 1.0 : 0.0) * nb;
      final glass = Color.lerp(dayGlass, nightGlass, _night)!;
      final warm = Color.lerp(const Color(0xFFEBCF94), const Color(0xFFFFE2A0), _night)!;
      final pane = Paint()..color = Color.lerp(glass, warm, lit)!;
      final mx = (w[0] + w[2]) / 2, my = (w[1] + w[3]) / 2;
      if (lit * _night > 0.02) {
        final center = Offset(mx, my);
        final amount = lit * _night * dim;
        canvas.drawCircle(
          center,
          w[4],
          Paint()..shader = RadialGradient(colors: [const Color(0xFFFFC866).withValues(alpha: 0.42 * amount), const Color(0xFFFFC866).withValues(alpha: 0)]).createShader(Rect.fromCircle(center: center, radius: w[4])),
        );
      }
      // the four panes with their cross bars
      canvas.drawRect(Rect.fromLTRB(w[0], w[1], mx - 0.9, my - 0.9), pane);
      canvas.drawRect(Rect.fromLTRB(mx + 0.9, w[1], w[2], my - 0.9), pane);
      canvas.drawRect(Rect.fromLTRB(w[0], my + 0.9, mx - 0.9, w[3]), pane);
      canvas.drawRect(Rect.fromLTRB(mx + 0.9, my + 0.9, w[2], w[3]), pane);
    }
  }

  // ---------------------------------------------------------------------------- flowers

  /// Flowers are painted last so grass and blades never hide them.
  void _flowers(Canvas canvas, SceneData d, _Disp disp) {
    if (seasons.winter > 0.25) return;
    for (final r in d.regions) {
      if (r.kind != _K.flower) continue;
      r.draw(canvas, _cache.paints[r.idx]!, reduced ? null : disp);
    }
  }


}
