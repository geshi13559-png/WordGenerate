import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../services/favorites_service.dart';
import '../services/translator.dart';
import '../services/word_level_service.dart';
import '../theme/wood_theme.dart';

/// 辞書画面：全単語の閲覧・検索・お気に入り登録・学年レベル絞り込み
class DictionaryScreen extends StatefulWidget {
  final Translator translator;
  final FavoritesService favorites;
  final WordLevelService wordLevels;
  const DictionaryScreen({
    super.key,
    required this.translator,
    required this.favorites,
    required this.wordLevels,
  });

  @override
  State<DictionaryScreen> createState() => _DictionaryScreenState();
}

class _DictionaryScreenState extends State<DictionaryScreen> {
  // 易しい→難しいの順（易しい単語を上に出すため）
  late final List<MapEntry<String, String>> _allEntries;
  String _query = '';
  bool _favoritesOnly = false;
  final Set<WordLevel> _selectedLevels = {}; // 空＝全レベル表示
  ExamFramework _framework = ExamFramework.grade; // チェックボックスのラベルの基準
  final _tts = FlutterTts();

  @override
  void initState() {
    super.initState();
    _tts.setLanguage('en-US');
    final entries = [...widget.translator.allEntries];
    entries.sort((a, b) {
      final levelCompare = widget.wordLevels
          .levelOf(a.key)
          .index
          .compareTo(widget.wordLevels.levelOf(b.key).index);
      if (levelCompare != 0) return levelCompare;
      return a.key.compareTo(b.key);
    });
    _allEntries = entries;
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  Future<void> _speak(String word) => _tts.speak(word);

  List<MapEntry<String, String>> get _filtered {
    final q = _query.trim().toLowerCase();
    return _allEntries.where((e) {
      if (_favoritesOnly && !widget.favorites.isFavorite(e.key)) return false;
      if (_selectedLevels.isNotEmpty &&
          !_selectedLevels.contains(widget.wordLevels.levelOf(e.key))) {
        return false;
      }
      if (q.isEmpty) return true;
      return e.key.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final entries = _filtered;

    return Scaffold(
      body: Stack(
        children: [
          const WoodFloorBackground(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back, color: WoodColors.ink),
                      ),
                      const Eyebrow('DICTIONARY'),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.only(left: 8, bottom: 12),
                    child: Text(
                      '辞書',
                      style: TextStyle(
                        fontFamily: 'Fraunces',
                        fontWeight: FontWeight.w900,
                        fontSize: 26,
                        color: WoodColors.ink,
                      ),
                    ),
                  ),

                  // 検索バー
                  Container(
                    decoration: BoxDecoration(
                      color: WoodColors.ink.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: WoodColors.ink.withValues(alpha: 0.18),
                        width: 1.5,
                      ),
                    ),
                    child: TextField(
                      onChanged: (v) => setState(() => _query = v),
                      style: const TextStyle(
                        color: WoodColors.ink,
                        fontFamily: 'Archivo',
                      ),
                      decoration: const InputDecoration(
                        hintText: '単語を検索',
                        hintStyle: TextStyle(color: WoodColors.oakGroove),
                        prefixIcon: Icon(Icons.search, color: WoodColors.ink),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // すべて／お気に入り 切り替え
                  Row(
                    children: [
                      Expanded(
                        child: _FilterTab(
                          label: 'すべて (${_allEntries.length})',
                          selected: !_favoritesOnly,
                          onTap: () => setState(() => _favoritesOnly = false),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _FilterTab(
                          label: '★ お気に入り',
                          selected: _favoritesOnly,
                          onTap: () => setState(() => _favoritesOnly = true),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // どの「ものさし」でラベルを表示するか（学年／英検／TOEIC／TOEFL／IELTS）
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: ExamFramework.values.map((f) {
                      return _ExamChip(
                        label: f.title,
                        selected: _framework == f,
                        onTap: () => setState(() => _framework = f),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),

                  // 単語レベルで絞り込み（複数選択可、何も選ばなければ全レベル表示）
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: WordLevel.values.map((level) {
                      final selected = _selectedLevels.contains(level);
                      return _LevelCheckbox(
                        label: _framework.labelFor(level),
                        selected: selected,
                        onTap: () => setState(() {
                          if (selected) {
                            _selectedLevels.remove(level);
                          } else {
                            _selectedLevels.add(level);
                          }
                        }),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),

                  Expanded(
                    child: entries.isEmpty
                        ? Center(
                            child: Text(
                              _favoritesOnly ? 'お気に入りはまだありません' : '見つかりませんでした',
                              style: TextStyle(
                                color: WoodColors.ink.withValues(alpha: 0.6),
                              ),
                            ),
                          )
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: ListView.separated(
                              itemCount: entries.length,
                              separatorBuilder: (_, _) => Container(
                                height: 1,
                                color: WoodColors.oakHi.withValues(alpha: 0.35),
                              ),
                              itemBuilder: (context, i) {
                                final entry = entries[i];
                                final tone =
                                    FloorPainter.plankTones[i % FloorPainter.plankTones.length];
                                return _DictionaryRow(
                                  word: entry.key,
                                  meaning: entry.value,
                                  isFavorite: widget.favorites.isFavorite(entry.key),
                                  toneTop: tone[0],
                                  toneBottom: tone[1],
                                  onSpeak: () => _speak(entry.key),
                                  onToggleFavorite: () async {
                                    await widget.favorites.toggle(entry.key);
                                    setState(() {});
                                  },
                                );
                              },
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? WoodColors.ink : WoodColors.ink.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: selected ? WoodColors.paper : WoodColors.ink,
          ),
        ),
      ),
    );
  }
}

// レベルラベルの基準（学年／英検／TOEIC等）を選ぶ単一選択チップ
class _ExamChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ExamChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? WoodColors.ink : WoodColors.ink.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 12,
            color: selected ? WoodColors.paper : WoodColors.ink,
          ),
        ),
      ),
    );
  }
}

// 学年レベルの絞り込みチェックボックス（複数選択可）
class _LevelCheckbox extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _LevelCheckbox({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? WoodColors.ink : WoodColors.ink.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? WoodColors.ink
                : WoodColors.ink.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected ? Icons.check_box : Icons.check_box_outline_blank,
              size: 15,
              color: selected ? WoodColors.paper : WoodColors.ink.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: selected ? WoodColors.paper : WoodColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 単語1行＝床板1枚のカード。行の高さを揃えて表のように見せ、
// 板の継ぎ目（濃い影の下にすぐ明るいハイライト）は上のListViewの
// separatorBuilderと自分自身の下側ボーダーを組み合わせて表現している。
class _DictionaryRow extends StatelessWidget {
  static const height = 64.0;

  final String word;
  final String meaning;
  final bool isFavorite;
  final Color toneTop;
  final Color toneBottom;
  final VoidCallback onSpeak;
  final VoidCallback onToggleFavorite;
  const _DictionaryRow({
    required this.word,
    required this.meaning,
    required this.isFavorite,
    required this.toneTop,
    required this.toneBottom,
    required this.onSpeak,
    required this.onToggleFavorite,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [toneTop, toneBottom],
        ),
        border: Border(
          bottom: BorderSide(
            color: WoodColors.oakGroove.withValues(alpha: 0.55),
            width: 1.6,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: onSpeak,
            child: Container(
              width: 26,
              height: 26,
              decoration: const BoxDecoration(
                color: WoodColors.ink,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.volume_up,
                size: 14,
                color: WoodColors.paper,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  word,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Fraunces',
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                    color: WoodColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  meaning,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: WoodColors.ink.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onToggleFavorite,
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Icon(
                isFavorite ? Icons.star : Icons.star_border,
                color: isFavorite
                    ? WoodColors.amber
                    : WoodColors.ink.withValues(alpha: 0.35),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
