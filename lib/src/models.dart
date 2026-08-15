/// A device discovered on the local network.
class Peer {
  Peer({
    required this.id,
    required this.name,
    required this.address,
    required this.platform,
    required this.lastSeen,
  });

  /// Stable unique id of the remote device.
  final String id;

  /// Human friendly name, e.g. "Mike's phone".
  String name;

  /// Source IP of the last packet received from this device.
  String address;

  /// Reported platform tag (android / ios / windows / other).
  String platform;

  /// Time the last packet (beacon or voice) arrived.
  DateTime lastSeen;

  /// True while this peer is transmitting voice.
  bool isTalking = false;

  Peer copy() => Peer(
    id: id,
    name: name,
    address: address,
    platform: platform,
    lastSeen: lastSeen,
  )..isTalking = isTalking;
}

/// Transmit state of the local radio.
enum TxState {
  /// Free to transmit.
  idle,

  /// Another device is transmitting (half-duplex channel is busy).
  busy,

  /// This device is currently transmitting.
  transmitting,
}

/// High level radio status shown in the UI.
enum RadioStatus { searching, ready, busy, transmitting }
