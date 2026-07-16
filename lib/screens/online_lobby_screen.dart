import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/favorites_service.dart';
import '../services/online_battle_service.dart';
import '../services/translator.dart';
import '../services/word_level_service.dart';
import '../theme/wood_theme.dart';
import 'online_battle_screen.dart';

/// オンライン対戦のロビー。部屋を作る（合言葉を発行）か、合言葉で入る。
class OnlineLobbyScreen extends StatefulWidget {
  final Translator translator;
  final WordLevelService wordLevels;
  final FavoritesService favorites;
  const OnlineLobbyScreen({
    super.key,
    required this.translator,
    required this.wordLevels,
    required this.favorites,
  });

  @override
  State<OnlineLobbyScreen> createState() => _OnlineLobbyScreenState();
}

enum _LobbyMode { menu, hosting, joining }

class _OnlineLobbyScreenState extends State<OnlineLobbyScreen> {
  final _online = OnlineBattleService();
  final _codeController = TextEditingController();

  _LobbyMode _mode = _LobbyMode.menu;
  bool _busy = false;
  String? _error;

  // ホスト用
  RoomInfo? _room;
  RealtimeChannel? _matchChannel;

  @override
  void dispose() {
    _codeController.dispose();
    final ch = _matchChannel;
    if (ch != null) _online.removeChannel(ch);
    super.dispose();
  }

  // ランダムマッチ → 相手がいれば即開始、いなければ待機
  Future<void> _random() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final room = await _online.findMatch();
      if (!mounted) return;
      if (room.isWaiting) {
        // 自分が待機ホスト。相手が入ったら開始。
        _matchChannel = _online.subscribeMatch(room.matchId, (row) {
          if (row['status'] == 'playing' && mounted) {
            _goToBattle(room.matchId, room.letters, isHost: true);
          }
        });
        setState(() {
          _room = room;
          _mode = _LobbyMode.hosting;
          _busy = false;
        });
      } else {
        // すでに相手が待っていた → 即対戦
        _goToBattle(room.matchId, room.letters, isHost: false);
      }
    } catch (e) {
      setState(() {
        _error = 'マッチングに失敗しました。通信を確認してください。';
        _busy = false;
      });
    }
  }

  // 部屋を作る → 合言葉を表示して相手を待つ
  Future<void> _host() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final room = await _online.createRoom();
      _matchChannel = _online.subscribeMatch(room.matchId, (row) {
        if (row['status'] == 'playing' && mounted) {
          _goToBattle(room.matchId, room.letters, isHost: true);
        }
      });
      setState(() {
        _room = room;
        _mode = _LobbyMode.hosting;
        _busy = false;
      });
    } catch (e) {
      setState(() {
        _error = '部屋を作れませんでした。通信を確認してください。';
        _busy = false;
      });
    }
  }

  // 合言葉で入る
  Future<void> _join() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.length < 4) {
      setState(() => _error = '4文字の合言葉を入力してください');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final room = await _online.joinRoom(code);
      if (!mounted) return;
      _goToBattle(room.matchId, room.letters, isHost: false);
    } on PostgrestException catch (e) {
      setState(() {
        _busy = false;
        _error = _messageFor(e.message);
      });
    } catch (_) {
      setState(() {
        _busy = false;
        _error = '入室できませんでした。通信を確認してください。';
      });
    }
  }

  String _messageFor(String raw) {
    if (raw.contains('room_not_found')) return 'その合言葉の部屋は見つかりませんでした';
    if (raw.contains('room_full')) return 'その部屋はすでに満員です';
    if (raw.contains('already_joined')) return '自分の部屋には入れません';
    return '入室できませんでした（$raw）';
  }

  Future<void> _goToBattle(String matchId, String letters,
      {required bool isHost}) async {
    // ホストの待機購読は解除（対戦画面が自分で購読する）
    final ch = _matchChannel;
    if (ch != null) {
      _online.removeChannel(ch);
      _matchChannel = null;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OnlineBattleScreen(
          matchId: matchId,
          letters: letters,
          translator: widget.translator,
          wordLevels: widget.wordLevels,
          favorites: widget.favorites,
        ),
      ),
    );
    // 対戦から戻ってきたらメニューに戻す
    if (mounted) {
      setState(() {
        _mode = _LobbyMode.menu;
        _room = null;
        _codeController.clear();
      });
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back, color: WoodColors.ink),
                      ),
                      const Eyebrow('ONLINE'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'オンライン対戦',
                    style: TextStyle(
                      fontFamily: 'Fraunces',
                      fontWeight: FontWeight.w900,
                      fontSize: 28,
                      color: WoodColors.ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '合言葉で友達とつながって、同じお題で対戦しよう',
                    style: TextStyle(
                      fontSize: 13,
                      color: WoodColors.ink.withValues(alpha: 0.65),
                    ),
                  ),
                  const Spacer(),
                  if (_error != null) ...[
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: WoodColors.danger,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  _buildBody(),
                  const Spacer(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    switch (_mode) {
      case _LobbyMode.menu:
        return Column(
          children: [
            SizedBox(
              width: double.infinity,
              child: WoodButton(
                label: _busy ? 'マッチング中…' : 'ランダムマッチ',
                big: true,
                primary: true,
                onTap: _busy ? null : _random,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '― 友達と対戦するなら ―',
              style: TextStyle(
                fontSize: 12,
                color: WoodColors.ink.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: WoodButton(
                label: '部屋を作る',
                big: true,
                onTap: _busy ? null : _host,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: WoodButton(
                label: '合言葉で入る',
                big: true,
                onTap: _busy
                    ? null
                    : () => setState(() {
                          _mode = _LobbyMode.joining;
                          _error = null;
                        }),
              ),
            ),
          ],
        );

      case _LobbyMode.hosting:
        final code = _room?.code; // null＝ランダムマッチの待機
        return Column(
          children: [
            if (code != null) ...[
              Text(
                'あいことば',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                  color: WoodColors.ink.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                decoration: BoxDecoration(
                  color: WoodColors.ink,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  code,
                  style: const TextStyle(
                    fontFamily: 'Fraunces',
                    fontWeight: FontWeight.w900,
                    fontSize: 44,
                    letterSpacing: 8,
                    color: WoodColors.paper,
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: WoodColors.ink,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  code != null ? '相手が入るのを待っています…' : '対戦相手を探しています…',
                  style: const TextStyle(color: WoodColors.ink, fontSize: 14),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              code != null ? 'この4文字を相手に伝えてね' : '誰かがマッチするまで少し待ってね',
              style: TextStyle(
                fontSize: 12,
                color: WoodColors.ink.withValues(alpha: 0.6),
              ),
            ),
          ],
        );

      case _LobbyMode.joining:
        return Column(
          children: [
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
                controller: _codeController,
                autofocus: true,
                textAlign: TextAlign.center,
                textCapitalization: TextCapitalization.characters,
                maxLength: 4,
                style: const TextStyle(
                  color: WoodColors.ink,
                  fontFamily: 'Fraunces',
                  fontWeight: FontWeight.w900,
                  fontSize: 32,
                  letterSpacing: 8,
                ),
                decoration: const InputDecoration(
                  hintText: 'コード',
                  counterText: '',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: WoodButton(
                label: _busy ? '入室中…' : '入る',
                big: true,
                primary: true,
                onTap: _busy ? null : _join,
              ),
            ),
          ],
        );
    }
  }
}
