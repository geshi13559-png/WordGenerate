import 'package:flutter/services.dart';

/// 入力された単語が正しいかを判定する部品
class WordValidator {
  Set<String>? _dictionary;

  /// 辞書ファイルを読み込む（アプリ起動時に一度だけ呼ぶ）
  ///
  /// 英和辞書(ejdict.tsv)に載っている＝日本語の意味を説明できる単語だけを
  /// 正解として扱う。マイナーすぎて意味の説明がつかない単語や、
  /// 差別的な語（あらかじめejdict.tsvから除外済み）を正解にしないため。
  Future<void> loadDictionary() async {
    final raw = await rootBundle.loadString('assets/ejdict.tsv');
    final dictionary = <String>{};
    for (final line in raw.split('\n')) {
      final tabIndex = line.indexOf('\t');
      if (tabIndex == -1) continue;
      final word = line.substring(0, tabIndex).trim().toLowerCase();
      if (word.isNotEmpty) dictionary.add(word);
    }
    _dictionary = dictionary;
  }

  /// お題の文字だけで作れているか
  bool _usesOnlyGivenLetters(String word, List<String> letters) {
    final pool = [...letters.map((e) => e.toLowerCase())];
    for (final ch in word.toLowerCase().split('')) {
      final idx = pool.indexOf(ch);
      if (idx == -1) return false;
      pool.removeAt(idx);
    }
    return true;
  }

  /// 判定本体。「文字が正しい」かつ「辞書にある」でtrue
  bool validate(String word, List<String> letters) {
    final w = word.trim().toLowerCase();
    if (w.length < 2) return false;
    if (!_usesOnlyGivenLetters(w, letters)) return false;
    return _dictionary?.contains(w) ?? false;
  }
}