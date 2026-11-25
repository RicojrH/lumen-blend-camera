import 'dart:typed_data';

import '../services/auto_matte_engine.dart';

Future<Float32List> runOnnxSegmentationModel({
  required String? onnxModelPath,
  required Float32List inputNchw,
  required int inputSize,
}) async {
  throw const OnnxModelNotConfiguredException(
    '当前为 Web 浏览器实时预览环境，端侧原生 ONNX Runtime (FFI) 仅在 iOS / Android 真机包中启用。请点击下方切换至「二次元护线」即时自动抠图！',
  );
}
