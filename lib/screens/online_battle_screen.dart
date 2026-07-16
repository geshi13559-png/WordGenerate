import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/favorites_service.dart';
import '../services/online_battle_service.dart';
import '../services/translator.dart';
import '../services/word_level_service.dart';
import '../theme/wood_theme.dart';

/// オンライン対戦の本編。2人が同じお題（letters）で90秒間プレイし、
/// スコアはサーバーが採点。相手の点数はRealtimeでライブ表示。
class OnlineBattleScreen extends StatefulWidget {
  final String matchId;
  final String letters; // 共有のお題11文字
  final Translator translator;
  final WordLevelService wordLevels;
  final FavoritesService favorites;
  const OnlineBattleScreen({
    super.key,
    required this.matchId,
    required this.letters,
    required this.translator,
    required this.wordLevels,
    required this.favorites,
  });

  @override
  State<OnlineBattleScreen> createState() => _OnlineBattleScreenState();
}

class _OnlineBattleScreenState extends State<OnlineBattleScreen> {
  final _online = OnlineBattleService();

  static const _roundSeconds = 90; // オンラインは固定90秒（時間ボーナス無し）

  late final List<String> _letters; // 表示用（大文字）
  late List<bool> _used;
  List<int> _selected = [];
  final List<_Found> _found = [];
  final Set<String> _usedWords = {};

  int _myScore = 0;
  int _oppScore = 0;
  int _timeLeft = _roundSeconds;
  String _message = '同じお題で対戦！単語をつくろう';

  // 開始予約時刻（サーバー）。ここまでは「3・2・1・GO」のカウントダウン。
  DateTime? _startAt;
  int _countdown = 0; // 開始までの残り秒（>0＝カウントダウン中）
  bool _playing = false; // 90秒の本番が始まっているか
  bool _showGo = false; // 「GO!」の一瞬の表示

  bool _finished = false;
  bool _finishing = false; // finish_match 呼び出し中の二重防止
  MatchResult? _result;
  List<_Found> _oppWords = []; // 試合後に見せる、相手が作った単語
  List<_Found> _suggestions = []; // こんな単語も作れたよ（誰も作らなかった作れる単語）
  bool _reviewMode = false; // 結果を閉じてレビュー表示に切り替えたか

  Timer? _timer;
  RealtimeChannel? _playersCh;
  RealtimeChannel? _matchCh;

  @override
  void initState() {
    super.initState();
    _letters = widget.letters.toUpperCase().split('');
    _used = List.filled(_letters.length, false);
    _subscribe();
    _start();
  }

  Future<void> _start() async {
    // サーバーの「開始予約時刻」を取得（少し未来＝その間カウントダウン）
    final m = await _online.fetchMatch(widget.matchId);
    if (!mounted) return;
    if (m != null && m['status'] == 'finished') {
      _onFinished();
      return;
    }
    final startedAt = m?['started_at'] as String?;
    _startAt = (startedAt != null ? DateTime.tryParse(startedAt)?.toUtc() : null) ??
        DateTime.now().toUtc();
    // 初期スコアを取得
    final players = await _online.fetchPlayers(widget.matchId);
    if (!mounted) return;
    setState(() {
      for (final p in players) {
        _applyPlayerRow(p);
      }
    });
    _runTicker();
  }

  void _subscribe() {
    _playersCh = _online.subscribePlayers(widget.matchId, (row) {
      if (!mounted) return;
      setState(() => _applyPlayerRow(row));
    });
    _matchCh = _online.subscribeMatch(widget.matchId, (row) {
      if (!mounted) return;
      if (row['status'] == 'finished' && !_finished) {
        _onFinished();
      }
    });
  }

  void _applyPlayerRow(Map<String, dynamic> row) {
    final pid = row['player_id'] as String?;
    final score = row['score'] as int? ?? 0;
    if (pid == _online.myId) {
      _myScore = score;
    } else if (pid != null) {
      _oppScore = score;
    }
  }

  // サーバー開始時刻を基準に、カウントダウン→90秒本番を進める（クロック基準でズレない）
  void _runTicker() {
    _timer?.cancel();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (!mounted || _finished) return;
    final start = _startAt;
    if (start == null) return;
    final now = DateTime.now().toUtc();
    final msToStart = start.difference(now).inMilliseconds;
    final wasPlaying = _playing;
    setState(() {
      if (msToStart > 0) {
        _playing = false;
        _countdown = (msToStart / 1000).ceil();
      } else {
        _countdown = 0;
        _playing = true;
        final left = _roundSeconds - now.difference(start).inSeconds;
        _timeLeft = left.clamp(0, _roundSeconds);
        if (left <= 0) {
          _timer?.cancel();
          _finish();
        }
      }
    });
    // カウントダウン→本番に切り替わった瞬間に「GO!」を一瞬出す
    if (!wasPlaying && _playing && _timeLeft > 0) {
      setState(() => _showGo = true);
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) setState(() => _showGo = false);
      });
    }
  }

  // 時間切れ→サーバーへ終了申告。両者終了 or 時間切れ(95秒)で決着。
  // まだ決着しない（相手が終えていない）場合は、数秒ごとに問い直す。
  // 相手が抜けても、サーバーが開始95秒経過で自動的に決着させる。
  Future<void> _finish() async {
    if (_finishing || _finished) return;
    _finishing = true;
    try {
      final res = await _online.finishMatch(widget.matchId);
      if (!mounted) return;
      if (res.finished) {
        setState(() {
          _result = res;
          _finished = true;
        });
        _loadOppWords();
        return;
      }
      setState(() => _message = '相手の終了を待っています…');
    } catch (_) {
      // 通信失敗時も後でリトライ
    } finally {
      _finishing = false;
    }
    // まだ決着していなければ、少し待って問い直す
    if (mounted && !_finished) {
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && !_finished) _finish();
      });
    }
  }

  // matches が finished になった通知を受けたとき（相手が先に終わった等）
  Future<void> _onFinished() async {
    if (_finished) return;
    try {
      final res = await _online.finishMatch(widget.matchId); // 自分視点の結果を取得
      if (!mounted) return;
      setState(() {
        _result = res;
        _finished = true;
        _timeLeft = 0;
      });
      _timer?.cancel();
      _loadOppWords();
    } catch (_) {}
  }

  // 試合後：相手が作った単語を取得し、候補（こんな単語も作れたよ）も計算する
  Future<void> _loadOppWords() async {
    try {
      final rows = await _online.fetchSubmittedWords(widget.matchId);
      final me = _online.myId;
      final opp = <_Found>[];
      for (final r in rows) {
        if (r['player_id'] == me) continue;
        final w = r['word'] as String;
        opp.add(_Found(
          word: w.toUpperCase(),
          meaning: widget.translator.translate(w),
          points: r['points'] as int? ?? 0,
        ));
      }
      final suggestions = _computeSuggestions(opp);
      if (mounted) {
        setState(() {
          _oppWords = opp;
          _suggestions = suggestions;
        });
      }
    } catch (_) {}
  }

  // お題で作れるのに、どちらも作らなかった単語を「こんな単語も作れたよ」として選ぶ
  List<_Found> _computeSuggestions(List<_Found> oppWords) {
    final made = <String>{..._usedWords};
    for (final w in oppWords) {
      made.add(w.word.toLowerCase());
    }
    final pool = _letters.map((e) => e.toLowerCase()).toList();
    final out = <_Found>[];
    for (final e in widget.translator.allEntries) {
      final w = e.key;
      if (w.length < 2 || made.contains(w)) continue;
      if (!_canFormLocally(w, pool)) continue;
      out.add(_Found(
        word: w.toUpperCase(),
        meaning: e.value,
        points: widget.wordLevels.levelOf(w).scoreTier.points,
      ));
    }
    // 点数が高い→長い順に、代表を12個
    out.sort((a, b) {
      final p = b.points.compareTo(a.points);
      return p != 0 ? p : b.word.length.compareTo(a.word.length);
    });
    return out.take(12).toList();
  }

  bool _canFormLocally(String word, List<String> letters) {
    final pool = [...letters];
    for (final ch in word.split('')) {
      final idx = pool.indexOf(ch);
      if (idx == -1) return false;
      pool.removeAt(idx);
    }
    return true;
  }

  // 一番最初の画面（タイトル）へ戻る
  void _goHome() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  // 決着後のレビュー画面：相手の単語 と「こんな単語も作れたよ」
  Widget _buildReview() {
    final r = _result!;
    final win = r.myScore > r.oppScore;
    final draw = r.myScore == r.oppScore;
    final before = r.ratingBefore;
    final after = r.ratingAfter;
    final delta = (before != null && after != null) ? after - before : null;
    return Scaffold(
      body: Stack(
        children: [
          const WoodFloorBackground(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        draw ? '引き分け' : (win ? 'あなたの勝ち！' : '相手の勝ち'),
                        style: const TextStyle(
                          fontFamily: 'Fraunces',
                          fontWeight: FontWeight.w900,
                          fontSize: 22,
                          color: WoodColors.ink,
                        ),
                      ),
                      const Spacer(),
                      _ScorePill(label: 'あなた', score: r.myScore, mine: true),
                      const SizedBox(width: 8),
                      _ScorePill(label: '相手', score: r.oppScore, mine: false),
                    ],
                  ),
                  if (before != null && after != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'レート $before → $after'
                        '${delta != null ? (delta >= 0 ? '（+$delta）' : '（$delta）') : ''}',
                        style: TextStyle(
                          fontSize: 12,
                          color: WoodColors.ink.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView(
                      children: [
                        const Eyebrow('相手が作った単語'),
                        const SizedBox(height: 6),
                        if (_oppWords.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              '相手は単語を作れませんでした',
                              style: TextStyle(
                                fontSize: 13,
                                color: WoodColors.ink.withValues(alpha: 0.6),
                              ),
                            ),
                          )
                        else
                          ..._oppWords.map(_wordRow),
                        const SizedBox(height: 20),
                        const Eyebrow('こんな単語も作れたよ'),
                        const SizedBox(height: 6),
                        ..._suggestions.map(_wordRow),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: WoodButton(
                            label: 'ホーム', big: true, onTap: _goHome),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: WoodButton(
                          label: '結果を見る',
                          big: true,
                          primary: true,
                          onTap: () => setState(() => _reviewMode = false),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // レビュー用の単語1行（★でお気に入り）
  Widget _wordRow(_Found w) {
    final fav = widget.favorites.isFavorite(w.word);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: WoodColors.ink,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '+${w.points}',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: WoodColors.paper,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            w.word,
            style: const TextStyle(
              fontFamily: 'Fraunces',
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: WoodColors.ink,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              w.meaning ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: WoodColors.ink.withValues(alpha: 0.7),
              ),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () {
              widget.favorites.toggle(w.word);
              setState(() {});
            },
            child: Icon(
              fav ? Icons.star : Icons.star_border,
              size: 20,
              color: fav
                  ? WoodColors.amber
                  : WoodColors.ink.withValues(alpha: 0.35),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    final p = _playersCh;
    final m = _matchCh;
    if (p != null) _online.removeChannel(p);
    if (m != null) _online.removeChannel(m);
    super.dispose();
  }

  String get _currentWord => _selected.map((i) => _letters[i]).join();

  void _tap(int i) {
    if (!_playing || _finished || _timeLeft <= 0) return;
    if (_used[i]) return;
    setState(() {
      _used[i] = true;
      _selected.add(i);
    });
  }

  void _backspace() {
    if (_selected.isEmpty) return;
    setState(() {
      final last = _selected.removeLast();
      _used[last] = false;
    });
  }

  void _clear() {
    setState(() {
      for (final i in _selected) {
        _used[i] = false;
      }
      _selected = [];
    });
  }

  Future<void> _submit() async {
    if (!_playing || _finished || _timeLeft <= 0) return;
    final word = _currentWord;
    if (word.length < 2) {
      setState(() => _message = '❌ 2文字以上えらんでください');
      return;
    }
    final lower = word.toLowerCase();
    if (_usedWords.contains(lower)) {
      setState(() {
        _message = '❌ "$word" はもう出しました';
        _clear();
      });
      return;
    }
    _clear();
    final res = await _online.submitWord(widget.matchId, lower);
    if (!mounted) return;
    setState(() {
      if (res.ok) {
        _usedWords.add(lower);
        _myScore = res.score;
        _found.insert(
          0,
          _Found(word: word, meaning: widget.translator.translate(lower), points: res.points),
        );
        _message = '⭕️ "$word" +${res.points}点';
      } else {
        _message = _reasonText(word, res.reason);
      }
    });
  }

  String _reasonText(String word, String? reason) {
    switch (reason) {
      case 'not_a_word':
        return '❌ "$word" は辞書にありません';
      case 'bad_letters':
        return '❌ "$word" はお題の文字で作れません';
      case 'duplicate':
        return '❌ "$word" はもう出しました';
      case 'time_up':
        return '⏰ 時間切れです';
      case 'too_short':
        return '❌ 2文字以上えらんでください';
      default:
        return '❌ "$word" は無効です';
    }
  }

  @override
  Widget build(BuildContext context) {
    // 決着後、結果を閉じたら「レビュー画面」（相手の単語・候補）に切り替える
    if (_finished && _reviewMode) return _buildReview();
    return Scaffold(
      body: Stack(
        children: [
          const WoodFloorBackground(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                children: [
                  // ヘッダー：戻る・スコア・タイマー
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close, color: WoodColors.ink),
                      ),
                      const Spacer(),
                      _ScorePill(label: 'あなた', score: _myScore, mine: true),
                      const SizedBox(width: 10),
                      _ScorePill(label: '相手', score: _oppScore, mine: false),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // タイマー（本番中のみ。カウントダウン中は「まもなく開始」）
                  Text(
                    _playing ? '残り $_timeLeft 秒' : 'まもなく開始',
                    style: TextStyle(
                      fontFamily: 'Archivo',
                      fontWeight: FontWeight.w900,
                      fontSize: 22,
                      color: _playing && _timeLeft <= 10
                          ? WoodColors.danger
                          : WoodColors.ink,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 現在の単語
                  Container(
                    width: double.infinity,
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: WoodColors.ink.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _currentWord,
                      style: const TextStyle(
                        fontFamily: 'Fraunces',
                        fontWeight: FontWeight.w900,
                        fontSize: 26,
                        letterSpacing: 4,
                        color: WoodColors.ink,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // タイル（静かな待機中＝残り8秒超は隠す。準備フェーズから見せる）
                  if (_playing || _countdown <= 8)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        for (var i = 0; i < _letters.length; i++)
                          _Tile(
                            letter: _letters[i],
                            used: _used[i],
                            onTap: () => _tap(i),
                          ),
                      ],
                    )
                  else
                    const SizedBox(height: 52),
                  const SizedBox(height: 10),

                  // 操作ボタン
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      WoodButton(label: '←1文字', onTap: _backspace),
                      const SizedBox(width: 8),
                      WoodButton(label: 'クリア', onTap: _clear),
                      const SizedBox(width: 8),
                      WoodButton(label: '提出', primary: true, onTap: _submit),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, color: WoodColors.ink),
                  ),
                  const SizedBox(height: 8),

                  // 見つけた単語
                  Expanded(
                    child: ListView.builder(
                      itemCount: _found.length,
                      itemBuilder: (_, i) {
                        final f = _found[i];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: WoodColors.ink,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '+${f.points}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: WoodColors.paper,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                f.word,
                                style: const TextStyle(
                                  fontFamily: 'Fraunces',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: WoodColors.ink,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  f.meaning ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color:
                                        WoodColors.ink.withValues(alpha: 0.7),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          // カウントダウン（3・2・1・GO!）オーバーレイ
          if (!_finished && (!_playing || _showGo))
            _CountdownOverlay(count: _countdown, go: _showGo),

          // 結果オーバーレイ
          if (_finished && _result != null)
            _ResultOverlay(
              result: _result!,
              onClose: () => setState(() => _reviewMode = true),
              onHome: _goHome,
            ),
        ],
      ),
    );
  }
}

/// 開始前の「3・2・1・GO!」表示。盤面の上に大きく出す。
class _CountdownOverlay extends StatelessWidget {
  final int count;
  final bool go;
  const _CountdownOverlay({required this.count, required this.go});

  @override
  Widget build(BuildContext context) {
    // 3段階：
    //  ・接続直後～残り8秒超（最初の約5秒）＝ほぼ無表示の静かな待機（盤面も隠す）
    //  ・残り4～8秒＝準備フェーズ（盤面を見せて「文字を見て準備」）
    //  ・残り1～3秒＝「3・2・1」→ GO!
    late final double alpha;
    late final Widget child;

    if (go) {
      alpha = 0.42;
      child = const Text(
        'GO!',
        style: TextStyle(
          fontFamily: 'Fraunces',
          fontWeight: FontWeight.w900,
          fontSize: 88,
          color: WoodColors.oakHi,
        ),
      );
    } else if (count > 8) {
      // 静かな待機（盤面を隠す。文字はまだ見せない）
      alpha = 0.72;
      child = Text(
        'まもなく開始します…',
        style: TextStyle(
          fontFamily: 'Fraunces',
          fontWeight: FontWeight.w700,
          fontSize: 22,
          color: WoodColors.paper.withValues(alpha: 0.9),
        ),
      );
    } else if (count > 3) {
      // 準備フェーズ（盤面が見えるよう薄く）
      alpha = 0.2;
      child = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'まもなく開始',
            style: TextStyle(
              fontFamily: 'Fraunces',
              fontWeight: FontWeight.w900,
              fontSize: 30,
              color: WoodColors.paper,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'お題の文字をよく見て準備しよう',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: WoodColors.paper.withValues(alpha: 0.85),
            ),
          ),
        ],
      );
    } else {
      // 3・2・1
      alpha = 0.42;
      child = Text(
        '$count',
        style: const TextStyle(
          fontFamily: 'Fraunces',
          fontWeight: FontWeight.w900,
          fontSize: 120,
          color: WoodColors.paper,
        ),
      );
    }

    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: WoodColors.ink.withValues(alpha: alpha),
          alignment: Alignment.center,
          child: child,
        ),
      ),
    );
  }
}

class _Found {
  final String word;
  final String? meaning;
  final int points;
  const _Found({required this.word, this.meaning, required this.points});
}

class _ScorePill extends StatelessWidget {
  final String label;
  final int score;
  final bool mine;
  const _ScorePill({required this.label, required this.score, required this.mine});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: mine ? WoodColors.ink : WoodColors.ink.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: mine
                  ? WoodColors.paper.withValues(alpha: 0.8)
                  : WoodColors.ink.withValues(alpha: 0.7),
            ),
          ),
          Text(
            '$score',
            style: TextStyle(
              fontFamily: 'Archivo',
              fontWeight: FontWeight.w900,
              fontSize: 20,
              color: mine ? WoodColors.paper : WoodColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final String letter;
  final bool used;
  final VoidCallback onTap;
  const _Tile({required this.letter, required this.used, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: used ? null : onTap,
      child: Opacity(
        opacity: used ? 0.28 : 1,
        child: Container(
          width: 48,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [WoodColors.oakHi, WoodColors.oakMid],
            ),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: WoodColors.oakGroove.withValues(alpha: 0.4),
                offset: const Offset(0, 2),
                blurRadius: 4,
              ),
            ],
          ),
          child: Text(
            letter,
            style: const TextStyle(
              fontFamily: 'Fraunces',
              fontWeight: FontWeight.w900,
              fontSize: 24,
              color: WoodColors.ink,
            ),
          ),
        ),
      ),
    );
  }
}

/// 決着オーバーレイ：勝敗とレート変動を見せる。
/// 「閉じる」でレビュー（相手の単語・候補）へ、「ホーム」でタイトルへ。
class _ResultOverlay extends StatelessWidget {
  final MatchResult result;
  final VoidCallback onClose;
  final VoidCallback onHome;
  const _ResultOverlay({
    required this.result,
    required this.onClose,
    required this.onHome,
  });

  @override
  Widget build(BuildContext context) {
    final win = result.myScore > result.oppScore;
    final draw = result.myScore == result.oppScore;
    final title = draw ? '引き分け' : (win ? 'あなたの勝ち！' : '相手の勝ち');
    final before = result.ratingBefore;
    final after = result.ratingAfter;
    final delta = (before != null && after != null) ? after - before : null;

    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.55),
        child: Center(
          child: Container(
            margin: const EdgeInsets.all(32),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: WoodColors.paper,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  draw ? '🤝' : (win ? '🎉' : '😢'),
                  style: const TextStyle(fontSize: 44),
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Fraunces',
                    fontWeight: FontWeight.w900,
                    fontSize: 26,
                    color: WoodColors.ink,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'あなた ${result.myScore}　-　${result.oppScore} 相手',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: WoodColors.ink,
                  ),
                ),
                const SizedBox(height: 16),
                if (before != null && after != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: WoodColors.ink.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('レート ',
                            style: TextStyle(color: WoodColors.ink)),
                        Text('$before → $after',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              color: WoodColors.ink,
                            )),
                        const SizedBox(width: 6),
                        if (delta != null)
                          Text(
                            delta >= 0 ? '(+$delta)' : '($delta)',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: delta >= 0
                                  ? WoodColors.inkSoft
                                  : WoodColors.danger,
                            ),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: WoodButton(label: 'ホーム', big: true, onTap: onHome),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: WoodButton(
                        label: '閉じる',
                        big: true,
                        primary: true,
                        onTap: onClose,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
