import 'dart:convert';
import 'dart:typed_data';

import 'config.dart';

/// A decoded packet that is addressed to us (correct channel, not our own id).
class RadioPacket {
  RadioPacket({
    required this.type,
    required this.id,
    required this.name,
    required this.platform,
    required this.channel,
    this.seq,
    this.wav,
  });

  /// 'beacon' or 'audio'.
  final String type;

  final String id;
  final String name;
  final String platform;
  final int channel;
  final int? seq;
  final Uint8List? wav;

  bool get isBeacon => type == 'beacon';
  bool get isAudio => type == 'audio';
}

String encodeBeacon({
  required String id,
  required String name,
  required int channel,
  required String platform,
}) {
  return jsonEncode({
    'v': AppConfig.protocolVersion,
    't': 'beacon',
    'id': id,
    'name': name,
    'ch': channel,
    'pf': platform,
  });
}

String encodeAudio({
  required String id,
  required String name,
  required int channel,
  required String platform,
  required int seq,
  required Uint8List wav,
}) {
  return jsonEncode({
    'v': AppConfig.protocolVersion,
    't': 'audio',
    'id': id,
    'name': name,
    'ch': channel,
    'pf': platform,
    'seq': seq,
    'wav': base64Encode(wav),
  });
}

/// Parses a raw datagram payload into a [RadioPacket].
///
/// Returns `null` for malformed packets, our own packets, packets on a
/// different channel, and anything larger than the maximum datagram size.
RadioPacket? decodePacket(
  Uint8List data, {
  required String myId,
  required int myChannel,
}) {
  if (data.isEmpty || data.length > 128 * 1024) return null;

  final Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(data));
  } catch (_) {
    return null;
  }
  if (decoded is! Map<String, dynamic>) return null;

  final id = decoded['id'];
  final ch = decoded['ch'];
  final type = decoded['t'];
  if (id is! String || ch is! num) return null;
  if (id == myId) return null;
  if (ch.toInt() != myChannel) return null;
  if (type != 'beacon' && type != 'audio') return null;

  final wavEncoded = decoded['wav'];
  Uint8List? wav;
  if (type == 'audio') {
    if (wavEncoded is! String) return null;
    try {
      wav = base64Decode(wavEncoded);
    } catch (_) {
      return null;
    }
  }

  return RadioPacket(
    type: type,
    id: id,
    name: decoded['name'] as String? ?? '',
    platform: decoded['pf'] as String? ?? '',
    channel: ch.toInt(),
    seq: (decoded['seq'] as num?)?.toInt(),
    wav: wav,
  );
}
