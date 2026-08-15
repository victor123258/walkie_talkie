import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:walkie_talkie/src/protocol.dart';

void main() {
  final wav = Uint8List.fromList(List.generate(64, (i) => i));

  RadioPacket? decode(Uint8List data, {String myId = 'me', int ch = 1}) =>
      decodePacket(data, myId: myId, myChannel: ch);

  Uint8List encode(String msg) => utf8.encode(msg);

  group('decodePacket', () {
    test('accepts a beacon on the same channel', () {
      final bytes = encode(
        encodeBeacon(id: 'abc', name: 'Bob', channel: 1, platform: 'android'),
      );
      final pkt = decode(bytes);
      expect(pkt, isNotNull);
      expect(pkt!.isBeacon, isTrue);
      expect(pkt.id, 'abc');
      expect(pkt.name, 'Bob');
      expect(pkt.channel, 1);
      expect(pkt.platform, 'android');
      expect(pkt.wav, isNull);
    });

    test('accepts an audio packet and decodes the wav payload', () {
      final bytes = encode(
        encodeAudio(
          id: 'abc',
          name: 'Bob',
          channel: 1,
          platform: 'ios',
          seq: 7,
          wav: wav,
        ),
      );
      final pkt = decode(bytes);
      expect(pkt, isNotNull);
      expect(pkt!.isAudio, isTrue);
      expect(pkt.seq, 7);
      expect(pkt.wav, wav);
    });

    test('rejects our own packets (no self-hearing)', () {
      final bytes = encode(
        encodeBeacon(id: 'me', name: 'Self', channel: 1, platform: 'windows'),
      );
      expect(decode(bytes), isNull);
    });

    test('rejects packets on a different channel', () {
      final bytes = encode(
        encodeBeacon(id: 'abc', name: 'Bob', channel: 3, platform: 'android'),
      );
      expect(decode(bytes, ch: 1), isNull);
    });

    test('rejects malformed data', () {
      expect(decode(Uint8List(0)), isNull);
      expect(decode(utf8.encode('not json')), isNull);
      expect(decode(utf8.encode('{"t":"beacon"}')), isNull);
      expect(decode(utf8.encode('[1,2,3]')), isNull);
    });

    test('rejects audio packets without a valid wav payload', () {
      final bytes = encode(
        '{"v":1,"t":"audio","id":"abc","name":"Bob","ch":1,"wav":"!!!"}',
      );
      expect(decode(bytes), isNull);
    });

    test('rejects packets larger than the maximum datagram size', () {
      final big = Uint8List(128 * 1024 + 1);
      expect(decode(big), isNull);
    });
  });
}
