import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'config.dart';
import 'models.dart';
import 'protocol.dart';
import 'wav.dart';

/// Owns the radio: UDP discovery + voice transport, mic capture and
/// speaker playback. Exposes state as a [ChangeNotifier] for the UI.
class WalkieController extends ChangeNotifier {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  RawDatagramSocket? _recvSocket;
  RawDatagramSocket? _sendSocket;
  InternetAddress _sendBindAddress = InternetAddress.anyIPv4;
  final Set<String> _broadcastTargets = {'255.255.255.255'};
  InternetAddress? _ownAddress;

  StreamSubscription<Uint8List>? _txStreamSub;
  StreamSubscription<void>? _playerCompleteSub;

  Timer? _beaconTimer;
  Timer? _networkTimer;
  Timer? _ticker;
  Timer? _playbackWatchdog;

  final List<int> _txBuffer = [];
  final List<Uint8List> _playQueue = [];
  bool _playing = false;
  bool _txActive = false;
  int _txSeq = 0;

  final Map<String, Peer> _peers = {};

  File? _identityFile;
  String _deviceId = '';
  String _deviceName = '';
  int _channel = 1;

  bool _initialized = false;
  bool _micGranted = false;
  bool _disposed = false;
  DateTime? _lastRxAt;
  DateTime? _talkingUntil;
  String? _talkingPeerId;
  String? _lastError;

  // Convenience accessors -----------------------------------------------------

  String get deviceName => _deviceName;
  String get deviceId => _deviceId;
  int get channel => _channel;
  bool get initialized => _initialized;
  bool get micGranted => _micGranted;
  String? get lastError => _lastError;
  String get ownAddress => _ownAddress?.address ?? 'unknown';

  List<Peer> get peers {
    final list = _peers.values.map((e) => e.copy()).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  bool get isTransmitting => _txActive;

  bool get isReceiving =>
      _lastRxAt != null &&
      DateTime.now().difference(_lastRxAt!) < AppConfig.channelBusyAfter;

  RadioStatus get status {
    if (_txActive) return RadioStatus.transmitting;
    if (isReceiving) return RadioStatus.busy;
    if (_peers.isNotEmpty) return RadioStatus.ready;
    return RadioStatus.searching;
  }

  bool get canTransmit =>
      _initialized && _micGranted && !_txActive && status != RadioStatus.busy;

  // Lifecycle -----------------------------------------------------------------

  Future<void> init() async {
    await _loadIdentity();
    await _requestMicPermission();
    await _openSockets();
    if (_disposed) {
      _recvSocket?.close();
      _sendSocket?.close();
      return;
    }
    _initialized = true;
    _playerCompleteSub = _player.onPlayerComplete.listen((_) {
      _playing = false;
      _cancelPlaybackWatchdog();
      _playNext();
    });
    _startTimers();
    _sendBeacon();
    notifyListeners();
  }

  Future<void> _requestMicPermission() async {
    try {
      _micGranted = await _recorder.hasPermission();
    } catch (e) {
      _micGranted = false;
      _lastError = 'Microphone error: $e';
    }
  }

  Future<void> requestMicPermission() async {
    await _requestMicPermission();
    if (_disposed) return;
    notifyListeners();
  }

  Future<void> _openSockets() async {
    try {
      _recvSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        AppConfig.udpPort,
        reuseAddress: true,
      );
      _recvSocket!.broadcastEnabled = true;
      _recvSocket!.listen(_onDatagram);

      await _refreshNetwork();
      _sendSocket = await RawDatagramSocket.bind(
        _sendBindAddress,
        0,
        reuseAddress: true,
      );
      _sendSocket!.broadcastEnabled = true;
    } catch (e) {
      _lastError = 'Network error: $e';
    }
  }

  Future<void> _refreshNetwork() async {
    var found = false;
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.isLoopback) continue;
          if (!found) {
            _sendBindAddress = addr;
            _ownAddress = addr;
            found = true;
          }
          final broadcast = addr.broadcast?.address;
          if (broadcast != null) _broadcastTargets.add(broadcast);
        }
      }
    } catch (_) {}
    if (found) _broadcastTargets.add('255.255.255.255');
  }

  void _startTimers() {
    _beaconTimer = Timer.periodic(
      AppConfig.beaconInterval,
      (_) => _sendBeacon(),
    );
    _networkTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _refreshNetwork(),
    );
    _ticker = Timer.periodic(const Duration(milliseconds: 300), (_) {
      if (_disposed) return;
      _updateTalkingFlags();
      _prunePeers();
      notifyListeners();
    });
  }

  void _updateTalkingFlags() {
    final now = DateTime.now();
    final talkingUntil = _talkingUntil;
    final talking = talkingUntil != null && now.isBefore(talkingUntil);
    for (final peer in _peers.values) {
      peer.isTalking = talking && peer.id == _talkingPeerId;
    }
  }

  void _prunePeers() {
    final now = DateTime.now();
    final expired = _peers.entries
        .where((e) => now.difference(e.value.lastSeen) > AppConfig.peerTimeout)
        .map((e) => e.key)
        .toList();
    for (final id in expired) {
      _peers.remove(id);
    }
  }

  // Identity ------------------------------------------------------------------

  Future<void> _loadIdentity() async {
    try {
      final dir = await getApplicationSupportDirectory();
      _identityFile = File(p.join(dir.path, 'walkie_identity.json'));
      if (_identityFile!.existsSync()) {
        final data = jsonDecode(
          await _identityFile!.readAsString(),
        ) as Map<String, dynamic>;
        _deviceId = data['id'] as String? ?? '';
        _deviceName = data['name'] as String? ?? '';
        _channel = (data['channel'] as num?)?.toInt() ?? 1;
      }
    } catch (_) {}

    if (_deviceId.isEmpty) _deviceId = _randomId();
    if (_deviceName.isEmpty) {
      _deviceName =
          '${_platformLabel()}-${_deviceId.substring(0, 4).toUpperCase()}';
    }
    _channel = _channel.clamp(1, 9);
    _saveIdentity();
  }

  String _randomId() {
    final r = Random.secure();
    final bytes = List<int>.generate(8, (_) => r.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  String _platformLabel() {
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iPhone';
    if (Platform.isWindows) return 'PC';
    if (Platform.isMacOS) return 'Mac';
    if (Platform.isLinux) return 'Linux';
    return 'Device';
  }

  void _saveIdentity() {
    try {
      _identityFile?.writeAsStringSync(
        jsonEncode({'id': _deviceId, 'name': _deviceName, 'channel': _channel}),
      );
    } catch (_) {}
  }

  Future<void> rename(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == _deviceName) return;
    _deviceName = trimmed;
    _saveIdentity();
    notifyListeners();
    _sendBeacon();
  }

  Future<void> setChannel(int value) async {
    final clamped = value.clamp(1, 9);
    if (clamped == _channel) return;
    _channel = clamped;
    _playQueue.clear();
    _saveIdentity();
    notifyListeners();
    _sendBeacon();
  }

  // Transmit ------------------------------------------------------------------

  Future<void> startTransmit() async {
    if (_txActive || !_micGranted || status == RadioStatus.busy) return;
    _txActive = true;
    _txSeq = 0;
    _txBuffer.clear();
    notifyListeners();

    try {
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: AppConfig.sampleRate,
          numChannels: AppConfig.channels,
        ),
      );
      _txStreamSub = stream.listen(
        _onTxPcm,
        onError: (Object e) {
          _lastError = 'Recording error: $e';
          _finishTransmit();
        },
      );
    } catch (e) {
      _lastError = 'Recording error: $e';
      _finishTransmit();
    }
  }

  void _onTxPcm(Uint8List data) {
    if (!_txActive) return;
    if (data.length.isOdd) return;
    final samples = Int16List.sublistView(data, 0, data.length);
    _txBuffer.addAll(samples);

    while (_txBuffer.length >= AppConfig.chunkSamples) {
      final chunk = Int16List.fromList(
        _txBuffer.sublist(0, AppConfig.chunkSamples),
      );
      _txBuffer.removeRange(0, AppConfig.chunkSamples);
      _sendAudio(chunk);
    }
  }

  void stopTransmit() {
    if (!_txActive) return;
    if (_txBuffer.length >= AppConfig.minFlushSamples) {
      final chunk = Int16List.fromList(_txBuffer);
      _sendAudio(chunk);
    }
    _txBuffer.clear();
    _finishTransmit();
  }

  Future<void> _finishTransmit() async {
    await _txStreamSub?.cancel();
    _txStreamSub = null;
    try {
      await _recorder.stop();
    } catch (_) {}
    _txActive = false;
    if (_disposed) return;
    notifyListeners();
  }

  void _sendAudio(Int16List chunk) {
    final wav = buildWav(chunk);
    final msg = encodeAudio(
      id: _deviceId,
      name: _deviceName,
      channel: _channel,
      platform: _platformLabel().toLowerCase(),
      seq: _txSeq++,
      wav: wav,
    );
    _broadcast(msg);
  }

  void _sendBeacon() {
    if (_sendSocket == null) return;
    final msg = encodeBeacon(
      id: _deviceId,
      name: _deviceName,
      channel: _channel,
      platform: _platformLabel().toLowerCase(),
    );
    _broadcast(msg);
  }

  void _broadcast(String msg) {
    if (_sendSocket == null) return;
    final bytes = utf8.encode(msg);
    // Voice packets are larger than one Wi-Fi frame, so the OS IP-fragments
    // them. Android delivers fragmented *unicast* datagrams reliably but
    // routinely drops fragmented *broadcast* datagrams. After beacon discovery
    // has taught us a peer's real IP, send to it directly (unicast) too, so the
    // only broadcast dependency is the small beacon. Broadcast stays as the
    // initial-contact fallback.
    final targets = <String>{..._broadcastTargets};
    for (final peer in _peers.values) {
      final addr = peer.address;
      if (addr.isNotEmpty) targets.add(addr);
    }
    for (final target in targets) {
      try {
        _sendSocket!.send(bytes, InternetAddress(target), AppConfig.udpPort);
      } catch (_) {}
    }
  }

  // Receive -------------------------------------------------------------------

  void _onDatagram(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final dg = _recvSocket?.receive();
    if (dg == null) return;
    _handlePacket(dg.data, dg.address.address);
  }

  void _handlePacket(Uint8List data, String fromAddress) {
    final packet = decodePacket(data, myId: _deviceId, myChannel: _channel);
    if (packet == null) return;

    if (packet.isBeacon) {
      _upsertPeer(packet, fromAddress);
    } else if (packet.isAudio) {
      _upsertPeer(packet, fromAddress);
      final now = DateTime.now();
      _lastRxAt = now;
      _talkingPeerId = packet.id;
      _talkingUntil = now.add(AppConfig.channelBusyAfter);
      final wav = packet.wav;
      if (wav != null && !_txActive) {
        _enqueuePlayback(wav);
      }
    }
  }

  void _upsertPeer(RadioPacket packet, String fromAddress) {
    final name = packet.name.trim();
    final platform = packet.platform.trim();
    final now = DateTime.now();
    final peer = _peers[packet.id];
    if (peer == null) {
      _peers[packet.id] = Peer(
        id: packet.id,
        name: name.isEmpty ? 'Device-${packet.id}' : name,
        address: fromAddress,
        platform: platform.isEmpty ? 'other' : platform,
        lastSeen: now,
      );
    } else {
      if (name.isNotEmpty) peer.name = name;
      if (platform.isNotEmpty) peer.platform = platform;
      peer.address = fromAddress;
      peer.lastSeen = now;
    }
  }

  // Playback ------------------------------------------------------------------

  void _enqueuePlayback(Uint8List wav) {
    _playQueue.add(wav);
    while (_playQueue.length > AppConfig.playbackQueueMax) {
      _playQueue.removeAt(0);
    }
    _playNext();
  }

  void _playNext() {
    if (_playing || _playQueue.isEmpty) return;
    _playing = true;
    final bytes = _playQueue.removeAt(0);
    _armPlaybackWatchdog();
    try {
      _player.play(BytesSource(bytes, mimeType: 'audio/wav')).catchError((
        Object e,
      ) {
        _playing = false;
        _cancelPlaybackWatchdog();
        _playNext();
      });
    } catch (_) {
      _playing = false;
      _cancelPlaybackWatchdog();
      _playNext();
    }
  }

  void _armPlaybackWatchdog() {
    _playbackWatchdog?.cancel();
    _playbackWatchdog = Timer(const Duration(seconds: 2), () {
      if (_playing) {
        _playing = false;
        _playNext();
      }
    });
  }

  void _cancelPlaybackWatchdog() {
    _playbackWatchdog?.cancel();
    _playbackWatchdog = null;
  }

  // Teardown ------------------------------------------------------------------

  @override
  void dispose() {
    _disposed = true;
    _beaconTimer?.cancel();
    _networkTimer?.cancel();
    _ticker?.cancel();
    _cancelPlaybackWatchdog();
    _playerCompleteSub?.cancel();
    _txStreamSub?.cancel();
    _recvSocket?.close();
    _sendSocket?.close();
    _player.dispose();
    _recorder.dispose();
    super.dispose();
  }
}
