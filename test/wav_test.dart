import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:walkie_talkie/src/config.dart';
import 'package:walkie_talkie/src/wav.dart';

void main() {
  group('buildWav', () {
    test('writes a valid RIFF/WAVE header for PCM16 mono 16kHz', () {
      final pcm = Int16List.fromList([100, -100, 0, 32767, -32768]);
      final wav = buildWav(pcm);

      expect(wav.length, 44 + pcm.length * 2);
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      expect(String.fromCharCodes(wav.sublist(12, 16)), 'fmt ');
      expect(String.fromCharCodes(wav.sublist(36, 40)), 'data');

      final view = ByteData.sublistView(wav);
      expect(view.getUint32(4, Endian.little), 36 + pcm.length * 2);
      expect(view.getUint16(20, Endian.little), 1); // PCM
      expect(view.getUint16(22, Endian.little), AppConfig.channels);
      expect(view.getUint32(24, Endian.little), AppConfig.sampleRate);
      expect(view.getUint16(34, Endian.little), 16); // bits per sample
      expect(view.getUint32(40, Endian.little), pcm.length * 2);
    });

    test('payload bytes round-trip intact', () {
      final pcm = Int16List.fromList(
        List.generate(1000, (i) => (i * 7 - 3000).clamp(-32768, 32767)),
      );
      final wav = buildWav(pcm);
      final samples = Int16List.sublistView(wav, 44, wav.length);
      expect(samples, pcm);
    });

    test('empty input still produces a valid container', () {
      final wav = buildWav(Int16List(0));
      expect(wav.length, 44);
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    });
  });
}
