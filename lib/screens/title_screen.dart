import 'package:flutter/material.dart';
import '../services/favorites_service.dart';
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
  const TitleScreen({
    super.key,
    required this.validator,
    required this.translator,
    required this.favorites,
    required this.wordLevels,
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
