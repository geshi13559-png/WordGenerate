import 'dart:math';

/// お題のアルファベットを生成する部品
class LetterGenerator {
  final Random _rng = Random();

  // よく使われる文字ほど多く入れて、単語を作りやすくする
  static const _weighted =
      'eeeeeeeeeeeetttttttttttaaaaaaaaaooooooooiiiiiiinnnnnnn'
      'sssssssrrrrrrhhhhhhddddllllccccuuuummmm'
      'wwffggyypbvkjxqz';

  /// count個のアルファベットを返す（母音を2つ以上保証）
  List<String> generate({int count = 7}) {
    const vowels = 'aeiou';
    final result = <String>[];

    for (var i = 0; i < 2; i++) {
      result.add(vowels[_rng.nextInt(vowels.length)]);
    }
    while (result.length < count) {
      result.add(_weighted[_rng.nextInt(_weighted.length)]);
    }
    result.shuffle(_rng);
    return result;
  }
}