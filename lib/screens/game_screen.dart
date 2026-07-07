import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../services/favorites_service.dart';
import '../services/letter_generator.dart';
import '../services/player_stats_service.dart';
import '../services/translator.dart';
import '../services/word_level_service.dart';
import '../services/word_validator.dart';
import '../theme/wood_theme.dart';

enum _TimerStage { calm, amber, red, critical }

/// 1人プレイのゲーム画面
class GameScreen extends StatefulWidget {
  final WordValidator validator;
  final Translator translator;
  final FavoritesService favorites;
  final WordLevelService wordLevels;
  final PlayerStatsService playerStats;
  const GameScreen({
    super.key,
    required this.validator,
    required this.translator,
    required this.favorites,
    required this.wordLevels,
    required this.playerStats,
  });

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with TickerProviderStateMixin {
  final _generator = LetterGenerator();

  // 1枚ごとのフリップ時間・隣のタイルとの発火間隔・最初のタメ
  // stagger > duration にして「前の1枚がめくり終わってから次」の間を作り、緊張感を出す
  static const _flipDuration = Duration(milliseconds: 300);
  static const _flipStagger = Duration(milliseconds: 450);
  static const _flipInitialDelay = Duration(milliseconds: 250);

  late final AnimationController _flipController;
  final _tts = FlutterTts();

  // 単語成立時：インクブルーの光を木目に沿って左から右へ流す
  late final AnimationController _beamController;
  // 残り10秒以降：数字が1秒ごとに脈打つ
  late final AnimationController _beatController;
  late final Animation<double> _beatScale;
  // 残り5秒：バーの脈動・画面ふちの赤いグローに使う継続ループ
  late final AnimationController _throbController;
  // 0になった瞬間の赤いフラッシュ（一度だけ）
  late final AnimationController _flashController;
  late final Animation<double> _flashOpacity;

  static const _roundSeconds = 45;
  static const _bonusSeconds = 5; // 1語正解するごとに伸びる時間
  Timer? _roundTimer;
  int _timeLeft = _roundSeconds;
  bool _roundActive = false; // タイマーが進行中か（全部めくり終わってから時間切れまでtrue）
  bool _timeUp = false;      // 時間切れになったか

  List<String> _letters = [];       // 出たお題の文字
  List<bool> _used = [];            // 各タイルを使用済みか
  List<int> _selectedIndexes = [];  // 選んだタイルの順番（indexで記録）
  final Set<String> _usedWords = {}; // 既に得点に使った単語
  final List<_FoundWord> _foundWords = []; // 作れた単語（表示用）
  List<_FoundWord> _suggestions = []; // 時間切れ後の「こんな単語も作れたよ」
  String _message = 'スタートを押してね';
  int _score = 0;

  // スコアバー：8語で板1枚分が満ちる（満ちたら次の板へ）
  static const _wordsPerPlank = 8;
  double _scoreFill = 0;
  bool _scoreFlash = false;

  _TimerStage get _timerStage {
    if (_timeLeft <= 5) return _TimerStage.critical;
    if (_timeLeft <= 10) return _TimerStage.red;
    if (_timeLeft <= 15) return _TimerStage.amber;
    return _TimerStage.calm;
  }

  Color get _timerStartColor {
    switch (_timerStage) {
      case _TimerStage.calm:
        return WoodColors.ink;
      case _TimerStage.amber:
        return WoodColors.amber;
      case _TimerStage.red:
      case _TimerStage.critical:
        return WoodColors.danger;
    }
  }

  Color get _timerEndColor {
    switch (_timerStage) {
      case _TimerStage.calm:
        return WoodColors.inkSoft;
      case _TimerStage.amber:
        return WoodColors.amberSoft;
      case _TimerStage.red:
      case _TimerStage.critical:
        return WoodColors.dangerSoft;
    }
  }

  @override
  void initState() {
    super.initState();
    _tts.setLanguage('en-US');
    _flipController = AnimationController(vsync: this, duration: _flipDuration)
      ..addStatusListener((status) {
        // 全タイルのフリップが完了したタイミングでタイマーを開始する
        if (status == AnimationStatus.completed) {
          _beginTimer();
        }
      });

    _beamController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _beatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _beatScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.22)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.22, end: 1.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 70,
      ),
    ]).animate(_beatController);

    _throbController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _flashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _flashOpacity = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 0.85)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 15,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.85, end: 0.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 85,
      ),
    ]).animate(_flashController);
  }

  @override
  void dispose() {
    _flipController.dispose();
    _beamController.dispose();
    _beatController.dispose();
    _throbController.dispose();
    _flashController.dispose();
    _roundTimer?.cancel();
    _tts.stop();
    super.dispose();
  }

  Future<void> _speak(String word) => _tts.speak(word);

  // index番目のタイルが今どれだけフリップしたか（0=裏, 1=表）
  double _flipProgress(int index) {
    final totalMs = _flipController.duration!.inMilliseconds;
    final startMs = _flipInitialDelay.inMilliseconds +
        index * _flipStagger.inMilliseconds;
    final endMs = startMs + _flipDuration.inMilliseconds;
    final nowMs = _flipController.value * totalMs;
    final t = ((nowMs - startMs) / (endMs - startMs)).clamp(0.0, 1.0);
    return Curves.easeInOut.transform(t);
  }

  void _startRound() {
    _roundTimer?.cancel();
    setState(() {
      _letters = _generator.generate(count: 11);
      _used = List.filled(_letters.length, false);
      _selectedIndexes = [];
      _usedWords.clear();
      _foundWords.clear();
      _suggestions = [];
      _timeLeft = _roundSeconds;
      _roundActive = false; // めくり終わるまではタイマー・操作なし
      _timeUp = false;
      _scoreFill = 0;
      _scoreFlash = false;
      _message = 'めくれるのを待ってね…';
    });
    final totalMs = _flipInitialDelay.inMilliseconds +
        _flipDuration.inMilliseconds +
        _flipStagger.inMilliseconds * (_letters.length - 1);
    _flipController
      ..duration = Duration(milliseconds: totalMs)
      ..forward(from: 0);
  }

  // 全タイルのフリップ完了時（AnimationStatus.completed）に呼ばれる
  void _beginTimer() {
    setState(() {
      _roundActive = true;
      _message = 'タイルをタップして単語を作ろう';
    });
    _roundTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _timeLeft--;
        if (_timeLeft <= 0) {
          _timeLeft = 0;
          _roundActive = false;
          _timeUp = true;
          _message = '⏰ 時間切れ！ SCORE $_score点';
          _suggestions = _computeSuggestions();
          timer.cancel();
          _flashController.forward(from: 0);
        } else if (_timeLeft <= 10) {
          _beatController.forward(from: 0);
        }
      });
    });
  }

  void _tapTile(int index) {
    if (!_roundActive) return;
    if (_used[index]) return;
    if (_flipProgress(index) < 1.0) return; // めくり終わるまでは選べない
    setState(() {
      _used[index] = true;
      _selectedIndexes.add(index);
    });
  }

  void _backspace() {
    if (_selectedIndexes.isEmpty) return;
    setState(() {
      final last = _selectedIndexes.removeLast();
      _used[last] = false;
    });
  }

  void _clear() {
    setState(() {
      for (final i in _selectedIndexes) {
        _used[i] = false;
      }
      _selectedIndexes = [];
    });
  }

  String get _currentWord =>
      _selectedIndexes.map((i) => _letters[i]).join();

  // 時間切れ後に見せる「こんな単語も作れたよ」の候補を選ぶ。
  // このラウンドの文字で作れて、まだ見つけていない単語の中から、
  // プレイヤーのこれまでの実力に近いレベルのものを優先して5つ選ぶ。
  List<_FoundWord> _computeSuggestions() {
    final candidates = <String>[];
    for (final entry in widget.translator.allEntries) {
      if (_usedWords.contains(entry.key)) continue;
      if (!widget.validator.validate(entry.key, _letters)) continue;
      candidates.add(entry.key);
    }
    if (candidates.isEmpty) return [];

    final targetLevel = widget.playerStats.averageLevel;
    candidates.sort((a, b) {
      final da = (widget.wordLevels.levelOf(a).index - targetLevel.index).abs();
      final db = (widget.wordLevels.levelOf(b).index - targetLevel.index).abs();
      return da.compareTo(db);
    });

    // レベルが近いものの中からランダムに選び、毎回同じ単語にならないようにする
    final pool = candidates.take(min(candidates.length, 15)).toList()
      ..shuffle(Random());
    return pool.take(5).map((w) {
      return _FoundWord(word: w.toUpperCase(), meaning: widget.translator.translate(w));
    }).toList();
  }

  void _submitWord() {
    if (_letters.isEmpty) {
      setState(() => _message = 'まずスタートを押してね');
      return;
    }
    if (_timeUp) {
      setState(() => _message = '⏰ 時間切れです。スタートを押してね');
      return;
    }
    if (!_roundActive) {
      setState(() => _message = 'めくれるのを待ってね…');
      return;
    }
    final word = _currentWord;
    final lowerWord = word.toLowerCase();
    final ok = widget.validator.validate(word, _letters);
    setState(() {
      if (word.isEmpty) {
        _message = '❌ 文字を選んでください';
      } else if (_usedWords.contains(lowerWord)) {
        _message = '❌ "$word" はすでに使われました';
      } else if (ok) {
        _score += 1;
        _timeLeft += _bonusSeconds;
        _usedWords.add(lowerWord);
        _foundWords.add(_FoundWord(
          word: word.toUpperCase(),
          meaning: widget.translator.translate(lowerWord),
        ));
        widget.playerStats.recordFoundWord(widget.wordLevels.levelOf(lowerWord));
        _message = '⭕️ "$word" 正解！ +1点 (+$_bonusSeconds秒)';

        _scoreFill += 1 / _wordsPerPlank;
        if (_scoreFill >= 1.0) {
          _scoreFill -= 1.0;
          _scoreFlash = true;
          Future.delayed(const Duration(milliseconds: 260), () {
            if (mounted) setState(() => _scoreFlash = false);
          });
        }

        _beamController.forward(from: 0);
      } else {
        _message = '❌ "$word" は無効です';
      }
      _clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final stage = _timerStage;
    final showCriticalFx = _roundActive && stage == _TimerStage.critical;

    return Scaffold(
      body: Stack(
        children: [
          // 床：板目フローリング
          const WoodFloorBackground(),

          // 単語成立時：インクブルーの光が木目に沿って左から右へ
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _beamController,
                builder: (context, _) {
                  if (_beamController.status == AnimationStatus.dismissed) {
                    return const SizedBox.shrink();
                  }
                  return LayoutBuilder(builder: (context, constraints) {
                    final w = constraints.maxWidth;
                    final beamWidth = w * 0.55;
                    final left =
                        -beamWidth + (w + beamWidth) * _beamController.value;
                    return Transform.translate(
                      offset: Offset(left, 0),
                      child: SizedBox(
                        width: beamWidth,
                        height: constraints.maxHeight,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.transparent,
                                const Color(0xFF7896D2).withValues(alpha: 0.0),
                                const Color(0xFF7896D2).withValues(alpha: 0.5),
                                const Color(0xFFC5D3F2).withValues(alpha: 0.85),
                                const Color(0xFF7896D2).withValues(alpha: 0.5),
                                const Color(0xFF7896D2).withValues(alpha: 0.0),
                                Colors.transparent,
                              ],
                              stops: const [0, 0.16, 0.42, 0.5, 0.58, 0.84, 1],
                            ),
                          ),
                        ),
                      ),
                    );
                  });
                },
              ),
            ),
          ),

          // 残り5秒：画面ふちに滲む赤いグロー
          if (showCriticalFx)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _throbController,
                  builder: (context, _) {
                    final intensity = 0.10 + _throbController.value * 0.20;
                    return DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment.center,
                          radius: 0.9,
                          stops: const [0.72, 1.0],
                          colors: [
                            Colors.transparent,
                            WoodColors.danger.withValues(alpha: intensity),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back, color: WoodColors.ink),
                      ),
                    ],
                  ),
                  // スコアバー・タイマーバー
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Eyebrow('SCORE'),
                            Text(
                              '$_score語',
                              style: const TextStyle(
                                fontFamily: 'Fraunces',
                                fontWeight: FontWeight.w900,
                                fontSize: 30,
                                color: WoodColors.ink,
                                height: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Eyebrow('TIME', color: _timerStartColor),
                          AnimatedBuilder(
                            animation: _beatController,
                            builder: (context, child) {
                              final scale =
                                  stage == _TimerStage.red ||
                                          stage == _TimerStage.critical
                                      ? _beatScale.value
                                      : 1.0;
                              return Transform.scale(
                                scale: scale,
                                child: child,
                              );
                            },
                            child: Text(
                              '残り ${_timeLeft.toString().padLeft(2, '0')}s',
                              style: TextStyle(
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: _timerStartColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _WoodProgressRail(
                    fraction: _scoreFill.clamp(0.0, 1.0),
                    flash: _scoreFlash,
                  ),
                  const SizedBox(height: 8),
                  _TimerRail(
                    fraction: (_timeLeft / _roundSeconds).clamp(0.0, 1.0),
                    startColor: _timerStartColor,
                    endColor: _timerEndColor,
                    throbController: showCriticalFx ? _throbController : null,
                  ),
                  const SizedBox(height: 24),

                  // 組み立て中の単語を表示するトレイ
                  Container(
                    width: double.infinity,
                    height: 66,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: WoodColors.ink.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: WoodColors.ink.withValues(alpha: 0.18),
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      _currentWord.toUpperCase(),
                      style: const TextStyle(
                        fontFamily: 'Fraunces',
                        fontWeight: FontWeight.w900,
                        fontSize: 30,
                        color: WoodColors.ink,
                        letterSpacing: 4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // お題のタイル
                  AnimatedBuilder(
                    animation: _flipController,
                    builder: (context, child) {
                      return Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        alignment: WrapAlignment.center,
                        children: List.generate(_letters.length, (i) {
                          return _LetterTile(
                            letter: _letters[i],
                            used: _used[i],
                            flipT: _flipProgress(i),
                            onTap: () => _tapTile(i),
                          );
                        }),
                      );
                    },
                  ),
                  const SizedBox(height: 20),

                  // 消す・クリアボタン
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      WoodButton(label: '← 1文字', onTap: _backspace),
                      const SizedBox(width: 16),
                      WoodButton(label: 'クリア', onTap: _clear),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Eyebrow('見つけた単語'),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: ListView.separated(
                        itemCount: _foundWords.length,
                        separatorBuilder: (_, _) => Container(
                          height: 1,
                          color: WoodColors.oakHi.withValues(alpha: 0.35),
                        ),
                        itemBuilder: (context, i) {
                          final w = _foundWords[i];
                          final tone = FloorPainter
                              .plankTones[i % FloorPainter.plankTones.length];
                          return _FoundWordRow(
                            entry: w,
                            isFavorite: widget.favorites.isFavorite(w.word),
                            toneTop: tone[0],
                            toneBottom: tone[1],
                            onSpeak: () => _speak(w.word.toLowerCase()),
                            onToggleFavorite: () async {
                              await widget.favorites.toggle(w.word);
                              setState(() {});
                            },
                          );
                        },
                      ),
                    ),
                  ),

                  // 時間切れ後：こんな単語も作れたよ
                  if (_timeUp && _suggestions.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    const Eyebrow('こんな単語も作れたよ'),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: _suggestions
                          .map((w) => _SuggestionChip(
                                entry: w,
                                onSpeak: () => _speak(w.word.toLowerCase()),
                              ))
                          .toList(),
                    ),
                  ],

                  // メッセージ
                  Text(
                    _message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, color: WoodColors.ink),
                  ),
                  const SizedBox(height: 16),

                  // スタート・提出
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      WoodButton(label: 'スタート', onTap: _startRound, big: true),
                      WoodButton(
                        label: '提出',
                        onTap: _submitWord,
                        big: true,
                        primary: true,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // 0になった瞬間の赤いフラッシュ（一度だけ）
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _flashOpacity,
                builder: (context, _) {
                  if (_flashOpacity.value <= 0) return const SizedBox.shrink();
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      color: WoodColors.danger
                          .withValues(alpha: _flashOpacity.value),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 作れた単語1つ分のデータ（単語＋日本語訳）
class _FoundWord {
  final String word;
  final String? meaning;
  const _FoundWord({required this.word, this.meaning});
}

// 作れた単語1つ分のチップ
// 見つけた単語1行＝床板1枚のカード。辞書画面の行と同じ考え方で、
// 行の高さを揃え、板の継ぎ目（影＋ハイライトの2重線）で区切ることで
// スクロールしても木目と単語が絶対にずれないようにしている。
class _FoundWordRow extends StatelessWidget {
  static const height = 64.0;

  final _FoundWord entry;
  final bool isFavorite;
  final Color toneTop;
  final Color toneBottom;
  final VoidCallback onSpeak;
  final VoidCallback onToggleFavorite;
  const _FoundWordRow({
    required this.entry,
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
      padding: const EdgeInsets.symmetric(horizontal: 12),
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
                  entry.word,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Fraunces',
                    fontWeight: FontWeight.w700,
                    color: WoodColors.ink,
                    fontSize: 16,
                  ),
                ),
                if (entry.meaning != null)
                  Text(
                    entry.meaning!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: WoodColors.ink.withValues(alpha: 0.72),
                      fontSize: 12,
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

// 時間切れ後の「こんな単語も作れたよ」チップ（タップで発音）
class _SuggestionChip extends StatelessWidget {
  final _FoundWord entry;
  final VoidCallback onSpeak;
  const _SuggestionChip({required this.entry, required this.onSpeak});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onSpeak,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: WoodColors.paper.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(9),
          boxShadow: [
            BoxShadow(
              color: WoodColors.oakGroove.withValues(alpha: 0.15),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              entry.word,
              style: const TextStyle(
                fontFamily: 'Fraunces',
                fontWeight: FontWeight.w700,
                color: WoodColors.ink,
                fontSize: 14,
              ),
            ),
            if (entry.meaning != null)
              Text(
                entry.meaning!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: WoodColors.ink.withValues(alpha: 0.72),
                  fontSize: 11,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// 木のタイル1枚
class _LetterTile extends StatelessWidget {
  final String letter;
  final bool used;
  final double flipT; // 0=裏向き, 1=表向き
  final VoidCallback onTap;
  const _LetterTile({
    required this.letter,
    required this.used,
    required this.flipT,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // 0→π回転させ、半分を過ぎたら表面に切り替える（鏡文字にならないよう角度を補正）
    final angle = flipT * pi;
    final showFront = angle >= pi / 2;
    final displayAngle = showFront ? angle - pi : angle;

    return GestureDetector(
      onTap: onTap,
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.001)
          ..rotateY(displayAngle),
        child: AnimatedOpacity(
          opacity: used ? 0.32 : 1.0,
          duration: const Duration(milliseconds: 150),
          child: showFront ? _buildFace(front: true) : _buildFace(front: false),
        ),
      ),
    );
  }

  Widget _buildFace({required bool front}) {
    return Container(
      width: 50,
      height: 50,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: front
              ? const [WoodColors.oakHi, WoodColors.oakMid]
              : const [WoodColors.inkSoft, WoodColors.ink],
        ),
        borderRadius: BorderRadius.circular(10),
        border: front
            ? null
            : Border.all(
                color: WoodColors.oakGroove.withValues(alpha: 0.6),
                width: 2,
              ),
        boxShadow: [
          BoxShadow(
            color: (front ? WoodColors.oakGroove : WoodColors.ink)
                .withValues(alpha: 0.55),
            offset: const Offset(0, 2),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            offset: const Offset(2, 6),
            blurRadius: 7,
          ),
        ],
      ),
      child: front
          ? Text(
              letter.toUpperCase(),
              style: const TextStyle(
                fontFamily: 'Fraunces',
                fontWeight: FontWeight.w700,
                fontSize: 24,
                color: WoodColors.ink,
              ),
            )
          : const Icon(Icons.diamond, size: 16, color: WoodColors.paper),
    );
  }
}

// 板が1枚敷かれて満ちていくように伸びるバー（スコア用）
class _WoodProgressRail extends StatelessWidget {
  final double fraction; // 0..1
  final bool flash;
  const _WoodProgressRail({required this.fraction, required this.flash});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 15,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: WoodColors.ink.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(4),
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        return Align(
          alignment: Alignment.centerLeft,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOut,
            width: constraints.maxWidth * fraction,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [WoodColors.oakHi, WoodColors.oakMid],
              ),
              border: Border(
                right: BorderSide(
                  color: WoodColors.oakGroove.withValues(alpha: 0.5),
                  width: 2,
                ),
              ),
              boxShadow: flash
                  ? [
                      BoxShadow(
                        color: WoodColors.paper.withValues(alpha: 0.9),
                        blurRadius: 14,
                        spreadRadius: 2,
                      ),
                    ]
                  : const [],
            ),
          ),
        );
      }),
    );
  }
}

// 残り時間ぶんだけ木目方向に縮むバー（タイマー用）。
// 残り5秒では、脈打つ光の帯がバーの中を左右に往復する。
class _TimerRail extends StatelessWidget {
  final double fraction; // 0..1
  final Color startColor;
  final Color endColor;
  final AnimationController? throbController;
  const _TimerRail({
    required this.fraction,
    required this.startColor,
    required this.endColor,
    required this.throbController,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 15,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: WoodColors.ink.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        final barWidth = constraints.maxWidth * fraction;
        return Stack(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 900),
              curve: Curves.linear,
              width: barWidth,
              height: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [startColor, endColor]),
              ),
            ),
            if (throbController != null)
              AnimatedBuilder(
                animation: throbController!,
                builder: (context, _) {
                  final beamWidth = barWidth * 0.5;
                  final left =
                      -beamWidth * 0.2 + (barWidth - beamWidth * 0.6) *
                          throbController!.value;
                  return Positioned(
                    left: left,
                    top: 0,
                    bottom: 0,
                    width: beamWidth,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            WoodColors.paper.withValues(alpha: 0.85),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        );
      }),
    );
  }
}
