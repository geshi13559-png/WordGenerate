import 'package:shared_preferences/shared_preferences.dart';

/// お気に入り単語の永続保存（端末内、オフラインで完結）
class FavoritesService {
  static const _prefsKey = 'favorite_words';

  SharedPreferences? _prefs;
  final Set<String> _favorites = {};

  Set<String> get favorites => Set.unmodifiable(_favorites);

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    _favorites
      ..clear()
      ..addAll(_prefs!.getStringList(_prefsKey) ?? const []);
  }

  bool isFavorite(String word) => _favorites.contains(word.trim().toLowerCase());

  Future<void> toggle(String word) async {
    final w = word.trim().toLowerCase();
    if (_favorites.contains(w)) {
      _favorites.remove(w);
    } else {
      _favorites.add(w);
    }
    await _prefs?.setStringList(_prefsKey, _favorites.toList());
  }
}
