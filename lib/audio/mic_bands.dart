import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:record/record.dart';

/// A source of six audio band levels (250 Hz, 500 Hz, 1 kHz, 2 kHz, 4 kHz,
/// 8 kHz) for sound-reactive lighting. Drivers consume this; nothing here
/// knows about BLE or UI.
abstract class BandSource {
  /// Starts capture and streams one `[b250, b500, b1k, b2k, b4k, b8k]` list per
  /// analysis window. Throws [StateError] when the microphone is unavailable
  /// (permission denied).
  Future<Stream<List<int>>> start();

  Future<void> stop();
}

/// Phone-microphone band sampler mirroring the CAR-LIGHTS app's
/// `AudioHelper`: 8 kHz mono PCM16, a radix-2 FFT over the largest power of
/// two that fits the buffer, and the bin at `(n - 1) * f / 8000` for each of
/// the six band frequencies.
///
/// The vendor app sends one frame per recorder buffer (every 40–80 ms); this
/// sampler groups samples into [windowSamples]-sample windows (64 ms at 8 kHz)
/// so the BLE write rate stays bounded.
class MicBandSampler implements BandSource {
  static const int sampleRate = 8000;
  static const int windowSamples = 512;
  static const List<int> bandHz = [250, 500, 1000, 2000, 4000, 8000];

  final AudioRecorder _recorder;
  StreamSubscription<Uint8List>? _sub;
  StreamController<List<int>>? _out;
  final List<int> _pending = <int>[];

  MicBandSampler({AudioRecorder? recorder})
      : _recorder = recorder ?? AudioRecorder();

  @override
  Future<Stream<List<int>>> start() async {
    if (!await _recorder.hasPermission()) {
      throw StateError('Microphone permission denied');
    }
    final pcm = await _recorder.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: sampleRate,
      numChannels: 1,
      autoGain: false,
      echoCancel: false,
      noiseSuppress: false,
    ));
    final out = StreamController<List<int>>.broadcast();
    _out = out;
    _pending.clear();
    _sub = pcm.listen((chunk) {
      _pending.addAll(pcm16ToSamples(chunk));
      while (_pending.length >= windowSamples) {
        final window = _pending.sublist(0, windowSamples);
        _pending.removeRange(0, windowSamples);
        if (!out.isClosed) out.add(bandsOf(window));
      }
    }, onError: (Object e, StackTrace st) {
      if (!out.isClosed) out.addError(e, st);
    });
    return out.stream;
  }

  @override
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    await _out?.close();
    _out = null;
    _pending.clear();
    try {
      await _recorder.stop();
    } catch (_) {
      // Already stopped.
    }
  }

  Future<void> dispose() async {
    await stop();
    await _recorder.dispose();
  }

  /// Little-endian 16-bit PCM → signed samples.
  static List<int> pcm16ToSamples(Uint8List bytes) {
    final count = bytes.length ~/ 2;
    final view = ByteData.sublistView(bytes, 0, count * 2);
    return List<int>.generate(count, (i) => view.getInt16(i * 2, Endian.little),
        growable: false);
  }

  /// Six band magnitudes for one window of samples, following the vendor
  /// app's bin selection (`(len - 1) * f / 8000` over the largest power of two
  /// that fits). Magnitude is the proper `sqrt(re² + im²)`; the vendor's
  /// `Complex.getIntValue` subtracts instead and rounds NaN to 0, which is a
  /// bug, not a protocol detail — the device only ever sees the 0–250 scaled
  /// result.
  static List<int> bandsOf(List<int> samples) {
    final n = _largestPowerOfTwoAtMost(samples.length);
    if (n < 2) return List<int>.filled(bandHz.length, 0);
    final re = Float64List(n);
    final im = Float64List(n);
    for (var i = 0; i < n; i++) {
      re[i] = samples[i].toDouble();
    }
    fft(re, im);
    final last = n - 1;
    return [
      for (final f in bandHz) _magnitude(re, im, (last * f) ~/ sampleRate),
    ];
  }

  static int _magnitude(Float64List re, Float64List im, int bin) {
    final r = re[bin];
    final i = im[bin];
    return math.sqrt(r * r + i * i).round();
  }

  static int _largestPowerOfTwoAtMost(int v) {
    var p = 1;
    while (p << 1 <= v) {
      p <<= 1;
    }
    return v >= 1 ? p : 0;
  }

  /// In-place iterative radix-2 FFT; `re.length` must be a power of two.
  static void fft(Float64List re, Float64List im) {
    final n = re.length;
    // Bit-reversal permutation.
    var j = 0;
    for (var i = 1; i < n; i++) {
      var bit = n >> 1;
      while (j & bit != 0) {
        j ^= bit;
        bit >>= 1;
      }
      j ^= bit;
      if (i < j) {
        final tr = re[i];
        re[i] = re[j];
        re[j] = tr;
        final ti = im[i];
        im[i] = im[j];
        im[j] = ti;
      }
    }
    for (var len = 2; len <= n; len <<= 1) {
      final ang = -2 * math.pi / len;
      final wr = math.cos(ang);
      final wi = math.sin(ang);
      for (var i = 0; i < n; i += len) {
        var cr = 1.0;
        var ci = 0.0;
        final half = len >> 1;
        for (var k = 0; k < half; k++) {
          final a = i + k;
          final b = a + half;
          final xr = re[b] * cr - im[b] * ci;
          final xi = re[b] * ci + im[b] * cr;
          re[b] = re[a] - xr;
          im[b] = im[a] - xi;
          re[a] += xr;
          im[a] += xi;
          final ncr = cr * wr - ci * wi;
          ci = cr * wi + ci * wr;
          cr = ncr;
        }
      }
    }
  }
}
