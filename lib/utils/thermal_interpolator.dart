class ThermalInterpolator {
  ThermalInterpolator._();

  static const _sourceSize = 8;
  static const _sourceLength = _sourceSize * _sourceSize;

  static List<double> interpolate8x8(
    List<double> grid8x8, {
    int targetSize = 64,
  }) {
    if (grid8x8.length != _sourceLength) {
      throw ArgumentError.value(
        grid8x8.length,
        'grid8x8',
        '輸入資料必須包含 64 筆溫度值',
      );
    }
    if (targetSize < 1) {
      throw ArgumentError.value(
        targetSize,
        'targetSize',
        '目標尺寸必須大於或等於 1',
      );
    }

    final output = List<double>.filled(targetSize * targetSize, 0.0);
    if (targetSize == 1) {
      output[0] = grid8x8[0];
      return output;
    }

    // 預先計算每個輸出座標對應的來源索引與權重，避免內層迴圈重複運算。
    final x0 = List<int>.filled(targetSize, 0);
    final x1 = List<int>.filled(targetSize, 0);
    final xWeight = List<double>.filled(targetSize, 0.0);
    final y0 = List<int>.filled(targetSize, 0);
    final y1 = List<int>.filled(targetSize, 0);
    final yWeight = List<double>.filled(targetSize, 0.0);
    final sourceScale = (_sourceSize - 1) / (targetSize - 1);

    for (var coordinate = 0; coordinate < targetSize; coordinate++) {
      final sourceCoordinate = (coordinate * sourceScale)
          .clamp(0.0, _sourceSize - 1.0)
          .toDouble();
      final lower = sourceCoordinate.floor();
      final upper = lower == _sourceSize - 1 ? lower : lower + 1;

      x0[coordinate] = lower;
      x1[coordinate] = upper;
      xWeight[coordinate] = sourceCoordinate - lower;
      y0[coordinate] = lower;
      y1[coordinate] = upper;
      yWeight[coordinate] = sourceCoordinate - lower;
    }

    var outputIndex = 0;
    for (var y = 0; y < targetSize; y++) {
      final topRow = y0[y] * _sourceSize;
      final bottomRow = y1[y] * _sourceSize;
      final verticalWeight = yWeight[y];
      final inverseVerticalWeight = 1.0 - verticalWeight;

      for (var x = 0; x < targetSize; x++) {
        final horizontalWeight = xWeight[x];
        final inverseHorizontalWeight = 1.0 - horizontalWeight;

        final topLeft = grid8x8[topRow + x0[x]];
        final topRight = grid8x8[topRow + x1[x]];
        final bottomLeft = grid8x8[bottomRow + x0[x]];
        final bottomRight = grid8x8[bottomRow + x1[x]];

        final top = topLeft * inverseHorizontalWeight +
            topRight * horizontalWeight;
        final bottom = bottomLeft * inverseHorizontalWeight +
            bottomRight * horizontalWeight;
        output[outputIndex++] =
            top * inverseVerticalWeight + bottom * verticalWeight;
      }
    }

    return output;
  }
}