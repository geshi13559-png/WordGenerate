import 'package:flutter/material.dart';
import '../services/favorites_service.dart';
import '../services/translator.dart';
import '../theme/wood_theme.dart';

/// 辞書画面：全単語の閲覧・検索・お気に入り登録
class DictionaryScreen extends StatefulWidget {
  final Translator translator;
  final FavoritesService favorites;
  const DictionaryScreen({
    super.key,
    required this.translator,
    required this.favorites,
  });

  @override
  State<DictionaryScreen> createState() => _DictionaryScreenState();
}

class _DictionaryScreenState extends State<DictionaryScreen> {
  late final List<MapEntry<String, String>> _allEntries;
  String _query = '';
  bool _favoritesOnly = false;

  @override
  void initState() {
    super.initState();
    _allEntries = widget.translator.allEntries;
  }

  List<MapEntry<String, String>> get _filtered {
    final q = _query.trim().toLowerCase();
    return _allEntries.where((e) {
      if (_favoritesOnly && !widget.favorites.isFavorite(e.key)) return false;
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
                        : ListView.separated(
                            itemCount: entries.length,
                            separatorBuilder: (_, _) => Divider(
                              color: WoodColors.oakGroove.withValues(alpha: 0.25),
                              height: 1,
                            ),
                            itemBuilder: (context, i) {
                              final entry = entries[i];
                              return _DictionaryRow(
                                word: entry.key,
                                meaning: entry.value,
                                isFavorite: widget.favorites.isFavorite(entry.key),
                                onToggleFavorite: () async {
                                  await widget.favorites.toggle(entry.key);
                                  setState(() {});
                                },
                              );
                            },
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

class _DictionaryRow extends StatelessWidget {
  final String word;
  final String meaning;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;
  const _DictionaryRow({
    required this.word,
    required this.meaning,
    required this.isFavorite,
    required this.onToggleFavorite,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  word,
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
              padding: const EdgeInsets.only(left: 8, top: 2),
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
