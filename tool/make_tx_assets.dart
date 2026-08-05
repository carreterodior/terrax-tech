// Builds the TX-monogram assets from the TERRAX LOGOS source art.
//
// Outputs:
//   assets/brand/tx_mark.png   trimmed, transparent — in-app watermark
//   web/favicon.png            64px, TX on black — browser tab icon
//   web/icons/Icon-192.png     PWA icons, TX on black
//   web/icons/Icon-512.png
//   web/icons/Icon-maskable-192.png   extra padding for launcher masks
//   web/icons/Icon-maskable-512.png
//
// The launcher icons (assets/icon/*) deliberately stay on the TERRAX
// wordmark — see tool/make_launcher_icon.dart. This tool only covers the web
// favicon/PWA icons and the in-app watermark, which use the TX monogram.
//
// Like the launcher tool, the source is white-on-opaque-black, so the
// transparent variant comes from luminance-as-alpha.
//
// Usage: dart run tool/make_tx_assets.dart [source.png]
import 'dart:io';

import 'package:image/image.dart';

void main(List<String> args) {
  final srcPath = args.isNotEmpty
      ? args[0]
      : r'..\TERRAX\TERRAX LOGOS\4C15C6A9-1FD7-4BE8-A194-E290825C7D50.png';
  final src = decodePng(File(srcPath).readAsBytesSync());
  if (src == null) {
    stderr.writeln('Could not decode $srcPath');
    exitCode = 1;
    return;
  }

  final mark = trim(_luminanceToAlpha(src), mode: TrimMode.transparent);

  Directory('assets/brand').createSync(recursive: true);
  File('assets/brand/tx_mark.png').writeAsBytesSync(encodePng(mark));
  stdout.writeln('assets/brand/tx_mark.png  ${mark.width}x${mark.height}');

  Directory('web/icons').createSync(recursive: true);
  for (final (path, size, markFraction) in [
    ('web/favicon.png', 64, 0.86),
    ('web/icons/Icon-192.png', 192, 0.80),
    ('web/icons/Icon-512.png', 512, 0.80),
    // Maskable icons must keep art inside the centre safe zone (~80% circle).
    ('web/icons/Icon-maskable-192.png', 192, 0.58),
    ('web/icons/Icon-maskable-512.png', 512, 0.58),
  ]) {
    File(path).writeAsBytesSync(encodePng(_txOnBlack(mark, size, markFraction)));
    stdout.writeln('$path  ${size}x$size');
  }
}

/// A [size]-square black tile with the TX mark centred at [markFraction] of
/// the width.
Image _txOnBlack(Image mark, int size, double markFraction) {
  final tile = Image(width: size, height: size, numChannels: 4);
  fill(tile, color: ColorRgba8(0, 0, 0, 255));
  final targetWidth = (size * markFraction).round();
  final scaled = copyResize(mark,
      width: targetWidth,
      height: (mark.height * targetWidth / mark.width).round(),
      interpolation: Interpolation.cubic);
  compositeImage(
    tile,
    scaled,
    dstX: ((size - scaled.width) / 2).round(),
    dstY: ((size - scaled.height) / 2).round(),
  );
  return tile;
}

/// Same conversion as tool/make_launcher_icon.dart: luminance becomes alpha so
/// white art on black becomes white art on transparency with soft edges.
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
