import 'dart:math';
import 'package:flutter/material.dart';

/// 明るいオーク材フローリング × インクブルー1色のカラーパレット
class WoodColors {
  static const oakHi = Color(0xFFF2DDAB);     // 板の明るいハイライト
  static const oakBase = Color(0xFFDDBC7C);   // 床のベース色
  static const oakMid = Color(0xFFC39A55);    // 板の陰側
  static const oakGroove = Color(0xFF8A5F2D); // 継ぎ目・木口の濃い色
  static const ink = Color(0xFF172444);       // アクセントのインクブルー
  static const inkSoft = Color(0xFF2F4576);
  static const paper = Color(0xFFFBF3DF);     // インクの上に乗る明るい文字色
  static const amber = Color(0xFFB5722A);     // 残り15秒
  static const amberSoft = Color(0xFFC98A3A);
  static const danger = Color(0xFFAC3A2E);    // 残り10秒・5秒
  static const dangerSoft = Color(0xFFC9503F);
}

/// 見出し用の小さなラベル（大文字・字間広め）
class Eyebrow extends StatelessWidget {
  final String text;
  final Color color;
  const Eyebrow(this.text, {super.key, this.color = WoodColors.ink});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontFamily: 'Archivo',
        fontWeight: FontWeight.w700,
        fontSize: 11,
        letterSpacing: 2,
        color: color.withValues(alpha: 0.6),
      ),
    );
  }
}

/// ボタン（primary＝インク塗り／それ以外＝木の色）
class WoodButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool big;
  final bool primary;
  const WoodButton({
    super.key,
    required this.label,
    required this.onTap,
    this.big = false,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: disabled ? 0.45 : 1.0,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: big ? 30 : 18,
            vertical: big ? 15 : 11,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: primary
                  ? const [WoodColors.inkSoft, WoodColors.ink]
                  : const [WoodColors.oakHi, WoodColors.oakMid],
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: (primary ? WoodColors.ink : WoodColors.oakGroove)
                    .withValues(alpha: 0.45),
                offset: const Offset(0, 3),
                blurRadius: 6,
              ),
            ],
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: big ? 17 : 14,
              fontWeight: FontWeight.w700,
              color: primary ? WoodColors.paper : WoodColors.ink,
            ),
          ),
        ),
      ),
    );
  }
}

/// 床：板目フローリングを描くCustomPainter
/// 固定シードで生成するため、同じサイズなら毎回同じ板目になり、
/// 再描画してもレイアウトが揺れない。
class FloorPainter extends CustomPainter {
  const FloorPainter();

  static const _plankTones = [
    [Color(0xFFF0DEAE), Color(0xFFE2C88C)],
    [Color(0xFFE6CD93), Color(0xFFD6B473)],
    [Color(0xFFDCC086), Color(0xFFC9A565)],
    [Color(0xFFEAD6A6), Color(0xFFDCBD82)],
    [Color(0xFFD8B878), Color(0xFFC7A05F)],
    [Color(0xFFE9D29C), Color(0xFFD9BB7E)],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random(1337);
    double y = 0;
    int prevTone = -1;

    while (y < size.height) {
      var plankH = 64 + rng.nextDouble() * 28;
      if (y + plankH > size.height) plankH = size.height - y;

      int toneIdx;
      do {
        toneIdx = rng.nextInt(_plankTones.length);
      } while (toneIdx == prevTone && _plankTones.length > 1);
      prevTone = toneIdx;
      final tone = _plankTones[toneIdx];

      final rect = Rect.fromLTWH(0, y, size.width, plankH);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: tone,
          ).createShader(rect),
      );

      // 板内部の木目（横方向の筋。長さ・濃さ・わずかなカーブをランダムに）
      final grainCount = (plankH / 6).round();
      for (var i = 0; i < grainCount; i++) {
        final gy = y + 3 + rng.nextDouble() * (plankH - 6);
        final len = size.width * (0.35 + rng.nextDouble() * 0.65);
        final gx = -20 + rng.nextDouble() * (size.width - len + 20);
        final path = Path()..moveTo(gx, gy);
        path.cubicTo(
          gx + len * 0.33,
          gy + (rng.nextDouble() * 2.8 - 1.4),
          gx + len * 0.66,
          gy + (rng.nextDouble() * 2.8 - 1.4),
          gx + len,
          gy,
        );
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.6 + rng.nextDouble() * 0.8
            ..color = const Color(0xFF6E4820)
                .withValues(alpha: 0.05 + rng.nextDouble() * 0.11),
        );
      }

      // たまに節目（ノット）を入れる
      if (rng.nextDouble() < 0.35) {
        final kx = size.width * (0.15 + rng.nextDouble() * 0.7);
        final ky = y + plankH / 2 + (rng.nextDouble() * 12 - 6);
        for (var r = 7.0; r > 0; r -= 2.5) {
          canvas.drawOval(
            Rect.fromCenter(center: Offset(kx, ky), width: r * 2, height: r * 1.1),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1
              ..color = const Color(0xFF5A3716)
                  .withValues(alpha: (0.16 - r * 0.01).clamp(0.0, 1.0)),
          );
        }
      }

      // 上端のわずかなハイライト（光沢）
      canvas.drawRect(
        Rect.fromLTWH(0, y, size.width, 2),
        Paint()..color = const Color(0xFFFFF8DE).withValues(alpha: 0.10),
      );

      // 継ぎ目の溝（濃い影 + すぐ下に明るいライン）
      final seamY = y + plankH;
      if (seamY < size.height) {
        canvas.drawRect(
          Rect.fromLTWH(0, seamY - 1, size.width, 1.6),
          Paint()..color = const Color(0xFF462C12).withValues(alpha: 0.55),
        );
        canvas.drawRect(
          Rect.fromLTWH(0, seamY + 0.6, size.width, 1),
          Paint()..color = const Color(0xFFFFF7DE).withValues(alpha: 0.30),
        );
      }

      y += plankH;
    }
  }

  @override
  bool shouldRepaint(covariant FloorPainter oldDelegate) => false;
}

/// 板目フローリングの背景。各画面の一番下に敷く共通ウィジェット。
class WoodFloorBackground extends StatelessWidget {
  const WoodFloorBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return const Positioned.fill(
      child: RepaintBoundary(child: CustomPaint(painter: FloorPainter())),
    );
  }
}
