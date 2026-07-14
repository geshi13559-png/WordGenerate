import 'package:flutter/material.dart';
import '../services/favorites_service.dart';
import '../services/player_stats_service.dart';
import '../services/supabase_service.dart';
import '../services/translator.dart';
import '../services/word_level_service.dart';
import '../services/word_validator.dart';
import '../theme/wood_theme.dart';
import 'dictionary_screen.dart';
import 'game_mode_screen.dart';

/// アプリを開いて最初に出るタイトル画面（ゲーム／辞書の入口）
class TitleScreen extends StatelessWidget {
  final WordValidator validator;
  final Translator translator;
  final FavoritesService favorites;
  final WordLevelService wordLevels;
  final PlayerStatsService playerStats;
  final SupabaseService supabase;
  const TitleScreen({
    super.key,
    required this.validator,
    required this.translator,
    required this.favorites,
    required this.wordLevels,
    required this.playerStats,
    required this.supabase,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const WoodFloorBackground(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Word\nBattle',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Fraunces',
                      fontWeight: FontWeight.w900,
                      fontSize: 52,
                      height: 1.05,
                      color: WoodColors.ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '木目の盤で単語をつくろう',
                    style: TextStyle(
                      fontFamily: 'Fraunces',
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w500,
                      fontSize: 16,
                      color: WoodColors.ink.withValues(alpha: 0.65),
                    ),
                  ),
                  const SizedBox(height: 56),
                  SizedBox(
                    width: double.infinity,
                    child: WoodButton(
                      label: 'ゲーム',
                      big: true,
                      primary: true,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => GameModeScreen(
                            validator: validator,
                            translator: translator,
                            favorites: favorites,
                            wordLevels: wordLevels,
                            playerStats: playerStats,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: WoodButton(
                      label: '辞書',
                      big: true,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => DictionaryScreen(
                            translator: translator,
                            favorites: favorites,
                            wordLevels: wordLevels,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  _ConnectionBadge(supabase: supabase),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// タイトル画面下部に出す、Supabaseへの接続状態バッジ
class _ConnectionBadge extends StatelessWidget {
  final SupabaseService supabase;
  const _ConnectionBadge({required this.supabase});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SupabaseConnectionStatus>(
      future: supabase.checkConnection(),
      builder: (context, snapshot) {
        final status = snapshot.data;

        late final IconData icon;
        late final String label;
        late final Color color;

        if (status == null) {
          icon = Icons.sync;
          label = 'サーバー接続を確認中…';
          color = WoodColors.ink.withValues(alpha: 0.5);
        } else {
          switch (status) {
            case SupabaseConnectionStatus.connected:
              icon = Icons.cloud_done;
              label = 'サーバーに接続済み';
              color = WoodColors.inkSoft;
            case SupabaseConnectionStatus.notConfigured:
              icon = Icons.cloud_off;
              label = 'オフライン（接続情報なし）';
              color = WoodColors.ink.withValues(alpha: 0.45);
            case SupabaseConnectionStatus.failed:
              icon = Icons.error_outline;
              label = 'サーバーに接続できません';
              color = WoodColors.danger;
          }
        }

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        );
      },
    );
  }
}
