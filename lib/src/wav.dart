import 'dart:typed_data';

import 'config.dart';

/// Builds a canonical RIFF/WAVE file (16-bit PCM) from raw PCM samples.
///
/// Each voice chunk is wrapped into its own WAV container so it can be
/// decoded and played by `audioplayers` on every platform with zero
/// knowledge of the underlying codec.
Uint8List buildWav(Int16List pcm) {
  final sampleCount = pcm.length;
  final dataSize = sampleCount * 2;
  final totalSize = 44 + dataSize;

  final out = Uint8List(totalSize);
  final view = ByteData.sublistView(out);

  void ascii(int offset, String text) {
    for (var i = 0; i < text.length; i++) {
      out[offset + i] = text.codeUnitAt(i);
    }
  }

  ascii(0, 'RIFF');
  view.setUint32(4, 36 + dataSize, Endian.little);
  ascii(8, 'WAVE');

  ascii(12, 'fmt ');
  view.setUint32(16, 16, Endian.little); // fmt chunk size
  view.setUint16(20, 1, Endian.little); // PCM
  view.setUint16(22, AppConfig.channels, Endian.little);
  view.setUint32(24, AppConfig.sampleRate, Endian.little);
  view.setUint32(
    28,
    AppConfig.sampleRate * AppConfig.channels * 2,
    Endian.little,
  );
  view.setUint16(32, AppConfig.channels * 2, Endian.little); // block align
  view.setUint16(34, 16, Endian.little); // bits per sample

  ascii(36, 'data');
  view.setUint32(40, dataSize, Endian.little);

  if (sampleCount > 0) {
    out.setRange(
      44,
      44 + dataSize,
      pcm.buffer.asUint8List(pcm.offsetInBytes, pcm.lengthInBytes),
    );
  }
  return out;
}
