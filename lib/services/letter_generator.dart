import 'dart:math';

/// お題のアルファベットを生成する部品
class LetterGenerator {
  final Random _rng = Random();

  // よく使われる文字ほど多く入れて、単語を作りやすくする
  static const _weighted =
      'eeeeeeeeeeeetttttttttttaaaaaaaaaooooooooiiiiiiinnnnnnn'
      'sssssssrrrrrrhhhhhhddddllllccccuuuummmm'
      'wwffggyypbvkjxqz';

  static const _vowels = 'aeiou';
  static const _maxPerVowel = 2; // 同じ母音は2個まで

  /// count個のアルファベットを返す
  /// ・母音を2つ以上保証（ただし同じ母音は2個まで）
  /// ・qが入る場合は必ずuも入るようにする（qだけでは単語が作れないため）
  List<String> generate({int count = 7}) {
    final result = <String>[];

    bool canAdd(String ch) {
      if (!_vowels.contains(ch)) return true;
      return result.where((c) => c == ch).length < _maxPerVowel;
    }

    // まず母音を2つ保証する（種類はランダム、同じ母音への偏りは抑える）
    while (result.where((c) => _vowels.contains(c)).length < 2) {
      final v = _vowels[_rng.nextInt(_vowels.length)];
      if (canAdd(v)) result.add(v);
    }

    // 残りを重み付き候補から埋める（母音は上限を超えたら引き直す）
    while (result.length < count) {
      final ch = _weighted[_rng.nextInt(_weighted.length)];
      if (canAdd(ch)) result.add(ch);
    }

    // qがあるのにuが無ければ、q以外の子音1文字をuに置き換える
    if (result.contains('q') && !result.contains('u')) {
      final replaceable = [
        for (var i = 0; i < result.length; i++)
          if (!_vowels.contains(result[i]) && result[i] != 'q') i
      ];
      if (replaceable.isNotEmpty) {
        result[replaceable[_rng.nextInt(replaceable.length)]] = 'u';
      }
    }

    result.shuffle(_rng);
    return result;
  }
}