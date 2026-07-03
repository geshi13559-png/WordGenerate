import 'dart:math';
import 'package:flutter/material.dart';
import 'services/letter_generator.dart';
import 'services/word_validator.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final validator = WordValidator();
  await validator.loadDictionary();
  runApp(WordBattleApp(validator: validator));
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
  const WordBattleApp({super.key, required this.validator});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Word Battle',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: WoodColors.bg,
        fontFamily: 'Georgia',
      ),
      home: GameScreen(validator: validator),
    );
  }
}

class GameScreen extends StatefulWidget {
  final WordValidator validator;
  const GameScreen({super.key, required this.validator});

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

  List<String> _letters = [];       // 出たお題の文字
  List<bool> _used = [];            // 各タイルを使用済みか
  List<int> _selectedIndexes = [];  // 選んだタイルの順番（indexで記録）
  final Set<String> _usedWords = {}; // 既に得点に使った単語
  String _message = 'スタートを押してね';
  int _score = 0;

  @override
  void initState() {
    super.initState();
    _flipController = AnimationController(vsync: this, duration: _flipDuration);
  }

  @override
  void dispose() {
    _flipController.dispose();
    super.dispose();
  }

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
    setState(() {
      _letters = _generator.generate(count: 7);
      _used = List.filled(_letters.length, false);
      _selectedIndexes = [];
      _message = 'タイルをタップして単語を作ろう';
    });
    final totalMs = _flipInitialDelay.inMilliseconds +
        _flipDuration.inMilliseconds +
        _flipStagger.inMilliseconds * (_letters.length - 1);
    _flipController
      ..duration = Duration(milliseconds: totalMs)
      ..forward(from: 0);
  }

  void _tapTile(int index) {
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
    final word = _currentWord;
    final lowerWord = word.toLowerCase();
    final ok = widget.validator.validate(word, _letters);
    setState(() {
      if (word.isEmpty) {
        _message = '❌ 文字を選んでください';
      } else if (_usedWords.contains(lowerWord)) {
        _message = '❌ "$word" はすでに使われました';
      } else if (ok) {
        _score += word.length;
        _usedWords.add(lowerWord);
        _message = '⭕️ "$word" 正解！ +${word.length}点';
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
              // スコア
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: WoodColors.board,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'SCORE  $_score',
                  style: const TextStyle(
                    fontSize: 28,
                    color: WoodColors.cream,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
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
              const Spacer(),

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