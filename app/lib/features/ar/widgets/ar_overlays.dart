import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Kid-friendly copy for the AR screen (hiragana first, SPEC §0).
abstract final class ArStrings {
  static const findPlane = 'ゆかや つくえを うつしてね';
  static const findPlaneSub = 'スマホを ゆっくり うごかしてね';
  static const tapToPlace = 'ゆかを タッチして キャラを おこう！';
  static const gestureTip = 'ゆび 2ほんで おおきさ・むきを かえられるよ';
  static const tooDark = 'すこし くらいみたい。あかるい ところで うつしてね';
  static const tooFast = 'ゆっくり うごかしてね';
  static const noTexture = 'もようの ある ところを うつしてね';
  static const preparing = 'じゅんび ちゅう…';
  static const saved = 'しゃしんを ほぞんしたよ！';
  static const saveFailed = 'しゃしんを ほぞんできなかったよ';
  static const saveNoPermission = 'しゃしんを ほぞんするには きょかが いるよ';
  static const saveNoSpace = 'スマホの ようりょうが いっぱいみたい';
  static const cameraNeeded = 'AR で あそぶには カメラを つかうよ';
  static const cameraAskAgain = 'もういちど きく';
  static const openSettings = 'せっていを ひらく（おうちのひと）';
  static const switchedToSimple = 'かんたん AR に きりかえたよ';
  static const simpleAr = 'かんたん AR';
  static const realAr = 'AR';
  static const simpleHint = 'ゆびで うごかしたり、2ほんで おおきさを かえてね';
  static const installTitle =
      'ほんものの AR を つかうには、'
      'Google の アプリ（Google Play 開発者サービス for AR）が いるよ';
  static const installYes = 'おうちのひとと いれる';
  static const installNo = 'かんたん AR で あそぶ';
  static const imageError = 'キャラの えが よみこめなかったよ';
  static const back = 'もどる';
  static const shutter = 'しゃしんを とる';
}

/// Large rounded hint bubble shown over the camera.
class ArHintBubble extends StatelessWidget {
  const ArHintBubble({super.key, required this.text, this.subText, this.icon});

  final String text;
  final String? subText;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(
              blurRadius: 12,
              color: Colors.black26,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ?icon,
            Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: const Color(0xFF333333),
              ),
            ),
            if (subText != null) ...[
              const SizedBox(height: 4),
              Text(
                subText!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF666666),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Animated phone icon sweeping left/right ("move your phone slowly").
class ScanAnimation extends StatefulWidget {
  const ScanAnimation({super.key});

  @override
  State<ScanAnimation> createState() => _ScanAnimationState();
}

class _ScanAnimationState extends State<ScanAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) => Transform.translate(
          offset: Offset(28 * math.sin(2 * math.pi * _c.value), 0),
          child: Transform.rotate(
            angle: 0.25 * math.sin(2 * math.pi * _c.value),
            child: child,
          ),
        ),
        child: const Icon(
          Icons.phone_android,
          size: 44,
          color: Color(0xFF4A90E2),
        ),
      ),
    );
  }
}

/// Round shutter button.
class ShutterButton extends StatelessWidget {
  const ShutterButton({super.key, required this.onPressed, this.busy = false});

  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    return Semantics(
      button: true,
      label: ArStrings.shutter,
      child: GestureDetector(
        onTap: enabled ? onPressed : null,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: enabled ? 1 : 0.5,
          child: Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(color: const Color(0xFFFF8A3D), width: 6),
              boxShadow: const [
                BoxShadow(blurRadius: 10, color: Colors.black38),
              ],
            ),
            child: busy
                ? const Padding(
                    padding: EdgeInsets.all(22),
                    child: CircularProgressIndicator(strokeWidth: 4),
                  )
                : const Icon(
                    Icons.camera_alt_rounded,
                    size: 40,
                    color: Color(0xFFFF8A3D),
                  ),
          ),
        ),
      ),
    );
  }
}

/// White flash after taking a picture.
class ShutterFlash extends StatelessWidget {
  const ShutterFlash({super.key, required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: visible ? 0.85 : 0,
        duration: Duration(milliseconds: visible ? 40 : 350),
        child: const ColoredBox(color: Colors.white),
      ),
    );
  }
}

/// Circular translucent icon button (back, mode switch).
class ArRoundButton extends StatelessWidget {
  const ArRoundButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Material(
        color: Colors.black.withValues(alpha: 0.4),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Icon(
              icon,
              color: Colors.white,
              size: 30,
              semanticLabel: label,
            ),
          ),
        ),
      ),
    );
  }
}
