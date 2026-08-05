/// A plain RGB triple (0–255 per channel). Protocol- and UI-agnostic.
class Rgb {
  final int r;
  final int g;
  final int b;

  const Rgb(this.r, this.g, this.b)
      : assert(r >= 0 && r <= 255),
        assert(g >= 0 && g <= 255),
        assert(b >= 0 && b <= 255);

  static const white = Rgb(255, 255, 255);
  static const black = Rgb(0, 0, 0);

  /// Returns this color scaled by [factor] (0.0–1.0), e.g. for brightness.
  Rgb scaled(double factor) {
    final f = factor.clamp(0.0, 1.0);
    return Rgb((r * f).round(), (g * f).round(), (b * f).round());
  }

  Map<String, dynamic> toJson() => {'r': r, 'g': g, 'b': b};

  factory Rgb.fromJson(Map<String, dynamic> json) =>
      Rgb(json['r'] as int, json['g'] as int, json['b'] as int);

  @override
  bool operator ==(Object other) =>
      other is Rgb && other.r == r && other.g == g && other.b == b;

  @override
  int get hashCode => Object.hash(r, g, b);

  @override
  String toString() => 'Rgb($r, $g, $b)';
}
