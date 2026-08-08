// Generates the Google Play store graphics into store/play/.
//
//   store/play/app-icon-512.png              512x512, TX monogram on black
//   store/play/feature-graphic-1024x500.png  wordmark centred, faint TX behind
//
// Screenshots are captured separately (see docs/play-store-metadata.md).
// Sources are the already-generated transparent brand marks, so this needs no
// access to the original TERRAX LOGOS folder.
//
// Usage: dart run tool/make_play_assets.dart
import 'dart:io';

import 'package:image/image.dart';

void main() {
  final tx = decodePng(File('assets/brand/tx_mark.png').readAsBytesSync());
  final wordmark =
      decodePng(File('assets/brand/wordmark.png').readAsBytesSync());
  if (tx == null || wordmark == null) {
    stderr.writeln('Run tool/make_tx_assets.dart and '
        'tool/make_launcher_icon.dart first.');
    exitCode = 1;
    return;
  }

  Directory('store/play').createSync(recursive: true);

  // --- App icon: TX on black, like the web/PWA icons.
  final icon = _blackCanvas(512, 512);
  _composeCentred(icon, tx, widthFraction: 0.8);
  File('store/play/app-icon-512.png').writeAsBytesSync(encodePng(icon));
  stdout.writeln('store/play/app-icon-512.png  512x512');

  // --- Feature graphic: faint TX watermark behind the wordmark, brand style.
  final feature = _blackCanvas(1024, 500);
  final ghost = _withOpacity(tx, 0.05);
  _composeCentred(feature, ghost, widthFraction: 0.55);
  _composeCentred(feature, wordmark, widthFraction: 0.62);
  File('store/play/feature-graphic-1024x500.png')
      .writeAsBytesSync(encodePng(feature));
  stdout.writeln('store/play/feature-graphic-1024x500.png  1024x500');
}

Image _blackCanvas(int w, int h) {
  final img = Image(width: w, height: h, numChannels: 4);
  fill(img, color: ColorRgba8(0, 0, 0, 255));
  return img;
}

void _composeCentred(Image canvas, Image art, {required double widthFraction}) {
  final targetWidth = (canvas.width * widthFraction).round();
  final scaled = copyResize(art,
      width: targetWidth,
      height: (art.height * targetWidth / art.width).round(),
      interpolation: Interpolation.cubic);
  compositeImage(
    canvas,
    scaled,
    dstX: ((canvas.width - scaled.width) / 2).round(),
    dstY: ((canvas.height - scaled.height) / 2).round(),
  );
}

Image _withOpacity(Image src, double opacity) {
  final out = Image.from(src);
  for (final p in out) {
    p.a = (p.a * opacity).round();
  }
  return out;
}
