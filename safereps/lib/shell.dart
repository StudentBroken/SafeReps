import 'dart:io' show Platform;
import 'dart:math' show pi;
import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import 'models/goals_model.dart';
import 'pages/dashboard_page.dart';
import 'pages/goals_page.dart';
import 'pages/settings_page.dart';
import 'services/ble_service.dart';
import 'theme.dart';

// Floating pill height (content only, safe-area bottom added separately).
const double _kPillH = 60.0;

// Extra bottom margin between pill and safe-area edge.
const double _kPillBottomMargin = 14.0;

// Horizontal inset so the pill floats inside the screen edges.
const double _kPillHInset = 26.0;

/// Bottom padding pages should add to their scroll content so the last item
/// clears the floating nav pill. Does NOT include the system safe-area inset
/// (SafeArea / MediaQuery.padding.bottom handles that separately).
const double kNavPillClearance = _kPillH + _kPillBottomMargin + 8;

// ---------------------------------------------------------------------------

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  late final PageController _pc = PageController();

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  void _onNavTap(int i) {
    if (i == _index) return;
    setState(() => _index = i);
    _pc.animateToPage(
      i,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);

    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          PageView(
            controller: _pc,
            onPageChanged: (i) => setState(() => _index = i),
            children: const [
              DashboardPage(),
              GoalsPage(),
              SettingsPage(),
            ],
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _FloatingNav(
              index: _index,
              controller: _pc,
              onTap: _onNavTap,
              sysBottom: mq.padding.bottom,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Floating glass nav pill
// ---------------------------------------------------------------------------

const _kNavItems = [
  Icons.home_rounded,
  Icons.flag_rounded,
  Icons.settings_rounded,
];

class _FloatingNav extends StatelessWidget {
  const _FloatingNav({
    required this.index,
    required this.controller,
    required this.onTap,
    required this.sysBottom,
  });

  final int index;
  final PageController controller;
  final ValueChanged<int> onTap;
  final double sysBottom;

  static bool get _isIOS => !kIsWeb && Platform.isIOS;

  @override
  Widget build(BuildContext context) {
    final isIOS = _isIOS;
    final themeColors = AppTheme.colors(context);
    final radius = BorderRadius.circular(_kPillH / 2);

    return Padding(
      padding: EdgeInsets.fromLTRB(
          _kPillHInset, 0, _kPillHInset, _kPillBottomMargin + sysBottom),
      child: Container(
        height: _kPillH,
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            // Outer diffuse shadow — gives floating feel
            BoxShadow(
              color: Colors.black.withAlpha(isIOS ? 45 : 30),
              blurRadius: isIOS ? 28 : 18,
              spreadRadius: isIOS ? 4 : 2,
              offset: const Offset(0, 6),
            ),
            // iOS: secondary tight shadow for depth
            if (isIOS)
              BoxShadow(
                color: Colors.black.withAlpha(20),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ── Layer 1: heavy backdrop blur ──────────────────────────────
              BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: isIOS ? 48 : 28,
                  sigmaY: isIOS ? 48 : 28,
                ),
                // Base fill: near-transparent on iOS, themed tint on Android.
                child: Container(
                  color: isIOS
                      ? const Color(0x18FFFFFF)   // almost clear glass
                      : Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.7),
                ),
              ),

              // ── Layer 2: specular + caustic paint ─────────────────────────
              CustomPaint(painter: _LiquidGlassPainter(isIOS: isIOS, tint: themeColors.accent)),

              // ── Layer 2.5: sliding highlight bubble ───────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: _NavBubble(
                  index: index,
                  controller: controller,
                  isIOS: isIOS,
                ),
              ),

              // ── Layer 3: nav items ────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  children: List.generate(
                    _kNavItems.length,
                    (i) => Expanded(
                      child: _NavItem(
                        icon: _kNavItems[i],
                        selected: index == i,
                        onTap: () => onTap(i),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Liquid glass painter — specular + caustic + rim
// ---------------------------------------------------------------------------

class _LiquidGlassPainter extends CustomPainter {
  const _LiquidGlassPainter({required this.isIOS, required this.tint});
  final bool isIOS;
  final Color tint;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.height / 2;
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(r));

    if (isIOS) {
      _paintIOS(canvas, size, rect, rrect, r);
    } else {
      _paintAndroid(canvas, size, rect, rrect, r);
    }
  }

  void _paintIOS(
      Canvas canvas, Size size, Rect rect, RRect rrect, double r) {
    // ── Caustic inner glow ────────────────────────
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0.0, 1.4),
          radius: 1.0,
          colors: [
            tint.withValues(alpha: 0.1), // themed caustic light
            const Color(0x00FFFFFF),
          ],
        ).createShader(rect),
    );

    // ── Top specular highlight ──────────────────
    final specH = size.height * 0.52;
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(0, 0, size.width, specH),
        topLeft: Radius.circular(r),
        topRight: Radius.circular(r),
      ),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0.0, 0.45, 1.0],
          colors: [
            const Color(0xAAFFFFFF),
            const Color(0x28FFFFFF),
            const Color(0x00FFFFFF),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, specH)),
    );

    // ── Rim ─────────────────
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..shader = SweepGradient(
          center: Alignment.center,
          startAngle: -pi / 2,
          endAngle: 3 * pi / 2,
          colors: const [
            Color(0xCCFFFFFF), // top — bright specular
            Color(0x55FFFFFF), // right
            Color(0x22FFFFFF), // bottom
            Color(0x55FFFFFF), // left
            Color(0xCCFFFFFF), // back to top
          ],
        ).createShader(rect),
    );

    // ── Inner rim ────────────────
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect.deflate(1.0),
        Radius.circular(r - 1),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5
        ..color = const Color(0x18FFFFFF),
    );
  }

  void _paintAndroid(
      Canvas canvas, Size size, Rect rect, RRect rrect, double r) {
    // ── Soft top specular ──────────────────────────────────────────────────
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(0, 0, size.width, size.height * 0.55),
        topLeft: Radius.circular(r),
        topRight: Radius.circular(r),
      ),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0x70FFFFFF),
            const Color(0x00FFFFFF),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height * 0.55)),
    );

    // ── Themed bottom glow ───────────────────────────────────────────────────
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0.0, 1.2),
          radius: 0.9,
          colors: [
            tint.withValues(alpha: 0.15), // soft themed warmth
            tint.withValues(alpha: 0.0),
          ],
        ).createShader(rect),
    );

    // ── Rim: uniform soft white stroke ────────────────────────────────────
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = const Color(0x80FFFFFF),
    );
  }

  @override
  bool shouldRepaint(_LiquidGlassPainter old) => old.isIOS != isIOS || old.tint != tint;
}

class _NavBubble extends StatelessWidget {
  const _NavBubble({
    required this.index,
    required this.controller,
    required this.isIOS,
  });

  final int index;
  final PageController controller;
  final bool isIOS;

  @override
  Widget build(BuildContext context) {
    final subPillColor = isIOS
        ? const Color(0x50FFFFFF)
        : Theme.of(context).colorScheme.primary.withValues(alpha: 0.25);

    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        double page = index.toDouble();
        if (controller.hasClients) {
          try {
            page = controller.page ?? index.toDouble();
          } catch (_) {
            // .page can throw if not yet laid out
          }
        }

        return Align(
          alignment: Alignment(-1.0 + (page * 1.0), 0),
          child: child,
        );
      },
      child: FractionallySizedBox(
        widthFactor: 1 / _kNavItems.length,
        child: Center(
          child: Container(
            width: 64,
            height: 44,
            decoration: BoxDecoration(
              color: subPillColor,
              borderRadius: BorderRadius.circular(20),
              border: isIOS
                  ? Border.all(color: const Color(0x44FFFFFF), width: 0.7)
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Nav item
// ---------------------------------------------------------------------------

class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press;

  @override
  void initState() {
    super.initState();
    _press = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
      reverseDuration: const Duration(milliseconds: 220),
    );
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) => _press.forward();
  void _onTapUp(TapUpDetails _) {
    _press.reverse();
    HapticFeedback.selectionClick();
    widget.onTap();
  }
  void _onTapCancel() => _press.reverse();

  @override
  Widget build(BuildContext context) {
    final themeColors = AppTheme.colors(context);
    final iconColor =
        widget.selected ? Theme.of(context).colorScheme.primary : themeColors.textDark.withValues(alpha: 0.5);

    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _press,
        builder: (context, child) => Transform.scale(
          scale: 1.0 - _press.value * 0.11,
          child: child,
        ),
        child: Center(
          child: AnimatedScale(
            scale: widget.selected ? 1.2 : 1.0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutBack,
            child: Icon(widget.icon, size: 28, color: iconColor),
          ),
        ),
      ),
    );
  }
}
