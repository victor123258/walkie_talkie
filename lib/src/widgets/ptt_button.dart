import 'package:flutter/material.dart';

/// Big hold-to-talk radio button.
class PttButton extends StatefulWidget {
  const PttButton({
    super.key,
    required this.enabled,
    required this.onPressedDown,
    required this.onPressedUp,
  });

  final bool enabled;
  final VoidCallback onPressedDown;
  final VoidCallback onPressedUp;

  @override
  State<PttButton> createState() => _PttButtonState();
}

class _PttButtonState extends State<PttButton> {
  bool _held = false;

  void _down(PointerDownEvent _) {
    if (!widget.enabled) return;
    setState(() => _held = true);
    widget.onPressedDown();
  }

  void _up(PointerEvent _) {
    if (!_held) return;
    setState(() => _held = false);
    widget.onPressedUp();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fill = !widget.enabled
        ? colors.surfaceContainerHighest
        : _held
        ? const Color(0xFFB71C1C)
        : const Color(0xFFD32F2F);
    final iconColor = widget.enabled ? Colors.white : colors.onSurfaceVariant;

    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: 'Push to talk',
      hint: widget.enabled ? 'Press and hold to transmit' : 'Channel is busy',
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _down,
        onPointerUp: _up,
        onPointerCancel: _up,
        child: AnimatedScale(
          scale: _held ? 0.94 : 1.0,
          duration: const Duration(milliseconds: 80),
          child: Container(
            width: 170,
            height: 170,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: fill,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: _held ? 6 : 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.mic_rounded, size: 52, color: iconColor),
                const SizedBox(height: 6),
                Text(
                  _held ? 'RELEASING…' : 'HOLD TO TALK',
                  style: TextStyle(
                    color: iconColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
