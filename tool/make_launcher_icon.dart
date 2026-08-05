// Builds the launcher-icon source images from the TERRAX wordmark.
//
// Two outputs are needed:
//   assets/icon/icon.png            square, black background — iOS + legacy Android
//   assets/icon/icon_foreground.png transparent, for Android adaptive icons
//
// Android adaptive icons only guarantee the centre ~66% of the canvas is
// visible (the launcher masks the rest to a circle/squircle/rounded square), so
// the foreground wordmark is scaled to fit that safe zone or it would be
// clipped at both ends.
//
// The source art is white-on-black with no alpha, so the foreground layer is
// produced by turning luminance into alpha — that keeps the antialiased edges
// instead of hard-keying black to transparent.
//
// Usage: dart run tool/make_launcher_icon.dart <source.png>
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

void main(List<String> args) {
  final srcPath = args.isNotEmpty
      ? args[0]
      : r'..\TERRAX\TERRAX LOGOS\IMG_5009.png';
  final src = decodePng(File(srcPath).readAsBytesSync());
  if (src == null) {
    stderr.writeln('Could not decode $srcPath');
    exitCode = 1;
    return;
  }

  Directory('assets/icon').createSync(recursive: true);

  // --- Full-bleed square icon (iOS disallows alpha; black background is fine).
  final square = Image(width: canvas, height: canvas, numChannels: 4);
  fill(square, color: ColorRgba8(0, 0, 0, 255));
  final fitted = copyResize(src,
      width: canvas, height: canvas, interpolation: Interpolation.cubic);
  compositeImage(square, fitted);
  File('assets/icon/icon.png').writeAsBytesSync(encodePng(square));

  // --- Adaptive foreground: wordmark only, alpha from luminance.
  final trimmed = trim(_luminanceToAlpha(src), mode: TrimMode.transparent);
  final targetWidth = (canvas * safeZone).round();
  final scale = targetWidth / trimmed.width;
  final scaledHeight = (trimmed.height * scale).round();
  final wordmark = copyResize(trimmed,
      width: targetWidth,
      height: scaledHeight,
      interpolation: Interpolation.cubic);

  final foreground = Image(width: canvas, height: canvas, numChannels: 4);
  // Leave fully transparent; the background layer supplies the black.
  compositeImage(
    foreground,
    wordmark,
    dstX: ((canvas - wordmark.width) / 2).round(),
    dstY: ((canvas - wordmark.height) / 2).round(),
  );
  File('assets/icon/icon_foreground.png').writeAsBytesSync(
      encodePng(foreground));

  // --- In-app wordmark: tightly trimmed, transparent background.
  //
  // The source art is white on opaque black. Tinting that directly fills the
  // background too and renders as a solid block, so the in-app asset must
  // carry real transparency.
  Directory('assets/brand').createSync(recursive: true);
  File('assets/brand/wordmark.png').writeAsBytesSync(encodePng(trimmed));
  stdout.writeln('brand/wordmark.png  ${trimmed.width}x${trimmed.height} '
      '(transparent)');

  stdout.writeln('icon.png            ${square.width}x${square.height}');
  stdout.writeln('icon_foreground.png ${foreground.width}x${foreground.height} '
      '(wordmark ${wordmark.width}x${wordmark.height})');
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
