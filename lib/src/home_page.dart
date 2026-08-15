import 'package:flutter/material.dart';

import 'models.dart';
import 'walkie_controller.dart';
import 'widgets/ptt_button.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final WalkieController _radio = WalkieController();

  @override
  void initState() {
    super.initState();
    _radio.init();
  }

  @override
  void dispose() {
    _radio.dispose();
    super.dispose();
  }

  Future<void> _promptRename() async {
    final controller = TextEditingController(text: _radio.deviceName);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Your device name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 24,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Name shown to other devices',
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name != null && mounted) {
      await _radio.rename(name);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.radio_rounded, color: Color(0xFFB0BFFF)),
            SizedBox(width: 10),
            Text('Walkie Talkie'),
          ],
        ),
        actions: [
          PopupMenuButton<int>(
            tooltip: 'Channel',
            icon: const Icon(Icons.radio_rounded),
            onSelected: _radio.setChannel,
            itemBuilder: (context) => [
              for (var ch = 1; ch <= 9; ch++)
                PopupMenuItem(value: ch, child: Text('Channel $ch')),
            ],
          ),
          IconButton(
            tooltip: 'Rename device',
            icon: const Icon(Icons.edit_rounded),
            onPressed: _promptRename,
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _radio,
        builder: (context, _) => _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Column(
        children: [
          _StatusBanner(status: _radio.status, peers: _radio.peers.length),
          if (!_radio.micGranted)
            _MicDeniedBanner(onRetry: _radio.requestMicPermission),
          Expanded(child: _buildPeerArea(theme)),
          _buildTransmitArea(theme),
        ],
      ),
    );
  }

  Widget _buildPeerArea(ThemeData theme) {
    final peers = _radio.peers;
    if (peers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.wifi_find_rounded,
                size: 64,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text('No devices found yet', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                'Open the app on another phone or PC and make sure every '
                'device is connected to the same Wi-Fi network.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: peers.length,
      separatorBuilder: (_, _) => const SizedBox(height: 4),
      itemBuilder: (context, index) => _PeerTile(peer: peers[index]),
    );
  }

  Widget _buildTransmitArea(ThemeData theme) {
    final canTalk = _radio.canTransmit;
    final hint = !_radio.micGranted
        ? 'Microphone permission is required'
        : _radio.status == RadioStatus.busy
        ? 'Channel is busy — wait for it to clear'
        : _radio.status == RadioStatus.transmitting
        ? 'You are transmitting — release to listen'
        : canTalk
        ? 'Hold to talk'
        : 'Searching for devices…';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        children: [
          Text(
            'You: ${_radio.deviceName}  •  Channel ${_radio.channel}',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          PttButton(
            enabled: canTalk,
            onPressedDown: _radio.startTransmit,
            onPressedUp: _radio.stopTransmit,
          ),
          const SizedBox(height: 14),
          Text(
            hint,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.status, required this.peers});

  final RadioStatus status;
  final int peers;

  (Color, IconData, String) _info() {
    switch (status) {
      case RadioStatus.transmitting:
        return (const Color(0xFFB71C1C), Icons.mic_rounded, 'Transmitting…');
      case RadioStatus.busy:
        return (
          const Color(0xFFE65100),
          Icons.speaker_phone_rounded,
          'Channel busy — someone is talking',
        );
      case RadioStatus.ready:
        return (
          const Color(0xFF1B5E20),
          Icons.campaign_rounded,
          'Ready · $peers device${peers == 1 ? '' : 's'} online',
        );
      case RadioStatus.searching:
        return (
          const Color(0xFF37474F),
          Icons.sync_rounded,
          'Searching for devices on this Wi-Fi…',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final (color, icon, label) = _info();
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MicDeniedBanner extends StatelessWidget {
  const _MicDeniedBanner({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.mic_off_rounded,
            color: Theme.of(context).colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Microphone access is denied. Grant it to transmit voice.',
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Grant')),
        ],
      ),
    );
  }
}

class _PeerTile extends StatelessWidget {
  const _PeerTile({required this.peer});

  final Peer peer;

  IconData _icon() {
    switch (peer.platform) {
      case 'android':
        return Icons.smartphone_rounded;
      case 'ios':
        return Icons.phone_iphone_rounded;
      case 'windows':
        return Icons.desktop_windows_rounded;
      default:
        return Icons.devices_other_rounded;
    }
  }

  String _timeAgo(DateTime time) {
    final seconds = DateTime.now().difference(time).inSeconds;
    if (seconds < 3) return 'now';
    if (seconds < 60) return '${seconds}s ago';
    return '${seconds ~/ 60}m ago';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: peer.isTalking
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.25),
          child: Icon(_icon(), color: theme.colorScheme.primary),
        ),
        title: Text(
          peer.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${peer.address} · ${_timeAgo(peer.lastSeen)}',
          style: theme.textTheme.bodySmall,
        ),
        trailing: peer.isTalking
            ? Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFD32F2F),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.graphic_eq_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'TALKING',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              )
            : const Icon(Icons.circle, size: 10, color: Color(0xFF4CAF50)),
      ),
    );
  }
}
