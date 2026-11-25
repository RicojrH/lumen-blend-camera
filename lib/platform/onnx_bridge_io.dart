import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import '../services/auto_matte_engine.dart';

Future<Float32List> runOnnxSegmentationModel({
  required String? onnxModelPath,
  required Float32List inputNchw,
  required int inputSize,
}) async {
  if (onnxModelPath == null ||
      onnxModelPath.trim().isEmpty ||
      !File(onnxModelPath).existsSync()) {
    throw const OnnxModelNotConfiguredException(
      '尚未导入端侧 ONNX 抠图模型（支持 RMBG-1.4 / IS-Net-Anime / U²-Net .onnx）。请在「设置」中填入本地模型文件路径，或切换至「二次元护线」即时抠图。',
    );
  }

  final ort = OnnxRuntime();
  final session = await ort.createSession(onnxModelPath);
  OrtValue? inputTensor;
  Map<String, OrtValue>? outputs;
  try {
    final inputName = session.inputNames.first;
    inputTensor =
        await OrtValue.fromList(inputNchw, [1, 3, inputSize, inputSize]);
    outputs = await session.run({inputName: inputTensor});
    final outTensor = outputs[session.outputNames.first];
    if (outTensor == null) {
      throw Exception('ONNX 模型未返回有效掩码张量');
    }
    final rawFlat = await outTensor.asFlattenedList();

    final planeSize = inputSize * inputSize;
    double minV = double.infinity;
    double maxV = double.negativeInfinity;
    final maskSmall = Float32List(planeSize);
    final count = math.min(rawFlat.length, planeSize);
    for (int i = 0; i < count; i++) {
      final v = (rawFlat[i] as num).toDouble();
      maskSmall[i] = v;
      if (v < minV) minV = v;
      if (v > maxV) maxV = v;
    }
    final span = (maxV - minV).abs() < 1e-6 ? 1.0 : (maxV - minV);
    for (int i = 0; i < count; i++) {
      maskSmall[i] = ((maskSmall[i] - minV) / span).clamp(0.0, 1.0);
    }
    return maskSmall;
  } finally {
    await inputTensor?.dispose();
    if (outputs != null) {
      for (final v in outputs.values) {
        await v.dispose();
      }
    }
    await session.close();
  }
}
