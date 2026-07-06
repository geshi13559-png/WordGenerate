import 'package:flutter/services.dart';

/// 英単語の日本語訳を引く部品
class Translator {
  Map<String, String>? _dict;

  /// 辞書ファイルを読み込む（アプリ起動時に一度だけ呼ぶ）
  Future<void> loadDictionary() async {
    final raw = await rootBundle.loadString('assets/ejdict.tsv');
    final dict = <String, String>{};
    for (final line in raw.split('\n')) {
      final tabIndex = line.indexOf('\t');
      if (tabIndex == -1) continue;
      final word = line.substring(0, tabIndex).trim().toLowerCase();
      final meaning = line.substring(tabIndex + 1).trim();
      if (word.isEmpty || meaning.isEmpty) continue;
      dict[word] = meaning;
    }
    _dict = dict;
  }

  /// 単語の日本語訳を返す。見つからなければnull
  String? translate(String word) => _dict?[word.trim().toLowerCase()];
}
