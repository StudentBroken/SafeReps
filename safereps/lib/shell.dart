import 'dart:io' show Platform;
import 'dart:math' show pi;
import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'models/goals_model.dart';
import 'pages/dashboard_page.dart';
import 'pages/goals_page.dart';
import 'pages/settings_page.dart';
import 'theme.dart';

// Floating pill height (content only, safe-area bottom added separately).
const double _kPillH = 60.0;

// Extra bottom margin between pill and safe-area edge.
const double _kPillBottomMargin = 14.0;

// Horizontal inset so the pill floats inside the screen edges.
const double _kPillHInset = 26.0;

// ---------------------------------------------------------------------------

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  final _goals = GoalsModel();

  @override
  void initState() {
    super.initState();
    _goals.load();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    // Tell SafeArea inside pages to reserve space for the floating pill.
    final bodyPaddingBottom =
        mq.padding.bottom + _kPillH + _kPillBottomMargin + 8;

    return GoalsScope(
      model: _goals,
      child: Scaffold(
        backgroundColor: AppColors.background,
        extendBody: true,
        // No bottomNavigationBar — the nav is a Stack overlay inside the body,
        // which lets BackdropFilter see and blur the live page content behind it.
        body: MediaQuery(
          data: mq.copyWith(
            padding: mq.padding.copyWith(bottom: bodyPaddingBottom),
          ),
          child: Stack(
            children: [
              IndexedStack(
                index: _index,
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
                  onTap: (i) => setState(() => _index = i),
                  sysBottom: mq.padding.bottom,
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
// Floating glass nav pill
// ---------------------------------------------------------------------------

const _kNavItems = [
  (icon: Icons.home_rounded, label: 'Dashboard'),
  (icon: Icons.flag_rounded, label: 'Goals'),
  (icon: Icons.settings_rounded, label: 'Settings'),
];

class _FloatingNav extends StatelessWidget {
  const _FloatingNav({
    required this.index,
    required this.onTap,
    required this.sysBottom,
  });

  final int index;
  final ValueChanged<int> onTap;
  final double sysBottom;

  static bool get _isIOS => !kIsWeb && Platform.isIOS;

  @override
  Widget build(BuildContext context) {
    final isIOS = _isIOS;
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
                // Base fill: near-transparent on iOS, warm tint on Android.
                child: Container(
                  color: isIOS
                      ? const Color(0x18FFFFFF)   // almost clear glass
                      : const Color(0xB2F0E6DC),  // warm frosted beige
                ),
              ),

              // ── Layer 2: specular + caustic paint ─────────────────────────
              CustomPaint(painter: _LiquidGlassPainter(isIOS: isIOS)),

              // ── Layer 3: nav items ────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  children: List.generate(
                    _kNavItems.length,
                    (i) => Expanded(
                      child: _NavItem(
                        icon: _kNavItems[i].icon,
                        label: _kNavItems[i].label,
                        selected: index == i,
                        isIOS: isIOS,
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
  const _LiquidGlassPainter({required this.isIOS});
  final bool isIOS;

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
    // ── Caustic inner glow: warmer at bottom-centre ────────────────────────
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0.0, 1.4),
          radius: 1.0,
          colors: [
            const Color(0x18FFF4E0), // warm caustic light
            const Color(0x00FFFFFF),
          ],
        ).createShader(rect),
    );

    // ── Top specular highlight: bright white fading down ──────────────────
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

    // ── Rim: sweep gradient stroke (brighter at top-left) ─────────────────
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

    // ── Inner rim: very subtle second highlight just inside ────────────────
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

    // ── Warm bottom glow ───────────────────────────────────────────────────
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0.0, 1.2),
          radius: 0.9,
          colors: [
            const Color(0x20F2AFC4), // soft pink warmth
            const Color(0x00F2AFC4),
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
  bool shouldRepaint(_LiquidGlassPainter old) => old.isIOS != isIOS;
}

// ---------------------------------------------------------------------------
// Nav item
// ---------------------------------------------------------------------------

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.isIOS,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool isIOS;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final iconColor = selected ? AppColors.pinkBright : const Color(0x88000000);
    final labelColor = selected ? AppColors.pinkBright : const Color(0x66000000);

    // Selection sub-pill:
    //   iOS  → white glass sub-pill (mimics iOS 18 tab indicator)
    //   Droid → warm pink-tinted sub-pill
    final subPillColor = selected
        ? (isIOS
            ? const Color(0x55FFFFFF)
            : const Color(0x35D6176E))
        : Colors.transparent;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 270),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: subPillColor,
            borderRadius: BorderRadius.circular(24),
            // iOS sub-pill gets its own micro specular rim
            border: (isIOS && selected)
                ? Border.all(color: const Color(0x40FFFFFF), width: 0.6)
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                scale: selected ? 1.1 : 1.0,
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutBack,
                child: Icon(icon, size: 21, color: iconColor),
              ),
              const SizedBox(height: 2),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: TextStyle(
                  color: labelColor,
                  fontSize: 10,
                  fontWeight:
                      selected ? FontWeight.w700 : FontWeight.w500,
                  letterSpacing: selected ? 0.1 : 0,
                ),
                child: Text(label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
