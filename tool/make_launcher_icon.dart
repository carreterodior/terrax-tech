// Builds the launcher-icon source images: the RGB Bluetooth mark stacked above
// the TERRAX wordmark.
//
// Two outputs are needed:
//   assets/icon/icon.png            square, black background — iOS + legacy Android
//   assets/icon/icon_foreground.png transparent, for Android adaptive icons
//
// Android adaptive icons only guarantee the centre ~66% of the canvas is
// visible (the launcher masks the rest to a circle/squircle/rounded square), so
// the artwork is scaled to fit that safe zone or it would be clipped.
//
// The wordmark source art is white-on-black with no alpha, so the transparent
// layer is produced by turning luminance into alpha — that keeps the antialiased
// edges instead of hard-keying black to transparent.
//
// `assets/icon/bt_mark.png` is the pre-rendered Bluetooth glyph carrying the
// same red/green/blue diagonal sweep the home screen's empty state uses. It is
// committed rather than generated here because it comes out of the Material
// Icons font, which this package cannot rasterize.
//
// Usage: dart run tool/make_launcher_icon.dart [source.png]
//        (with no argument it reuses the already-trimmed assets/brand/wordmark.png)
import 'dart:io';

import 'package:image/image.dart';

const canvas = 1024;

/// Fraction of the canvas width the wordmark occupies in the adaptive
/// foreground.
///
/// Keep this near 1.0: `flutter_launcher_icons` wraps the foreground drawable
/// in a 16% inset, which already implements the adaptive-icon safe zone.
/// Pre-shrinking here too would compound the two and leave the wordmark tiny.
const safeZone = 0.98;

/// Wordmark width as a fraction of the composed artwork's width.
const wordmarkWidthFraction = 0.86;

/// Bluetooth mark height as a fraction of the canvas.
const markHeightFraction = 0.34;

/// Gap between the mark and the wordmark, as a fraction of the canvas.
const gapFraction = 0.07;

void main(List<String> args) {
  Directory('assets/icon').createSync(recursive: true);
  Directory('assets/brand').createSync(recursive: true);

  // The wordmark comes either from fresh source art (white on black) or from
  // the already-trimmed asset, so re-running this never needs the original file.
  final Image trimmed;
  if (args.isNotEmpty) {
    final src = decodePng(File(args[0]).readAsBytesSync());
    if (src == null) {
      stderr.writeln('Could not decode ${args[0]}');
      exitCode = 1;
      return;
    }
    trimmed = trim(_luminanceToAlpha(src), mode: TrimMode.transparent);
    // In-app wordmark: tightly trimmed, transparent background. The source art
    // is white on opaque black; tinting that directly fills the background too
    // and renders as a solid block, so the asset must carry real transparency.
    File('assets/brand/wordmark.png').writeAsBytesSync(encodePng(trimmed));
    stdout.writeln('brand/wordmark.png  ${trimmed.width}x${trimmed.height} '
        '(transparent)');
  } else {
    final existing = decodePng(File('assets/brand/wordmark.png').readAsBytesSync());
    if (existing == null) {
      stderr.writeln('assets/brand/wordmark.png missing; pass the source art');
      exitCode = 1;
      return;
    }
    trimmed = existing;
  }

  final mark = decodePng(File('assets/icon/bt_mark.png').readAsBytesSync());
  if (mark == null) {
    stderr.writeln('assets/icon/bt_mark.png missing');
    exitCode = 1;
    return;
  }

  final artwork = _compose(mark, trimmed);

  // --- Full-bleed square icon (iOS disallows alpha; black background is fine).
  final square = Image(width: canvas, height: canvas, numChannels: 4);
  fill(square, color: ColorRgba8(0, 0, 0, 255));
  compositeImage(square, artwork);
  File('assets/icon/icon.png').writeAsBytesSync(encodePng(square));

  // --- Adaptive foreground: same artwork, transparent, inside the safe zone.
  final scaled = copyResize(artwork,
      width: (canvas * safeZone).round(),
      height: (canvas * safeZone).round(),
      interpolation: Interpolation.cubic);
  final foreground = Image(width: canvas, height: canvas, numChannels: 4);
  compositeImage(
    foreground,
    scaled,
    dstX: ((canvas - scaled.width) / 2).round(),
    dstY: ((canvas - scaled.height) / 2).round(),
  );
  File('assets/icon/icon_foreground.png').writeAsBytesSync(
      encodePng(foreground));

  stdout.writeln('icon.png            ${square.width}x${square.height}');
  stdout.writeln('icon_foreground.png ${foreground.width}x${foreground.height}');
}

/// Stacks the Bluetooth [mark] above the [wordmark] on a transparent square,
/// centred as a group so the pair reads as one lockup at launcher sizes.
Image _compose(Image mark, Image wordmark) {
  final markHeight = (canvas * markHeightFraction).round();
  final markWidth = (mark.width * markHeight / mark.height).round();
  final scaledMark = copyResize(mark,
      width: markWidth,
      height: markHeight,
      interpolation: Interpolation.cubic);

  final wordWidth = (canvas * wordmarkWidthFraction).round();
  final wordHeight = (wordmark.height * wordWidth / wordmark.width).round();
  final scaledWord = copyResize(wordmark,
      width: wordWidth,
      height: wordHeight,
      interpolation: Interpolation.cubic);

  final gap = (canvas * gapFraction).round();
  final totalHeight = scaledMark.height + gap + scaledWord.height;
  var y = ((canvas - totalHeight) / 2).round();

  final out = Image(width: canvas, height: canvas, numChannels: 4);
  compositeImage(out, scaledMark,
      dstX: ((canvas - scaledMark.width) / 2).round(), dstY: y);
  y += scaledMark.height + gap;
  compositeImage(out, scaledWord,
      dstX: ((canvas - scaledWord.width) / 2).round(), dstY: y);
  return out;
}

/// Copies [src] with each pixel's luminance used as its alpha, so white art on
/// a black field becomes white art on transparency with soft edges intact.
///
/// The "black" background carries compression noise rather than being exactly
/// 0, so anything below [_floor] is forced fully transparent — otherwise the
/// whole canvas stays faintly opaque and [trim] finds no border to crop.
Image _luminanceToAlpha(Image src) {
  const floor = 32;
  final out = Image(width: src.width, height: src.height, numChannels: 4);
  for (final p in src) {
    final lum = getLuminance(p).round().clamp(0, 255);
    final alpha = lum <= floor
        ? 0
        : (((lum - floor) / (255 - floor)) * 255).round().clamp(0, 255);
    out.setPixelRgba(p.x, p.y, 255, 255, 255, alpha);
  }
  return out;
}
