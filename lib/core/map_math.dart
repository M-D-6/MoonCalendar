import 'dart:ui' as ui;

// One compiled pattern, shared by every token of the big map paths.
final RegExp _pathLetter = RegExp(r'^[A-Za-z]$');

class MapGeometry {
  final ui.Path path;
  final List<List<ui.Offset>> contours;
  const MapGeometry(this.path, this.contours);
}

typedef MapPointTransform = ui.Offset Function(double x, double y);

MapGeometry parseMapPath(String data, {MapPointTransform? transform}) {
  final tokens = RegExp(
    r'[MmLlHhVvZz]|[-+]?(?:(?:\d+(?:\.\d*)?)|(?:\.\d+))(?:[eE][-+]?\d+)?',
  ).allMatches(data).map((m) => m.group(0)!).toList(growable: false);

  const arity = <String, int>{
    'M': 2, 'm': 2,
    'L': 2, 'l': 2,
    'H': 1, 'h': 1,
    'V': 1, 'v': 1,
  };

  double x = 0;
  double y = 0;
  double startX = 0;
  double startY = 0;
  String? command;
  int index = 0;
  final path = ui.Path();
  final contours = <List<ui.Offset>>[];
  List<ui.Offset>? contour;

  ui.Offset tx(double px, double py) => transform?.call(px, py) ?? ui.Offset(px, py);

  void beginContour(double px, double py) {
    contour = <ui.Offset>[];
    contours.add(contour!);
    final p = tx(px, py);
    contour!.add(p);
    path.moveTo(p.dx, p.dy);
  }

  void addPoint(double px, double py) {
    contour ??= <ui.Offset>[];
    final p = tx(px, py);
    contour!.add(p);
    path.lineTo(p.dx, p.dy);
  }

  while (index < tokens.length) {
    final token = tokens[index];
    if (_pathLetter.hasMatch(token)) {
      command = token;
      index++;
    } else if (command == null) {
      index++;
      continue;
    }

    if (command == 'Z' || command == 'z') {
      path.close();
      if (contour != null && contour!.isNotEmpty) contour!.add(contour!.first);
      x = startX;
      y = startY;
      command = null;
      continue;
    }

    final count = arity[command];
    if (count == null) {
      command = null;
      continue;
    }
    if (index + count > tokens.length) break;
    if (_pathLetter.hasMatch(tokens[index])) {
      command = null;
      continue;
    }

    final relative = command == command.toLowerCase();
    final op = command;
    final values = <double>[];
    for (var j = 0; j < count; j++) {
      if (index >= tokens.length || _pathLetter.hasMatch(tokens[index])) break;
      values.add(double.parse(tokens[index++]));
    }
    if (values.length != count) {
      command = null;
      continue;
    }

    switch (op) {
      case 'M':
      case 'm':
        var nx = values[0];
        var ny = values[1];
        if (relative) {
          nx += x;
          ny += y;
        }
        x = nx;
        y = ny;
        startX = x;
        startY = y;
        beginContour(x, y);
        command = relative ? 'l' : 'L';
        break;
      case 'L':
      case 'l':
        var nx = values[0];
        var ny = values[1];
        if (relative) {
          nx += x;
          ny += y;
        }
        x = nx;
        y = ny;
        addPoint(x, y);
        break;
      case 'H':
      case 'h':
        var nx = values[0];
        if (relative) nx += x;
        x = nx;
        addPoint(x, y);
        break;
      case 'V':
      case 'v':
        var ny = values[0];
        if (relative) ny += y;
        y = ny;
        addPoint(x, y);
        break;
    }
  }

  return MapGeometry(path, contours);
}
