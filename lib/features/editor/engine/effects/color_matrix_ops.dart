/// Composition primitive for 4×5 colour matrices.
///
/// Lifted out of `image_layer.dart` so the effect stack
/// (`color_adjustment_effects.dart`) can build per-effect matrices
/// without an inverted module → engine import. The math is the
/// same; only the location moved.
library;

/// Composes two affine 4×5 colour matrices ([a] applied after [b])
/// into a single equivalent 4×5 matrix. Treats each as the top
/// four rows of a 5×5 with `[0,0,0,0,1]` appended, then multiplies.
List<double> composeColorMatrices(List<double> a, List<double> b) {
  final out = List<double>.filled(20, 0);
  for (var i = 0; i < 4; i++) {
    for (var j = 0; j < 5; j++) {
      double sum = 0;
      for (var k = 0; k < 4; k++) {
        sum += a[i * 5 + k] * b[k * 5 + j];
      }
      if (j == 4) sum += a[i * 5 + 4];
      out[i * 5 + j] = sum;
    }
  }
  return out;
}

/// 4×5 identity colour matrix. Useful as the seed of a fold over a
/// list of per-effect matrices.
const List<double> kIdentityColorMatrix = <double>[
  1,
  0,
  0,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  0,
  0,
  1,
  0,
];
