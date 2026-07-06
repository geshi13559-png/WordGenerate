import 'package:flutter/material.dart';
import 'screens/title_screen.dart';
import 'services/favorites_service.dart';
import 'services/translator.dart';
import 'services/word_validator.dart';
import 'theme/wood_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final validator = WordValidator();
  final translator = Translator();
  final favorites = FavoritesService();
  await Future.wait([
    validator.loadDictionary(),
    translator.loadDictionary(),
    favorites.load(),
  ]);
  runApp(WordBattleApp(
    validator: validator,
    translator: translator,
    favorites: favorites,
  ));
}

class WordBattleApp extends StatelessWidget {
  final WordValidator validator;
  final Translator translator;
  final FavoritesService favorites;
  const WordBattleApp({
    super.key,
    required this.validator,
    required this.translator,
    required this.favorites,
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
      ),
    );
  }
}
