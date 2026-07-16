import 'package:flutter/material.dart';
import '../services/favorites_service.dart';
import '../services/player_stats_service.dart';
import '../services/supabase_service.dart';
import '../services/translator.dart';
import '../services/word_level_service.dart';
import '../services/word_validator.dart';
import '../theme/wood_theme.dart';
import 'game_screen.dart';
import 'online_lobby_screen.dart';

/// 「ゲーム」を押した後に出る対戦形式の選択画面
class GameModeScreen extends StatelessWidget {
  final WordValidator validator;
  final Translator translator;
  final FavoritesService favorites;
  final WordLevelService wordLevels;
  final PlayerStatsService playerStats;
  final SupabaseService supabase;
  const GameModeScreen({
    super.key,
    required this.validator,
    required this.translator,
    required this.favorites,
    required this.wordLevels,
    required this.playerStats,
    required this.supabase,
  });

  void _comingSoon(BuildContext context, String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label は準備中です。もうしばらくお待ちください。')),
    );
  }

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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back, color: WoodColors.ink),
                  ),
                  const SizedBox(height: 8),
                  const Eyebrow('GAME'),
                  const Text(
                    'あそびかたを選ぶ',
                    style: TextStyle(
                      fontFamily: 'Fraunces',
                      fontWeight: FontWeight.w900,
                      fontSize: 28,
                      color: WoodColors.ink,
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    child: WoodButton(
                      label: '1人で',
                      big: true,
                      primary: true,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => GameScreen(
                            validator: validator,
                            translator: translator,
                            favorites: favorites,
                            wordLevels: wordLevels,
                            playerStats: playerStats,
                            supabase: supabase,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: WoodButton(
                      label: '隣の友達と',
                      big: true,
                      onTap: () => _comingSoon(context, '「隣の友達と」対戦'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: WoodButton(
                      label: 'オンライン',
                      big: true,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => OnlineLobbyScreen(
                            translator: translator,
                            wordLevels: wordLevels,
                            favorites: favorites,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
