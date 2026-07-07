import 'package:flutter/services.dart';

/// 単語のおおよその学年レベル（CEFR-Jレベルを日本の学校段階に近似変換したもの）
///
/// 正式な文部科学省の学年別単語リストではなく、CEFR-J（東京外国語大学）の
/// レベルをもとにした近似区分。宣言順が易しい→難しいの並び順になっている。
enum WordLevel {
  elementary, // 小学校・中1相当（CEFR A1）
  ms23,       // 中2・中3相当（CEFR A2）
  hs12,       // 高1・高2相当（CEFR B1）
  hs3plus,    // 高3以上相当（CEFR B2）
  unknown,    // レベル不明（データに無い単語）
}

extension WordLevelLabel on WordLevel {
  String get label {
    switch (this) {
      case WordLevel.elementary:
        return '小学校・中1';
      case WordLevel.ms23:
        return '中2・中3';
      case WordLevel.hs12:
        return '高1・高2';
      case WordLevel.hs3plus:
        return '高3以上';
      case WordLevel.unknown:
        return 'レベル不明';
    }
  }
}

/// 単語レベルをどの「ものさし」で表示するか（中身のCEFR分類は共通で、
/// ラベルだけを試験ごとの公式対照表に基づいて表示する）
enum ExamFramework {
  grade, // 学校の学年
  eiken, // 英検
  toeic, // TOEIC L&R
  toefl, // TOEFL iBT
  ielts, // IELTS
}

extension ExamFrameworkLabel on ExamFramework {
  String get title {
    switch (this) {
      case ExamFramework.grade:
        return '学年';
      case ExamFramework.eiken:
        return '英検';
      case ExamFramework.toeic:
        return 'TOEIC';
      case ExamFramework.toefl:
        return 'TOEFL';
      case ExamFramework.ielts:
        return 'IELTS';
    }
  }

  /// 各試験の公式CEFR対照表をもとにした、レベルごとのおおよその目安ラベル
  String labelFor(WordLevel level) {
    switch (this) {
      case ExamFramework.grade:
        return level.label;
      case ExamFramework.eiken:
        switch (level) {
          case WordLevel.elementary:
            return '5級・4級';
          case WordLevel.ms23:
            return '3級・準2級';
          case WordLevel.hs12:
            return '2級';
          case WordLevel.hs3plus:
            return '準1級・1級';
          case WordLevel.unknown:
            return 'レベル不明';
        }
      case ExamFramework.toeic:
        switch (level) {
          case WordLevel.elementary:
            return '400点未満の目安';
          case WordLevel.ms23:
            return '400〜600点の目安';
          case WordLevel.hs12:
            return '600〜800点の目安';
          case WordLevel.hs3plus:
            return '800点以上の目安';
          case WordLevel.unknown:
            return 'レベル不明';
        }
      case ExamFramework.toefl:
        switch (level) {
          case WordLevel.elementary:
            return '基礎レベルの目安';
          case WordLevel.ms23:
            return '初級の目安';
          case WordLevel.hs12:
            return '中級の目安';
          case WordLevel.hs3plus:
            return '上級の目安';
          case WordLevel.unknown:
            return 'レベル不明';
        }
      case ExamFramework.ielts:
        switch (level) {
          case WordLevel.elementary:
            return 'バンド3前後の目安';
          case WordLevel.ms23:
            return 'バンド4前後の目安';
          case WordLevel.hs12:
            return 'バンド5〜5.5の目安';
          case WordLevel.hs3plus:
            return 'バンド6以上の目安';
          case WordLevel.unknown:
            return 'レベル不明';
        }
    }
  }
}

/// 単語→学年レベルを引く部品
class WordLevelService {
  Map<String, WordLevel>? _levels;

  Future<void> load() async {
    final raw = await rootBundle.loadString('assets/word_levels.tsv');
    final map = <String, WordLevel>{};
    for (final line in raw.split('\n')) {
      final tabIndex = line.indexOf('\t');
      if (tabIndex == -1) continue;
      final word = line.substring(0, tabIndex).trim().toLowerCase();
      final code = line.substring(tabIndex + 1).trim();
      final level = _fromCefrCode(code);
      if (word.isNotEmpty && level != null) map[word] = level;
    }
    _levels = map;
  }

  WordLevel? _fromCefrCode(String code) {
    switch (code) {
      case 'A1':
        return WordLevel.elementary;
      case 'A2':
        return WordLevel.ms23;
      case 'B1':
        return WordLevel.hs12;
      case 'B2':
        return WordLevel.hs3plus;
      default:
        return null;
    }
  }

  WordLevel levelOf(String word) =>
      _levels?[word.trim().toLowerCase()] ?? WordLevel.unknown;
}
