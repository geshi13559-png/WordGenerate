import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import '../theme/wood_theme.dart';

/// ランキング画面：全プレイヤーをレートの高い順に並べて表示する。
/// players テーブルを読むだけ（対戦機能はまだ無く、レートは初期値1200のまま）。
class RankingScreen extends StatefulWidget {
  final SupabaseService supabase;
  const RankingScreen({super.key, required this.supabase});

  @override
  State<RankingScreen> createState() => _RankingScreenState();
}

class _RankingScreenState extends State<RankingScreen> {
  late Future<List<Player>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.supabase.fetchRanking();
  }

  Future<void> _reload() async {
    setState(() => _future = widget.supabase.fetchRanking());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    final myId = widget.supabase.currentPlayer?.id;

    return Scaffold(
      body: Stack(
        children: [
          const WoodFloorBackground(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back, color: WoodColors.ink),
                      ),
                      const Eyebrow('HIGH SCORE'),
                      const Spacer(),
                      IconButton(
                        onPressed: _reload,
                        icon: const Icon(Icons.refresh, color: WoodColors.ink),
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.only(left: 8, bottom: 2),
                    child: Text(
                      'ハイスコアランキング',
                      style: TextStyle(
                        fontFamily: 'Fraunces',
                        fontWeight: FontWeight.w900,
                        fontSize: 24,
                        color: WoodColors.ink,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 8, bottom: 12),
                    child: Text(
                      '1人プレイの自己ベストで競おう',
                      style: TextStyle(
                        fontSize: 12,
                        color: WoodColors.ink.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                  Expanded(
                    child: FutureBuilder<List<Player>>(
                      future: _future,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(
                              color: WoodColors.ink,
                            ),
                          );
                        }
                        final players = snapshot.data ?? const <Player>[];
                        if (players.isEmpty) {
                          return Center(
                            child: Text(
                              widget.supabase.isEnabled
                                  ? 'まだプレイヤーがいません'
                                  : 'オフラインのため表示できません',
                              style: TextStyle(
                                color: WoodColors.ink.withValues(alpha: 0.6),
                              ),
                            ),
                          );
                        }
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: ListView.separated(
                            itemCount: players.length,
                            separatorBuilder: (_, _) => Container(
                              height: 1,
                              color: WoodColors.oakHi.withValues(alpha: 0.35),
                            ),
                            itemBuilder: (context, i) {
                              final tone = FloorPainter
                                  .plankTones[i % FloorPainter.plankTones.length];
                              return _RankingRow(
                                rank: i + 1,
                                player: players[i],
                                isMe: players[i].id == myId,
                                toneTop: tone[0],
                                toneBottom: tone[1],
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ランキング1行＝床板1枚のカード（辞書画面と同じ木目カード方式）。
class _RankingRow extends StatelessWidget {
  static const height = 62.0;

  final int rank;
  final Player player;
  final bool isMe;
  final Color toneTop;
  final Color toneBottom;
  const _RankingRow({
    required this.rank,
    required this.player,
    required this.isMe,
    required this.toneTop,
    required this.toneBottom,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [toneTop, toneBottom],
        ),
        border: Border(
          bottom: BorderSide(
            color: WoodColors.oakGroove.withValues(alpha: 0.55),
            width: 1.6,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 順位（上位3位はメダル色の丸バッジ）
          _RankBadge(rank: rank),
          const SizedBox(width: 12),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    player.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Fraunces',
                      fontWeight: FontWeight.w700,
                      fontSize: 17,
                      color: WoodColors.ink,
                    ),
                  ),
                ),
                if (isMe)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: WoodColors.ink,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'あなた',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: WoodColors.paper,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // ハイスコアとプレイ回数
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${player.bestScore}',
                    style: const TextStyle(
                      fontFamily: 'Archivo',
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                      color: WoodColors.ink,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 2),
                  Text(
                    '点',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: WoodColors.ink.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
              Text(
                player.gamesPlayed > 0 ? '${player.gamesPlayed}回プレイ' : '記録なし',
                style: TextStyle(
                  fontSize: 11,
                  color: WoodColors.ink.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 順位バッジ。1〜3位は金・銀・銅の丸、それ以外は「#4」のような小さな数字。
class _RankBadge extends StatelessWidget {
  final int rank;
  const _RankBadge({required this.rank});

  @override
  Widget build(BuildContext context) {
    const medals = {
      1: Color(0xFFC9A227), // 金
      2: Color(0xFF9AA0A6), // 銀
      3: Color(0xFFB5722A), // 銅
    };
    final medal = medals[rank];
    if (medal != null) {
      return Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: medal,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: WoodColors.oakGroove.withValues(alpha: 0.4),
              offset: const Offset(0, 1),
              blurRadius: 3,
            ),
          ],
        ),
        child: Text(
          '$rank',
          style: const TextStyle(
            fontFamily: 'Archivo',
            fontWeight: FontWeight.w900,
            fontSize: 15,
            color: WoodColors.paper,
          ),
        ),
      );
    }
    return SizedBox(
      width: 30,
      child: Text(
        '$rank',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'Archivo',
          fontWeight: FontWeight.w700,
          fontSize: 14,
          color: WoodColors.ink.withValues(alpha: 0.55),
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
