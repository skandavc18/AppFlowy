// Draws the built-in nature covers.
//
// Run from `frontend/appflowy_flutter`:
//   dart run tool/generate_nature_covers.dart
//
// The covers are original artwork rather than photographs: nothing here is
// licensed from anybody, and a scene can be retuned by changing the numbers
// below rather than by finding another picture.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const int width = 1600;
const int height = 900;

void main(List<String> arguments) {
  final directory = Directory(
    arguments.isNotEmpty
        ? arguments.first
        : 'assets/images/built_in_cover_images',
  );
  directory.createSync(recursive: true);

  final scenes = <String, Uint8List Function()>{
    'nature_cover_image_1.png': _dawnHills,
    'nature_cover_image_2.png': _pineRidges,
    'nature_cover_image_3.png': _oceanDusk,
    'nature_cover_image_4.png': _duneField,
    'nature_cover_image_5.png': _auroraPeaks,
    'nature_cover_image_6.png': _meadow,
  };

  scenes.forEach((name, draw) {
    final file = File('${directory.path}/$name');
    file.writeAsBytesSync(_encodePng(draw()));
    stdout.writeln('${file.path}  ${file.lengthSync()} bytes');
  });
}

// --------------------------------------------------------------- the scenes

Uint8List _dawnHills() {
  final canvas = _Canvas();
  canvas.sky(const [
    _Stop(0.0, _Rgb(0x2B, 0x2E, 0x6B)),
    _Stop(0.34, _Rgb(0x77, 0x51, 0x8F)),
    _Stop(0.62, _Rgb(0xD9, 0x7A, 0x83)),
    _Stop(0.82, _Rgb(0xF3, 0xA8, 0x72)),
    _Stop(1.0, _Rgb(0xFB, 0xD3, 0x9B)),
  ]);
  canvas.disc(0.68, 0.70, 74, const _Rgb(0xFF, 0xEB, 0xC4), glow: 240);
  canvas.ridge(
    base: 0.70,
    amplitude: 0.045,
    frequency: 1.3,
    phase: 0.4,
    colour: const _Rgb(0x8A, 0x5E, 0x86),
    haze: 0.22,
  );
  canvas.ridge(
    base: 0.78,
    amplitude: 0.055,
    frequency: 1.9,
    phase: 2.1,
    colour: const _Rgb(0x64, 0x42, 0x66),
    haze: 0.14,
  );
  canvas.ridge(
    base: 0.87,
    amplitude: 0.05,
    frequency: 2.6,
    phase: 4.3,
    colour: const _Rgb(0x3F, 0x2A, 0x4B),
    haze: 0.07,
  );
  canvas.ridge(
    base: 0.96,
    amplitude: 0.04,
    frequency: 3.4,
    phase: 1.2,
    colour: const _Rgb(0x25, 0x18, 0x33),
  );
  canvas.grain(4);
  return canvas.pixels;
}

Uint8List _pineRidges() {
  final canvas = _Canvas();
  canvas.sky(const [
    _Stop(0.0, _Rgb(0x8F, 0xC7, 0xD6)),
    _Stop(0.45, _Rgb(0xC7, 0xE3, 0xDF)),
    _Stop(1.0, _Rgb(0xE9, 0xF1, 0xE2)),
  ]);
  canvas.disc(0.24, 0.26, 52, const _Rgb(0xFF, 0xFD, 0xF0), glow: 150);
  canvas.ridge(
    base: 0.66,
    amplitude: 0.05,
    frequency: 1.5,
    phase: 0.9,
    colour: const _Rgb(0x9D, 0xBE, 0xB4),
    haze: 0.30,
  );
  canvas.ridge(
    base: 0.75,
    amplitude: 0.045,
    frequency: 2.2,
    phase: 3.0,
    colour: const _Rgb(0x6E, 0x9C, 0x8C),
    haze: 0.20,
  );
  canvas.pines(base: 0.84, colour: const _Rgb(0x3E, 0x6E, 0x62), scale: 0.9);
  canvas.pines(base: 0.96, colour: const _Rgb(0x22, 0x45, 0x3F), scale: 1.35);
  canvas.grain(3);
  return canvas.pixels;
}

Uint8List _oceanDusk() {
  final canvas = _Canvas();
  canvas.sky(const [
    _Stop(0.0, _Rgb(0x21, 0x2A, 0x5E)),
    _Stop(0.30, _Rgb(0x4E, 0x46, 0x8C)),
    _Stop(0.52, _Rgb(0xA5, 0x62, 0x92)),
    _Stop(0.66, _Rgb(0xE8, 0x8B, 0x7C)),
    _Stop(0.72, _Rgb(0xF6, 0xBE, 0x8E)),
    _Stop(1.0, _Rgb(0xF6, 0xBE, 0x8E)),
  ]);
  canvas.disc(0.5, 0.715, 66, const _Rgb(0xFF, 0xEF, 0xCE), glow: 300);
  canvas.sea(
    horizon: 0.72,
    near: const _Rgb(0x18, 0x1E, 0x46),
    far: const _Rgb(0x9E, 0x74, 0x93),
    sunAt: 0.5,
  );
  canvas.grain(4);
  return canvas.pixels;
}

Uint8List _duneField() {
  final canvas = _Canvas();
  canvas.sky(const [
    _Stop(0.0, _Rgb(0x6E, 0x9A, 0xB8)),
    _Stop(0.36, _Rgb(0xC6, 0xC8, 0xB6)),
    _Stop(0.58, _Rgb(0xF0, 0xCE, 0x9B)),
    _Stop(1.0, _Rgb(0xF7, 0xDD, 0xAF)),
  ]);
  canvas.disc(0.74, 0.44, 46, const _Rgb(0xFF, 0xF6, 0xDE), glow: 190);
  canvas.ridge(
    base: 0.60,
    amplitude: 0.035,
    frequency: 1.1,
    phase: 2.4,
    colour: const _Rgb(0xE2, 0xB9, 0x86),
    haze: 0.18,
  );
  canvas.ridge(
    base: 0.72,
    amplitude: 0.05,
    frequency: 1.6,
    phase: 5.1,
    colour: const _Rgb(0xC9, 0x99, 0x66),
    haze: 0.10,
  );
  canvas.ridge(
    base: 0.85,
    amplitude: 0.06,
    frequency: 2.1,
    phase: 0.6,
    colour: const _Rgb(0xA8, 0x76, 0x4C),
  );
  canvas.ridge(
    base: 0.99,
    amplitude: 0.05,
    frequency: 2.9,
    phase: 3.7,
    colour: const _Rgb(0x7C, 0x52, 0x37),
  );
  canvas.grain(5);
  return canvas.pixels;
}

Uint8List _auroraPeaks() {
  final canvas = _Canvas();
  canvas.sky(const [
    _Stop(0.0, _Rgb(0x07, 0x0D, 0x24)),
    _Stop(0.45, _Rgb(0x10, 0x1E, 0x42)),
    _Stop(1.0, _Rgb(0x1B, 0x33, 0x55)),
  ]);
  canvas.stars(260);
  canvas.aurora(
    centre: 0.34,
    spread: 0.16,
    colour: const _Rgb(0x54, 0xE0, 0xA8),
    strength: 0.55,
  );
  canvas.aurora(
    centre: 0.44,
    spread: 0.12,
    colour: const _Rgb(0x6C, 0xB8, 0xF2),
    strength: 0.36,
  );
  canvas.ridge(
    base: 0.74,
    amplitude: 0.10,
    frequency: 1.4,
    phase: 1.7,
    colour: const _Rgb(0x18, 0x2B, 0x45),
    haze: 0.20,
    peaked: true,
  );
  canvas.ridge(
    base: 0.92,
    amplitude: 0.11,
    frequency: 2.0,
    phase: 4.6,
    colour: const _Rgb(0x0A, 0x14, 0x26),
    peaked: true,
  );
  canvas.grain(3);
  return canvas.pixels;
}

Uint8List _meadow() {
  final canvas = _Canvas();
  canvas.sky(const [
    _Stop(0.0, _Rgb(0x5C, 0xA6, 0xD8)),
    _Stop(0.45, _Rgb(0xA8, 0xD2, 0xEC)),
    _Stop(1.0, _Rgb(0xE4, 0xF1, 0xEC)),
  ]);
  canvas.cloud(0.22, 0.24, 120);
  canvas.cloud(0.58, 0.17, 86);
  canvas.cloud(0.82, 0.29, 104);
  canvas.ridge(
    base: 0.63,
    amplitude: 0.04,
    frequency: 1.2,
    phase: 2.8,
    colour: const _Rgb(0xA9, 0xCB, 0x8E),
    haze: 0.24,
  );
  canvas.ridge(
    base: 0.75,
    amplitude: 0.05,
    frequency: 1.7,
    phase: 0.3,
    colour: const _Rgb(0x7E, 0xB0, 0x66),
    haze: 0.12,
  );
  canvas.ridge(
    base: 0.88,
    amplitude: 0.05,
    frequency: 2.4,
    phase: 5.4,
    colour: const _Rgb(0x55, 0x8B, 0x4C),
  );
  canvas.ridge(
    base: 1.02,
    amplitude: 0.04,
    frequency: 3.1,
    phase: 2.2,
    colour: const _Rgb(0x37, 0x66, 0x38),
  );
  canvas.grain(3);
  return canvas.pixels;
}

// --------------------------------------------------------------- the canvas

class _Rgb {
  const _Rgb(this.r, this.g, this.b);

  final int r;
  final int g;
  final int b;

  _Rgb lerp(_Rgb other, double t) => _Rgb(
        (r + (other.r - r) * t).round(),
        (g + (other.g - g) * t).round(),
        (b + (other.b - b) * t).round(),
      );
}

class _Stop {
  const _Stop(this.at, this.colour);

  final double at;
  final _Rgb colour;
}

class _Canvas {
  final Uint8List pixels = Uint8List(width * height * 3);
  final math.Random _random = math.Random(20260809);

  void _set(int x, int y, _Rgb colour) {
    final at = (y * width + x) * 3;
    pixels[at] = colour.r;
    pixels[at + 1] = colour.g;
    pixels[at + 2] = colour.b;
  }

  _Rgb _get(int x, int y) {
    final at = (y * width + x) * 3;
    return _Rgb(pixels[at], pixels[at + 1], pixels[at + 2]);
  }

  void _blend(int x, int y, _Rgb colour, double alpha) {
    if (x < 0 || y < 0 || x >= width || y >= height || alpha <= 0) {
      return;
    }
    final clamped = alpha.clamp(0.0, 1.0);
    _set(x, y, _get(x, y).lerp(colour, clamped));
  }

  void sky(List<_Stop> stops) {
    for (var y = 0; y < height; y++) {
      final t = y / (height - 1);
      _set(0, y, _sample(stops, t));
      final colour = _sample(stops, t);
      for (var x = 0; x < width; x++) {
        _set(x, y, colour);
      }
    }
  }

  static _Rgb _sample(List<_Stop> stops, double t) {
    for (var i = 0; i < stops.length - 1; i++) {
      final from = stops[i];
      final to = stops[i + 1];
      if (t >= from.at && t <= to.at) {
        final span = to.at - from.at;
        return from.colour
            .lerp(to.colour, span == 0 ? 0 : (t - from.at) / span);
      }
    }
    return t <= stops.first.at ? stops.first.colour : stops.last.colour;
  }

  /// A sun or a moon, with the light it throws into the sky around it.
  void disc(
    double cx,
    double cy,
    double radius,
    _Rgb colour, {
    double glow = 0,
  }) {
    final centreX = cx * width;
    final centreY = cy * height;
    if (glow > 0) {
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final distance = math.sqrt(
            math.pow(x - centreX, 2) + math.pow(y - centreY, 2),
          );
          if (distance > glow) {
            continue;
          }
          final falloff = math.pow(1 - distance / glow, 2.2).toDouble();
          _blend(x, y, colour, falloff * 0.55);
        }
      }
    }
    for (var y = (centreY - radius - 2).floor();
        y <= (centreY + radius + 2).ceil();
        y++) {
      for (var x = (centreX - radius - 2).floor();
          x <= (centreX + radius + 2).ceil();
          x++) {
        final distance = math.sqrt(
          math.pow(x - centreX, 2) + math.pow(y - centreY, 2),
        );
        _blend(x, y, colour, (radius - distance).clamp(0.0, 1.0));
      }
    }
  }

  /// One band of land, drawn from a smooth line rather than from a polygon so
  /// the horizon never shows a straight edge.
  void ridge({
    required double base,
    required double amplitude,
    required double frequency,
    required double phase,
    required _Rgb colour,
    double haze = 0,
    bool peaked = false,
  }) {
    for (var x = 0; x < width; x++) {
      final u = x / width;
      final wave = peaked
          ? _peaks(u * frequency + phase)
          : math.sin(u * frequency * math.pi * 2 + phase) * 0.6 +
              math.sin(u * frequency * math.pi * 4.7 + phase * 1.7) * 0.3 +
              math.sin(u * frequency * math.pi * 9.1 + phase * 0.6) * 0.1;
      final top = ((base - amplitude * wave) * height).round();
      for (var y = math.max(0, top); y < height; y++) {
        final depth = (y - top) / height;
        final shade = colour.lerp(const _Rgb(0, 0, 0), depth * 0.18);
        final alpha = y - top < 2 ? (y - top + 1) / 2 : 1.0;
        _blend(x, y, shade, alpha);
      }
      if (haze > 0) {
        for (var y = math.max(0, top); y < math.min(height, top + 90); y++) {
          _blend(
            x,
            y,
            const _Rgb(0xFF, 0xFF, 0xFF),
            haze * (1 - (y - top) / 90),
          );
        }
      }
    }
  }

  static double _peaks(double u) {
    final saw = (u % 1.0) * 2 - 1;
    return 1 - saw.abs() * 1.6 + math.sin(u * 11) * 0.12;
  }

  /// A stand of conifers along a ridge.
  void pines({
    required double base,
    required _Rgb colour,
    required double scale,
  }) {
    final line = (base * height).round();
    for (var y = math.max(0, line); y < height; y++) {
      for (var x = 0; x < width; x++) {
        _blend(x, y, colour, 1);
      }
    }
    var x = -20.0;
    while (x < width + 20) {
      final treeHeight = (70 + _random.nextDouble() * 60) * scale;
      final treeWidth = treeHeight * 0.42;
      final top = line - treeHeight;
      for (var y = top.round(); y < line; y++) {
        if (y < 0) {
          continue;
        }
        final along = (y - top) / treeHeight;
        final half = treeWidth * 0.5 * math.pow(along, 0.72);
        for (var dx = -half; dx <= half; dx += 1) {
          _blend((x + dx).round(), y, colour, 1);
        }
      }
      x += treeWidth * (0.55 + _random.nextDouble() * 0.5);
    }
  }

  /// Flat water, with the light of the low sun broken across it.
  void sea({
    required double horizon,
    required _Rgb near,
    required _Rgb far,
    required double sunAt,
  }) {
    final line = (horizon * height).round();
    for (var y = line; y < height; y++) {
      final t = (y - line) / (height - line);
      final band = far.lerp(near, math.pow(t, 0.7).toDouble());
      for (var x = 0; x < width; x++) {
        _set(x, y, band);
      }
    }
    // The sun's path widens and breaks up as it comes towards the reader.
    for (var y = line; y < height; y++) {
      final t = (y - line) / (height - line);
      final spread = 26 + t * 300;
      final centre = sunAt * width;
      final strength = (1 - t) * 0.85;
      final broken = 0.45 +
          0.55 *
              (math.sin(y * 0.7) * 0.5 + 0.5) *
              (1 - t * 0.4).clamp(0.0, 1.0);
      for (var x = (centre - spread).floor();
          x <= (centre + spread).ceil();
          x++) {
        if (x < 0 || x >= width) {
          continue;
        }
        final across = 1 - ((x - centre).abs() / spread);
        if (across <= 0) {
          continue;
        }
        _blend(
          x,
          y,
          const _Rgb(0xFF, 0xE6, 0xB8),
          math.pow(across, 1.8).toDouble() * strength * broken,
        );
      }
    }
  }

  void stars(int count) {
    for (var i = 0; i < count; i++) {
      final x = _random.nextInt(width);
      final y = _random.nextInt((height * 0.62).round());
      final brightness = 0.25 + _random.nextDouble() * 0.75;
      _blend(x, y, const _Rgb(0xFF, 0xFF, 0xFF), brightness);
      _blend(x + 1, y, const _Rgb(0xFF, 0xFF, 0xFF), brightness * 0.35);
      _blend(x, y + 1, const _Rgb(0xFF, 0xFF, 0xFF), brightness * 0.35);
    }
  }

  void aurora({
    required double centre,
    required double spread,
    required _Rgb colour,
    required double strength,
  }) {
    for (var x = 0; x < width; x++) {
      final u = x / width;
      final drift = math.sin(u * 5.1) * 0.05 + math.sin(u * 11.3 + 1.4) * 0.022;
      final band = (centre + drift) * height;
      final thickness = spread * height * (0.7 + 0.5 * math.sin(u * 7.7 + 2.1));
      for (var y = (band - thickness).floor();
          y <= (band + thickness).ceil();
          y++) {
        if (y < 0 || y >= height) {
          continue;
        }
        final across = 1 - ((y - band).abs() / thickness);
        if (across <= 0) {
          continue;
        }
        final curtain = 0.55 + 0.45 * (math.sin(u * 61) * 0.5 + 0.5);
        _blend(
          x,
          y,
          colour,
          math.pow(across, 1.6).toDouble() * strength * curtain,
        );
      }
    }
  }

  void cloud(double cx, double cy, double radius) {
    final centreX = cx * width;
    final centreY = cy * height;
    for (var puff = 0; puff < 5; puff++) {
      final offsetX = centreX + (puff - 2) * radius * 0.52;
      final offsetY = centreY + math.sin(puff * 1.7) * radius * 0.18;
      final size = radius * (0.55 + 0.45 * math.sin(puff * 2.3 + 1));
      for (var y = (offsetY - size).floor();
          y <= (offsetY + size).ceil();
          y++) {
        for (var x = (offsetX - size).floor();
            x <= (offsetX + size).ceil();
            x++) {
          final distance = math.sqrt(
            math.pow(x - offsetX, 2) + math.pow((y - offsetY) * 1.7, 2),
          );
          if (distance > size) {
            continue;
          }
          final soft = math.pow(1 - distance / size, 1.4).toDouble();
          _blend(x, y, const _Rgb(0xFF, 0xFF, 0xFF), soft * 0.55);
        }
      }
    }
  }

  /// A little tooth on the colour so a wide gradient never bands.
  void grain(int amount) {
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final noise = _random.nextInt(amount * 2 + 1) - amount;
        final at = (y * width + x) * 3;
        pixels[at] = (pixels[at] + noise).clamp(0, 255);
        pixels[at + 1] = (pixels[at + 1] + noise).clamp(0, 255);
        pixels[at + 2] = (pixels[at + 2] + noise).clamp(0, 255);
      }
    }
  }
}

// ------------------------------------------------------------------ the png

Uint8List _encodePng(Uint8List rgb) {
  final raw = Uint8List(height * (width * 3 + 1));
  var at = 0;
  for (var y = 0; y < height; y++) {
    raw[at++] = 0;
    raw.setRange(at, at + width * 3, rgb, y * width * 3);
    at += width * 3;
  }

  final out = BytesBuilder();
  out.add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);

  final header = BytesBuilder()
    ..add(_be32(width))
    ..add(_be32(height))
    ..add(const [8, 2, 0, 0, 0]);
  out.add(_chunk('IHDR', header.takeBytes()));
  out.add(
    _chunk(
      'IDAT',
      Uint8List.fromList(ZLibCodec().encode(raw)),
    ),
  );
  out.add(_chunk('IEND', Uint8List(0)));
  return out.takeBytes();
}

Uint8List _chunk(String name, Uint8List data) {
  final body = BytesBuilder()
    ..add(name.codeUnits)
    ..add(data);
  final bytes = body.takeBytes();
  return Uint8List.fromList([
    ..._be32(data.length),
    ...bytes,
    ..._be32(_crc32(bytes)),
  ]);
}

List<int> _be32(int value) => [
      (value >> 24) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 8) & 0xFF,
      value & 0xFF,
    ];

final List<int> _crcTable = List<int>.generate(256, (i) {
  var c = i;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(List<int> bytes) {
  var c = 0xFFFFFFFF;
  for (final byte in bytes) {
    c = _crcTable[(c ^ byte) & 0xFF] ^ (c >> 8);
  }
  return c ^ 0xFFFFFFFF;
}
