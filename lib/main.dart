import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'services/letter_generator.dart';
import 'services/translator.dart';
import 'services/word_validator.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final validator = WordValidator();
  final translator = Translator();
  await Future.wait([
    validator.loadDictionary(),
    translator.loadDictionary(),
  ]);
  runApp(WordBattleApp(validator: validator, translator: translator));
}

// 明るいオーク材フローリング × インクブルー1色のカラーパレット
class WoodColors {
  static const oakHi = Color(0xFFF2DDAB);     // 板の明るいハイライト
  static const oakBase = Color(0xFFDDBC7C);   // 床のベース色
  static const oakMid = Color(0xFFC39A55);    // 板の陰側
  static const oakGroove = Color(0xFF8A5F2D); // 継ぎ目・木口の濃い色
  static const ink = Color(0xFF172444);       // アクセントのインクブルー
  static const inkSoft = Color(0xFF2F4576);
  static const paper = Color(0xFFFBF3DF);     // インクの上に乗る明るい文字色
  static const amber = Color(0xFFB5722A);     // 残り15秒
  static const amberSoft = Color(0xFFC98A3A);
  static const danger = Color(0xFFAC3A2E);    // 残り10秒・5秒
  static const dangerSoft = Color(0xFFC9503F);
}

class WordBattleApp extends StatelessWidget {
  final WordValidator validator;
  final Translator translator;
  const WordBattleApp({
    super.key,
    required this.validator,
    required this.translator,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Word Battle',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: WoodColors.oakBase,
        fontFamily: 'Archivo',
      ),
      home: GameScreen(validator: validator, translator: translator),
    );
  }
}

enum _TimerStage { calm, amber, red, critical }

class GameScreen extends StatefulWidget {
  final WordValidator validator;
  final Translator translator;
  const GameScreen({
    super.key,
    required this.validator,
    required this.translator,
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
  Timer? _roundTimer;
  int _timeLeft = _roundSeconds;
  bool _roundActive = false; // タイマーが進行中か（全部めくり終わってから時間切れまでtrue）
  bool _timeUp = false;      // 時間切れになったか

  List<String> _letters = [];       // 出たお題の文字
  List<bool> _used = [];            // 各タイルを使用済みか
  List<int> _selectedIndexes = [];  // 選んだタイルの順番（indexで記録）
  final Set<String> _usedWords = {}; // 既に得点に使った単語
  final List<_FoundWord> _foundWords = []; // 作れた単語（表示用）
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
        _usedWords.add(lowerWord);
        _foundWords.add(_FoundWord(
          word: word.toUpperCase(),
          meaning: widget.translator.translate(lowerWord),
        ));
        _message = '⭕️ "$word" 正解！ +1点';

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
          const Positioned.fill(
            child: RepaintBoundary(child: CustomPaint(painter: _FloorPainter())),
          ),

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
                  // スコアバー・タイマーバー
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _Eyebrow('SCORE'),
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
                          _Eyebrow('TIME', color: _timerStartColor),
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
                      _WoodButton(label: '← 1文字', onTap: _backspace),
                      const SizedBox(width: 16),
                      _WoodButton(label: 'クリア', onTap: _clear),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const _Eyebrow('見つけた単語'),
                  const SizedBox(height: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: _foundWords
                            .map((w) => _WordChip(
                                  entry: w,
                                  onSpeak: () => _speak(w.word.toLowerCase()),
                                ))
                            .toList(),
                      ),
                    ),
                  ),

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
                      _WoodButton(label: 'スタート', onTap: _startRound, big: true),
                      _WoodButton(
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

// 見出し用の小さなラベル（大文字・字間広め）
class _Eyebrow extends StatelessWidget {
  final String text;
  final Color color;
  const _Eyebrow(this.text, {this.color = WoodColors.ink});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontFamily: 'Archivo',
        fontWeight: FontWeight.w700,
        fontSize: 11,
        letterSpacing: 2,
        color: color.withValues(alpha: 0.6),
      ),
    );
  }
}

// 床：板目フローリングを描くCustomPainter
// 固定シードで生成するため、同じサイズなら毎回同じ板目になり、
// 再描画してもレイアウトが揺れない。
class _FloorPainter extends CustomPainter {
  const _FloorPainter();

  static const _plankTones = [
    [Color(0xFFF0DEAE), Color(0xFFE2C88C)],
    [Color(0xFFE6CD93), Color(0xFFD6B473)],
    [Color(0xFFDCC086), Color(0xFFC9A565)],
    [Color(0xFFEAD6A6), Color(0xFFDCBD82)],
    [Color(0xFFD8B878), Color(0xFFC7A05F)],
    [Color(0xFFE9D29C), Color(0xFFD9BB7E)],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random(1337);
    double y = 0;
    int prevTone = -1;

    while (y < size.height) {
      var plankH = 64 + rng.nextDouble() * 28;
      if (y + plankH > size.height) plankH = size.height - y;

      int toneIdx;
      do {
        toneIdx = rng.nextInt(_plankTones.length);
      } while (toneIdx == prevTone && _plankTones.length > 1);
      prevTone = toneIdx;
      final tone = _plankTones[toneIdx];

      final rect = Rect.fromLTWH(0, y, size.width, plankH);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: tone,
          ).createShader(rect),
      );

      // 板内部の木目（横方向の筋。長さ・濃さ・わずかなカーブをランダムに）
      final grainCount = (plankH / 6).round();
      for (var i = 0; i < grainCount; i++) {
        final gy = y + 3 + rng.nextDouble() * (plankH - 6);
        final len = size.width * (0.35 + rng.nextDouble() * 0.65);
        final gx = -20 + rng.nextDouble() * (size.width - len + 20);
        final path = Path()..moveTo(gx, gy);
        path.cubicTo(
          gx + len * 0.33,
          gy + (rng.nextDouble() * 2.8 - 1.4),
          gx + len * 0.66,
          gy + (rng.nextDouble() * 2.8 - 1.4),
          gx + len,
          gy,
        );
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.6 + rng.nextDouble() * 0.8
            ..color = const Color(0xFF6E4820)
                .withValues(alpha: 0.05 + rng.nextDouble() * 0.11),
        );
      }

      // たまに節目（ノット）を入れる
      if (rng.nextDouble() < 0.35) {
        final kx = size.width * (0.15 + rng.nextDouble() * 0.7);
        final ky = y + plankH / 2 + (rng.nextDouble() * 12 - 6);
        for (var r = 7.0; r > 0; r -= 2.5) {
          canvas.drawOval(
            Rect.fromCenter(center: Offset(kx, ky), width: r * 2, height: r * 1.1),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1
              ..color = const Color(0xFF5A3716)
                  .withValues(alpha: (0.16 - r * 0.01).clamp(0.0, 1.0)),
          );
        }
      }

      // 上端のわずかなハイライト（光沢）
      canvas.drawRect(
        Rect.fromLTWH(0, y, size.width, 2),
        Paint()..color = const Color(0xFFFFF8DE).withValues(alpha: 0.10),
      );

      // 継ぎ目の溝（濃い影 + すぐ下に明るいライン）
      final seamY = y + plankH;
      if (seamY < size.height) {
        canvas.drawRect(
          Rect.fromLTWH(0, seamY - 1, size.width, 1.6),
          Paint()..color = const Color(0xFF462C12).withValues(alpha: 0.55),
        );
        canvas.drawRect(
          Rect.fromLTWH(0, seamY + 0.6, size.width, 1),
          Paint()..color = const Color(0xFFFFF7DE).withValues(alpha: 0.30),
        );
      }

      y += plankH;
    }
  }

  @override
  bool shouldRepaint(covariant _FloorPainter oldDelegate) => false;
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

// 作れた単語1つ分のデータ（単語＋日本語訳）
class _FoundWord {
  final String word;
  final String? meaning;
  const _FoundWord({required this.word, this.meaning});
}

// 作れた単語1つ分のチップ
class _WordChip extends StatelessWidget {
  final _FoundWord entry;
  final VoidCallback onSpeak;
  const _WordChip({required this.entry, required this.onSpeak});

  @override
  Widget build(BuildContext context) {
    return Container(
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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: onSpeak,
            child: Container(
              width: 22,
              height: 22,
              decoration: const BoxDecoration(
                color: WoodColors.ink,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.volume_up,
                size: 13,
                color: WoodColors.paper,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                entry.word,
                style: const TextStyle(
                  fontFamily: 'Fraunces',
                  fontWeight: FontWeight.w700,
                  color: WoodColors.ink,
                  fontSize: 15,
                ),
              ),
              if (entry.meaning != null)
                Text(
                  entry.meaning!,
                  style: TextStyle(
                    color: WoodColors.ink.withValues(alpha: 0.72),
                    fontSize: 11,
                  ),
                ),
            ],
          ),
        ],
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

// ボタン（提出＝インク塗り／それ以外＝木の色）
class _WoodButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool big;
  final bool primary;
  const _WoodButton({
    required this.label,
    required this.onTap,
    this.big = false,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: big ? 30 : 18,
          vertical: big ? 15 : 11,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: primary
                ? const [WoodColors.inkSoft, WoodColors.ink]
                : const [WoodColors.oakHi, WoodColors.oakMid],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: (primary ? WoodColors.ink : WoodColors.oakGroove)
                  .withValues(alpha: 0.45),
              offset: const Offset(0, 3),
              blurRadius: 6,
            ),
          ],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: big ? 17 : 14,
            fontWeight: FontWeight.w700,
            color: primary ? WoodColors.paper : WoodColors.ink,
          ),
        ),
      ),
    );
  }
}
