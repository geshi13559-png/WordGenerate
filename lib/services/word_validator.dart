import 'package:flutter/services.dart';

/// 入力された単語が正しいかを判定する部品
class WordValidator {
  Set<String>? _dictionary;

  /// 辞書ファイルを読み込む（アプリ起動時に一度だけ呼ぶ）
  Future<void> loadDictionary() async {
    final raw = await rootBundle.loadString('assets/words.txt');
    _dictionary = raw
        .split('\n')
        .map((w) => w.trim().toLowerCase())
        .where((w) => w.isNotEmpty)
        .toSet();
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