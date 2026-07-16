import 'package:flutter/material.dart';
import '../services/favorites_service.dart';
import '../services/player_stats_service.dart';
import '../services/supabase_service.dart';
import '../services/translator.dart';
import '../services/word_level_service.dart';
import '../services/word_validator.dart';
import '../theme/wood_theme.dart';
import 'dictionary_screen.dart';
import 'game_mode_screen.dart';
import 'ranking_screen.dart';

/// アプリを開いて最初に出るタイトル画面（ゲーム／辞書の入口）
class TitleScreen extends StatefulWidget {
  final WordValidator validator;
  final Translator translator;
  final FavoritesService favorites;
  final WordLevelService wordLevels;
  final PlayerStatsService playerStats;
  final SupabaseService supabase;
  const TitleScreen({
    super.key,
    required this.validator,
    required this.translator,
    required this.favorites,
    required this.wordLevels,
    required this.playerStats,
    required this.supabase,
  });

  @override
  State<TitleScreen> createState() => _TitleScreenState();
}

class _TitleScreenState extends State<TitleScreen> {
  @override
  void initState() {
    super.initState();
    // 初回に players 行が作られた新規プレイヤーには、名前入力を促す
    if (widget.supabase.isNewPlayer) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.supabase.isNewPlayer = false;
        _editName(initial: true);
      });
    }
  }

  Future<void> _editName({bool initial = false}) async {
    final current = widget.supabase.currentPlayer?.displayName ?? '';
    final name = await showDialog<String>(
      context: context,
      barrierDismissible: !initial, // 初回は必ず入力してもらう
      builder: (_) => _NameDialog(
        initialName: initial ? '' : current,
        isFirstTime: initial,
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      await widget.supabase.updateDisplayName(name);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const WoodFloorBackground(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Word\nBattle',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Fraunces',
                      fontWeight: FontWeight.w900,
                      fontSize: 52,
                      height: 1.05,
                      color: WoodColors.ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '木目の盤で単語をつくろう',
                    style: TextStyle(
                      fontFamily: 'Fraunces',
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w500,
                      fontSize: 16,
                      color: WoodColors.ink.withValues(alpha: 0.65),
                    ),
                  ),
                  const SizedBox(height: 56),
                  SizedBox(
                    width: double.infinity,
                    child: WoodButton(
                      label: 'ゲーム',
                      big: true,
                      primary: true,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => GameModeScreen(
                            validator: widget.validator,
                            translator: widget.translator,
                            favorites: widget.favorites,
                            wordLevels: widget.wordLevels,
                            playerStats: widget.playerStats,
                            supabase: widget.supabase,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: WoodButton(
                      label: '辞書',
                      big: true,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => DictionaryScreen(
                            translator: widget.translator,
                            favorites: widget.favorites,
                            wordLevels: widget.wordLevels,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (widget.supabase.isEnabled) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: WoodButton(
                        label: 'ランキング',
                        big: true,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                RankingScreen(supabase: widget.supabase),
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  _ConnectionBadge(
                    supabase: widget.supabase,
                    onEditName: () => _editName(),
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

/// タイトル画面下部に出す、Supabaseへの接続状態バッジ
class _ConnectionBadge extends StatelessWidget {
  final SupabaseService supabase;
  final VoidCallback onEditName;
  const _ConnectionBadge({required this.supabase, required this.onEditName});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SupabaseConnectionStatus>(
      future: supabase.checkConnection(),
      builder: (context, snapshot) {
        final status = snapshot.data;

        late final IconData icon;
        late final String label;
        late final Color color;

        if (status == null) {
          icon = Icons.sync;
          label = 'サーバー接続を確認中…';
          color = WoodColors.ink.withValues(alpha: 0.5);
        } else {
          switch (status) {
            case SupabaseConnectionStatus.connected:
              icon = Icons.cloud_done;
              label = 'サーバーに接続済み';
              color = WoodColors.inkSoft;
            case SupabaseConnectionStatus.notConfigured:
              icon = Icons.cloud_off;
              label = 'オフライン（接続情報なし）';
              color = WoodColors.ink.withValues(alpha: 0.45);
            case SupabaseConnectionStatus.failed:
              icon = Icons.error_outline;
              label = 'サーバーに接続できません';
              color = WoodColors.danger;
          }
        }

        final player = supabase.currentPlayer;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: color),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
            if (status == SupabaseConnectionStatus.connected && player != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: GestureDetector(
                  onTap: onEditName,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${player.displayName}（レート ${player.rating}）',
                        style: TextStyle(
                          fontSize: 12,
                          color: WoodColors.ink.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.edit,
                        size: 13,
                        color: WoodColors.ink.withValues(alpha: 0.5),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// プレイヤー名の入力ダイアログ（初回登録・後からの変更どちらにも使う）
class _NameDialog extends StatefulWidget {
  final String initialName;
  final bool isFirstTime;
  const _NameDialog({required this.initialName, required this.isFirstTime});

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: WoodColors.paper,
      title: Text(
        widget.isFirstTime ? 'プレイヤー名を決めよう' : '名前を変更',
        style: const TextStyle(
          fontFamily: 'Fraunces',
          fontWeight: FontWeight.w700,
          color: WoodColors.ink,
        ),
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 20,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        style: const TextStyle(color: WoodColors.ink),
        decoration: InputDecoration(
          hintText: '名前を入力',
          hintStyle: TextStyle(color: WoodColors.ink.withValues(alpha: 0.4)),
          focusedBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: WoodColors.ink, width: 2),
          ),
        ),
      ),
      actions: [
        if (!widget.isFirstTime)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'キャンセル',
              style: TextStyle(color: WoodColors.ink.withValues(alpha: 0.6)),
            ),
          ),
        TextButton(
          onPressed: _submit,
          child: const Text(
            '決定',
            style: TextStyle(
              color: WoodColors.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
