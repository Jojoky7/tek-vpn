import 'dart:math';

import 'package:circle_flags/circle_flags.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

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

/// The round button in the middle of the main screen. Every press sends a
/// few rings across the screen, like a touch on calm water. They are
/// plain circles drawn by one ticker that stops when the last ring is gone,
/// so weak devices do not notice them.
class PowerButton extends StatefulWidget {
  const PowerButton({super.key, required this.state, required this.onTap, this.size = 176});

  final ConnState state;
  final VoidCallback onTap;
  final double size;

  @override
  State<PowerButton> createState() => _PowerButtonState();
}

class _PowerButtonState extends State<PowerButton> with TickerProviderStateMixin {
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
  final _waves = _Waves();
  late final Ticker _ticker = createTicker((elapsed) => _waves.tick(elapsed));
  bool _pressed = false;

  bool get _busy =>
      widget.state == ConnState.connecting || widget.state == ConnState.disconnecting;

  @override
  void initState() {
    super.initState();
    if (_busy) _spin.repeat();
    _waves.onIdle = () {
      if (_ticker.isActive) _ticker.stop();
    };
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
    _ticker.dispose();
    _spin.dispose();
    _waves.dispose();
    super.dispose();
  }

  void _tap() {
    if (!(MediaQuery.maybeDisableAnimationsOf(context) ?? false)) {
      if (!_ticker.isActive) {
        _waves.reset();
        _ticker.start();
      }
      _waves.touch();
    }
    widget.onTap();
  }

  void _press(bool down) {
    if (_pressed != down) setState(() => _pressed = down);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final on = widget.state == ConnState.connected;
    final size = widget.size;
    final ringColor = on ? TekColors.blue : scheme.outline;
    return Semantics(
      button: true,
      label: on ? 'disconnect' : 'connect',
      child: GestureDetector(
        onTap: _tap,
        onTapDown: (_) => _press(true),
        onTapUp: (_) => _press(false),
        onTapCancel: () => _press(false),
        child: SizedBox(
          width: size + 40,
          height: size + 40,
          child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(painter: _WavePainter(_waves, TekColors.blue, size / 2)),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              width: size + 40,
              height: size + 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: on ? TekColors.blue.withValues(alpha: 0.10) : Colors.transparent,
              ),
            ),
            if (_busy)
              AnimatedBuilder(
                animation: _spin,
                builder: (_, _) => Transform.rotate(
                  angle: _spin.value * 2 * pi,
                  child: CustomPaint(
                    size: Size.square(size + 14),
                    painter: _ArcPainter(TekColors.blue),
                  ),
                ),
              ),
            AnimatedScale(
              scale: _pressed ? 0.96 : 1,
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOut,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: on ? TekColors.blue : scheme.surface,
                  border: Border.all(color: ringColor, width: on ? 0 : 2),
                  boxShadow: [
                    if (on)
                      BoxShadow(
                          color: TekColors.blue.withValues(alpha: 0.35),
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
            ),
          ]),
        ),
      ),
    );
  }
}

/// The rings in flight: when each touch happened, on the ticker's clock.
class _Waves extends ChangeNotifier {
  static const rings = 3;
  static const ringGap = 0.28; // seconds between the rings of one touch
  static const life = 1.8; // seconds one ring takes to fade out

  final List<double> touches = [];
  double now = 0;
  VoidCallback? onIdle;

  void reset() {
    touches.clear();
    now = 0;
  }

  void touch() {
    touches.add(now);
    if (touches.length > 4) touches.removeAt(0);
  }

  void tick(Duration elapsed) {
    now = elapsed.inMicroseconds / 1e6;
    touches.removeWhere((t) => now - t > life + ringGap * (rings - 1));
    notifyListeners();
    if (touches.isEmpty) onIdle?.call();
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.waves, this.color, this.radius) : super(repaint: waves);
  final _Waves waves;
  final Color color;

  /// The button's radius: the rings start at its edge.
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (waves.touches.isEmpty) return;
    final center = size.center(Offset.zero);
    final paint = Paint()..style = PaintingStyle.stroke;
    for (final t0 in waves.touches) {
      for (var k = 0; k < _Waves.rings; k++) {
        final t = (waves.now - t0 - k * _Waves.ringGap) / _Waves.life;
        if (t <= 0 || t >= 1) continue;
        final spread = Curves.easeOutCubic.transform(t);
        final fade = (1 - t) * (1 - t);
        paint
          ..color = color.withValues(alpha: 0.45 * fade * (1 - k * 0.22))
          ..strokeWidth = 0.8 + 2.4 * (1 - spread);
        canvas.drawCircle(center, radius + 6 + spread * radius * 1.1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.waves != waves || old.color != color || old.radius != radius;
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
          color: TekColors.blue.withValues(alpha: 0.14),
        ),
        child: Icon(Icons.bolt_rounded, size: size * 0.62, color: TekColors.blue),
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
        painter: TekMarkPainter(color ?? TekColors.blue),
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

/// The small caps title above a card of settings.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.hint});
  final String title;

  /// A line under the title that says how the card works.
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title.toUpperCase(),
            style: TextStyle(
                fontSize: 12, letterSpacing: 0.8, fontWeight: FontWeight.w600, color: muted)),
        if (hint != null) ...[
          const SizedBox(height: 4),
          Text(hint!, style: TextStyle(fontSize: 13, height: 1.3, color: muted)),
        ],
      ]),
    );
  }
}

/// A round letter in place of an app icon.
class LetterIcon extends StatelessWidget {
  const LetterIcon(this.text, {super.key, this.size = 36});
  final String text;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final letter = text.isEmpty ? '?' : String.fromCharCode(text.runes.first).toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: scheme.surfaceContainerHighest),
      child: Text(letter,
          style: TextStyle(
              fontSize: size * 0.42, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
    );
  }
}
