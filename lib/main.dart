import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/title_screen.dart';
import 'services/favorites_service.dart';
import 'services/player_stats_service.dart';
import 'services/supabase_config.dart';
import 'services/supabase_service.dart';
import 'services/translator.dart';
import 'services/word_level_service.dart';
import 'services/word_validator.dart';
import 'theme/wood_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Supabase接続（--dart-defineでURL/キーが渡されている時だけ初期化する）
  if (SupabaseConfig.isConfigured) {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.publishableKey,
    );
  }

  final validator = WordValidator();
  final translator = Translator();
  final favorites = FavoritesService();
  final wordLevels = WordLevelService();
  final playerStats = PlayerStatsService();
  final supabase = SupabaseService();
  await Future.wait([
    validator.loadDictionary(),
    translator.loadDictionary(),
    favorites.load(),
    wordLevels.load(),
    playerStats.load(),
  ]);
  runApp(WordBattleApp(
    validator: validator,
    translator: translator,
    favorites: favorites,
    wordLevels: wordLevels,
    playerStats: playerStats,
    supabase: supabase,
  ));
}

class WordBattleApp extends StatelessWidget {
  final WordValidator validator;
  final Translator translator;
  final FavoritesService favorites;
  final WordLevelService wordLevels;
  final PlayerStatsService playerStats;
  final SupabaseService supabase;
  const WordBattleApp({
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
    return MaterialApp(
      title: 'Word Battle',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: WoodColors.oakBase,
        fontFamily: 'Archivo',
      ),
      home: TitleScreen(
        validator: validator,
        translator: translator,
        favorites: favorites,
        wordLevels: wordLevels,
        playerStats: playerStats,
        supabase: supabase,
      ),
    );
  }
}
