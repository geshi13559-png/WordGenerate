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

// 木目カラーパレット
class WoodColors {
  static const bg = Color(0xFF3E2A1E);        // 濃い木の背景
  static const board = Color(0xFF5C4033);     // ボード
  static const tile = Color(0xFFD9B382);      // タイル（明るい木）
  static const tileDark = Color(0xFFB8905C);  // タイルの影側
  static const text = Color(0xFF3E2A1E);      // 文字（濃茶）
  static const cream = Color(0xFFF5E6C8);     // 明るいクリーム
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
        scaffoldBackgroundColor: WoodColors.bg,
        fontFamily: 'Georgia',
      ),
      home: GameScreen(validator: validator, translator: translator),
    );
  }
}

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
    with SingleTickerProviderStateMixin {
  final _generator = LetterGenerator();

  // 1枚ごとのフリップ時間・隣のタイルとの発火間隔・最初のタメ
  // stagger > duration にして「前の1枚がめくり終わってから次」の間を作り、緊張感を出す
  static const _flipDuration = Duration(milliseconds: 300);
  static const _flipStagger = Duration(milliseconds: 450);
  static const _flipInitialDelay = Duration(milliseconds: 250);

  late final AnimationController _flipController;
  final _tts = FlutterTts();

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
  }

  @override
  void dispose() {
    _flipController.dispose();
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
      } else {
        _message = '❌ "$word" は無効です';
      }
      _clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // スコア・タイマー
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: WoodColors.board,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'SCORE  $_score',
                      style: const TextStyle(
                        fontSize: 24,
                        color: WoodColors.cream,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: WoodColors.board,
                      borderRadius: BorderRadius.circular(12),
                      border: _roundActive && _timeLeft <= 10
                          ? Border.all(color: Colors.redAccent, width: 2)
                          : null,
                    ),
                    child: Text(
                      '⏱ $_timeLeft',
                      style: TextStyle(
                        fontSize: 24,
                        color: _roundActive && _timeLeft <= 10
                            ? Colors.redAccent
                            : WoodColors.cream,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // 組み立て中の単語を表示するトレイ
              Container(
                width: double.infinity,
                height: 70,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: WoodColors.board,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: WoodColors.tileDark, width: 3),
                ),
                child: Text(
                  _currentWord.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 32,
                    color: WoodColors.cream,
                    letterSpacing: 6,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // お題のタイル
              AnimatedBuilder(
                animation: _flipController,
                builder: (context, child) {
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
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
              const SizedBox(height: 24),

              // 消す・クリアボタン
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _WoodButton(label: '← 1文字', onTap: _backspace),
                  const SizedBox(width: 16),
                  _WoodButton(label: 'クリア', onTap: _clear),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                '作った単語',
                style: TextStyle(color: WoodColors.cream, fontSize: 14),
              ),
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
                style: const TextStyle(fontSize: 18, color: WoodColors.cream),
              ),
              const SizedBox(height: 16),

              // スタート・提出
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _WoodButton(label: 'スタート', onTap: _startRound, big: true),
                  _WoodButton(label: '提出', onTap: _submitWord, big: true),
                ],
              ),
            ],
          ),
        ),
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
class _WordChip extends StatelessWidget {
  final _FoundWord entry;
  final VoidCallback onSpeak;
  const _WordChip({required this.entry, required this.onSpeak});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: WoodColors.board,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: WoodColors.tileDark, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: onSpeak,
            child: const Icon(
              Icons.volume_up,
              size: 16,
              color: WoodColors.cream,
            ),
          ),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                entry.word,
                style: const TextStyle(
                  color: WoodColors.cream,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              if (entry.meaning != null)
                Text(
                  entry.meaning!,
                  style: const TextStyle(
                    color: WoodColors.tile,
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
          opacity: used ? 0.3 : 1.0,
          duration: const Duration(milliseconds: 150),
          child: showFront ? _buildFace(front: true) : _buildFace(front: false),
        ),
      ),
    );
  }

  Widget _buildFace({required bool front}) {
    return Container(
      width: 56,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: front
              ? const [WoodColors.tile, WoodColors.tileDark]
              : const [WoodColors.board, WoodColors.bg],
        ),
        borderRadius: BorderRadius.circular(10),
        border: front
            ? null
            : Border.all(color: WoodColors.tileDark, width: 2),
        boxShadow: const [
          BoxShadow(
            color: Colors.black45,
            offset: Offset(2, 3),
            blurRadius: 4,
          ),
        ],
      ),
      child: front
          ? Text(
              letter.toUpperCase(),
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: WoodColors.text,
              ),
            )
          : const Icon(Icons.diamond, size: 18, color: WoodColors.tileDark),
    );
  }
}

// 木のボタン
class _WoodButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool big;
  const _WoodButton({
    required this.label,
    required this.onTap,
    this.big = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: big ? 32 : 20,
          vertical: big ? 16 : 12,
        ),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [WoodColors.tile, WoodColors.tileDark],
          ),
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [
            BoxShadow(
              color: Colors.black45,
              offset: Offset(1, 2),
              blurRadius: 3,
            ),
          ],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: big ? 20 : 16,
            fontWeight: FontWeight.bold,
            color: WoodColors.text,
          ),
        ),
      ),
    );
  }
}