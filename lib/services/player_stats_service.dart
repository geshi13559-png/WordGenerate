import 'package:shared_preferences/shared_preferences.dart';
import 'word_level_service.dart';

/// これまで見つけた単語の難易度から、プレイヤーのおおよその実力レベルを
/// 推定する（ラウンド終了後のヒント単語のレベル合わせに使う）
class PlayerStatsService {
  static const _prefsKey = 'found_word_level_indexes';
  static const _historyLimit = 300; // 際限なく増えないよう直近だけ保持

  SharedPreferences? _prefs;
  final List<int> _levelIndexes = [];

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    _levelIndexes
      ..clear()
      ..addAll(
        (_prefs!.getStringList(_prefsKey) ?? const [])
            .map(int.parse),
      );
  }

  Future<void> recordFoundWord(WordLevel level) async {
    if (level == WordLevel.unknown) return; // 不明レベルは平均に入れない
    _levelIndexes.add(level.index);
    if (_levelIndexes.length > _historyLimit) {
      _levelIndexes.removeRange(0, _levelIndexes.length - _historyLimit);
    }
    await _prefs?.setStringList(
      _prefsKey,
      _levelIndexes.map((e) => e.toString()).toList(),
    );
  }

  /// これまでの実績から見た、今のプレイヤーに合いそうなレベル
  /// （記録が無ければ「小学校・中1」相当から）
  WordLevel get averageLevel {
    if (_levelIndexes.isEmpty) return WordLevel.elementary;
    final avg =
        _levelIndexes.reduce((a, b) => a + b) / _levelIndexes.length;
    final rounded = avg.round().clamp(0, WordLevel.hs3plus.index);
    return WordLevel.values[rounded];
  }
}
