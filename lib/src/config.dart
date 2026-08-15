/// Global tunables for the walkie-talkie radio.
class AppConfig {
  AppConfig._();

  /// UDP port used for discovery beacons and voice packets.
  static const int udpPort = 48005;

  /// How often each device announces itself on the network.
  static const Duration beaconInterval = Duration(seconds: 2);

  /// A peer is considered gone if not heard from within this window.
  static const Duration peerTimeout = Duration(seconds: 8);

  /// After receiving a voice packet, the channel stays "busy" this long.
  static const Duration channelBusyAfter = Duration(milliseconds: 700);

  /// Voice sample rate (mono, 16 bit).
  static const int sampleRate = 16000;

  /// Number of channels in the captured audio.
  static const int channels = 1;

  /// Length of one voice chunk (300 ms), in PCM samples.
  static const int chunkSamples = sampleRate * 3 ~/ 10;

  /// A partial chunk smaller than this is dropped on release.
  static const int minFlushSamples = chunkSamples ~/ 3;

  /// Cap on the playback queue so a busy talker cannot eat all memory.
  static const int playbackQueueMax = 60;

  /// Protocol version tag sent in every packet.
  static const int protocolVersion = 1;
}
