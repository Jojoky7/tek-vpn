import 'dart:math';

import 'package:circle_flags/circle_flags.dart';
import 'package:flutter/material.dart';

import '../services/storage.dart';
import '../state/app_state.dart';
import 'strings.dart';
import 'theme.dart';

/// The number next to a server: the TCP time, or a dash when the server
/// does not work through the VPN.
String pingText(CheckResult? check) {
  if (check == null) return '';
  if (check.alive == false) return '—';
  final ms = check.tcpMs ?? check.realMs;
  return ms == null ? '' : S.current.ms(ms);
}

/// The round button in the middle of the main screen.
class PowerButton extends StatefulWidget {
  const PowerButton({super.key, required this.state, required this.onTap, this.size = 176});

  final ConnState state;
  final VoidCallback onTap;
  final double size;

  @override
  State<PowerButton> createState() => _PowerButtonState();
}

class _PowerButtonState extends State<PowerButton> with SingleTickerProviderStateMixin {
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  bool get _busy =>
      widget.state == ConnState.connecting || widget.state == ConnState.disconnecting;

  @override
  void initState() {
    super.initState();
    if (_busy) _spin.repeat();
  }

  @override
  void didUpdateWidget(PowerButton old) {
    super.didUpdateWidget(old);
    if (_busy && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!_busy && _spin.isAnimating) {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final on = widget.state == ConnState.connected;
    final size = widget.size;
    final ringColor = on ? TekColors.green : scheme.outline;
    return Semantics(
      button: true,
      label: on ? 'disconnect' : 'connect',
      child: GestureDetector(
        onTap: widget.onTap,
        child: SizedBox(
          width: size + 40,
          height: size + 40,
          child: Stack(alignment: Alignment.center, children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              width: size + 40,
              height: size + 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: on ? TekColors.green.withValues(alpha: 0.10) : Colors.transparent,
              ),
            ),
            if (_busy)
              AnimatedBuilder(
                animation: _spin,
                builder: (_, _) => Transform.rotate(
                  angle: _spin.value * 2 * pi,
                  child: CustomPaint(
                    size: Size.square(size + 14),
                    painter: _ArcPainter(TekColors.green),
                  ),
                ),
              ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: on ? TekColors.green : scheme.surface,
                border: Border.all(color: ringColor, width: on ? 0 : 2),
                boxShadow: [
                  if (on)
                    BoxShadow(
                        color: TekColors.green.withValues(alpha: 0.35),
                        blurRadius: 32,
                        spreadRadius: 2),
                ],
              ),
              child: Icon(
                Icons.power_settings_new_rounded,
                size: size * 0.38,
                color: on ? Colors.white : scheme.onSurfaceVariant,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  _ArcPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Offset.zero & size, 0, pi * 0.6, false, paint);
  }

  @override
  bool shouldRepaint(_ArcPainter old) => old.color != color;
}

/// A round flag, or a globe when the country is unknown.
class Flag extends StatelessWidget {
  const Flag(this.code, {super.key, this.size = 32});
  final String? code;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = code;
    if (c == null || c.length != 2) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        child: Icon(Icons.public_rounded,
            size: size * 0.6, color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
    }
    return CircleFlag(c, size: size);
  }
}

/// The "fastest" icon in place of a flag.
class FastestIcon extends StatelessWidget {
  const FastestIcon({super.key, this.size = 32});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: TekColors.green.withValues(alpha: 0.14),
        ),
        child: Icon(Icons.bolt_rounded, size: size * 0.62, color: TekColors.green),
      );
}

/// Green when the server works through the VPN, red when it does not,
/// grey when not checked yet, pulsing while the check runs.
class PingDot extends StatelessWidget {
  const PingDot({super.key, required this.alive, this.checking = false, this.size = 8});
  final bool? alive;
  final bool checking;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = switch (alive) {
      true => TekColors.green,
      false => TekColors.red,
      null => TekColors.grey,
    };
    final dot = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
    if (!checking) return dot;
    return _Pulse(child: dot);
  }
}

class _Pulse extends StatefulWidget {
  const _Pulse({required this.child});
  final Widget child;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 800))
        ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: Tween(begin: 0.25, end: 1.0).animate(_c), child: widget.child);
}

/// The Tek mark drawn in code, so it is sharp at any size.
class TekMark extends StatelessWidget {
  const TekMark({super.key, this.size = 28, this.color});
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.square(size),
        painter: TekMarkPainter(color ?? TekColors.green),
      );
}

/// An arch over a stem: a "T" that is also a tunnel.
class TekMarkPainter extends CustomPainter {
  TekMarkPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.15
      ..strokeCap = StrokeCap.round;
    final arch = Path()
      ..moveTo(s * 0.16, s * 0.40)
      ..quadraticBezierTo(s * 0.5, s * 0.10, s * 0.84, s * 0.40);
    canvas.drawPath(arch, paint);
    canvas.drawLine(Offset(s * 0.5, s * 0.27), Offset(s * 0.5, s * 0.86), paint);
  }

  @override
  bool shouldRepaint(TekMarkPainter old) => old.color != color;
}
