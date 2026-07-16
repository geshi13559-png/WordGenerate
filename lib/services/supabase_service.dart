import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_config.dart';

/// Supabaseへの接続状態を確認する部品
enum SupabaseConnectionStatus {
  notConfigured, // URL/キーが渡されていない
  connected,     // 接続確認OK
  failed,        // 接続失敗（URL/キーが違う・ネットワーク不通など）
}

/// プレイヤーのプロフィール（players テーブルの1行）
class Player {
  final String id;
  final String displayName;
  final int rating;
  final int wins;
  final int losses;
  final int bestScore;   // 1人プレイの自己ベスト
  final int gamesPlayed; // 1人プレイの通算回数

  const Player({
    required this.id,
    required this.displayName,
    required this.rating,
    required this.wins,
    required this.losses,
    this.bestScore = 0,
    this.gamesPlayed = 0,
  });

  factory Player.fromMap(Map<String, dynamic> map) => Player(
        id: map['id'] as String,
        displayName: map['display_name'] as String? ?? 'ゲスト',
        rating: map['rating'] as int? ?? 1200,
        wins: map['wins'] as int? ?? 0,
        losses: map['losses'] as int? ?? 0,
        bestScore: map['best_score'] as int? ?? 0,
        gamesPlayed: map['games_played'] as int? ?? 0,
      );

  Player copyWith({String? displayName, int? bestScore, int? gamesPlayed}) =>
      Player(
        id: id,
        displayName: displayName ?? this.displayName,
        rating: rating,
        wins: wins,
        losses: losses,
        bestScore: bestScore ?? this.bestScore,
        gamesPlayed: gamesPlayed ?? this.gamesPlayed,
      );
}

/// 1ゲームを記録した結果（終了画面に「自己ベスト更新！全国○位」を出すのに使う）
class GameResultOutcome {
  final int score;        // 今回のスコア
  final int bestScore;    // 記録後の自己ベスト
  final bool isNewBest;   // 今回で自己ベストを更新したか
  final int rank;         // 自己ベストでの全国順位（1位＝トップ）
  final int gamesPlayed;  // 記録後の通算プレイ回数

  const GameResultOutcome({
    required this.score,
    required this.bestScore,
    required this.isNewBest,
    required this.rank,
    required this.gamesPlayed,
  });
}

class SupabaseService {
  /// 接続情報が渡されていて初期化済みか
  bool get isEnabled => SupabaseConfig.isConfigured;

  SupabaseClient get _client => Supabase.instance.client;

  /// ログイン中のプレイヤー（未ログインならnull）
  Player? currentPlayer;

  /// このセッションで players 行を新規作成したか（初回の名前入力を促すのに使う）
  bool isNewPlayer = false;

  /// 接続確認。認証系のヘルスチェック（テーブル不要）を叩いて到達性を見る。
  /// publishable キーだけで 200 が返るので、URL/キーの妥当性を確認できる。
  Future<SupabaseConnectionStatus> checkConnection() async {
    if (!SupabaseConfig.isConfigured) {
      return SupabaseConnectionStatus.notConfigured;
    }
    try {
      final uri = Uri.parse('${SupabaseConfig.url}/auth/v1/health');
      final res = await http.get(
        uri,
        headers: {'apikey': SupabaseConfig.publishableKey},
      ).timeout(const Duration(seconds: 8));
      return res.statusCode == 200
          ? SupabaseConnectionStatus.connected
          : SupabaseConnectionStatus.failed;
    } catch (_) {
      return SupabaseConnectionStatus.failed;
    }
  }

  /// 匿名ログインし、自分の players 行を用意して返す。
  /// ・セッションが無ければ匿名サインイン（メール・パスワード不要）
  /// ・players に自分の行がまだ無ければ作成（初回のみ）
  /// 失敗時やオフライン時は null を返す（オンライン機能を無効化するだけ）
  Future<Player?> signInAndLoadPlayer() async {
    if (!isEnabled) return null;
    try {
      var session = _client.auth.currentSession;
      session ??= (await _client.auth.signInAnonymously()).session;
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return null;

      // 既存の行を探す
      final existing = await _client
          .from('players')
          .select()
          .eq('id', uid)
          .maybeSingle();

      Map<String, dynamic> row;
      if (existing == null) {
        // 初回：自分の行を作る
        row = await _client
            .from('players')
            .insert({'id': uid})
            .select()
            .single();
        isNewPlayer = true;
      } else {
        row = existing;
      }

      currentPlayer = Player.fromMap(row);
      return currentPlayer;
    } catch (_) {
      return null;
    }
  }

  /// ランキング（レートの高い順）を取得する。
  /// 誰でも閲覧できる（RLSで players は select using(true)）。
  /// オフライン・失敗時は空リストを返す。
  Future<List<Player>> fetchRanking({int limit = 100}) async {
    if (!isEnabled) return [];
    try {
      final rows = await _client
          .from('players')
          .select()
          .order('best_score', ascending: false)
          .order('games_played', ascending: true)
          .limit(limit);
      return (rows as List)
          .map((r) => Player.fromMap(r as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 表示名を更新する
  Future<void> updateDisplayName(String name) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    await _client.from('players').update({'display_name': trimmed}).eq('id', uid);
    currentPlayer = currentPlayer?.copyWith(displayName: trimmed);
  }

  /// 1人プレイ1ゲームの結果を記録する。
  /// ・matches / match_players に履歴を残す（オンライン対戦の土台）
  /// ・自己ベスト更新なら players.best_score を更新し、games_played を+1
  /// ・記録後の自己ベストでの全国順位を計算して返す
  /// オフライン・失敗時は null（記録できないだけで、ゲームは続行できる）。
  Future<GameResultOutcome?> recordGameResult({
    required String letters,
    required int score,
  }) async {
    if (!isEnabled) return null;
    final uid = _client.auth.currentUser?.id;
    final player = currentPlayer;
    if (uid == null || player == null) return null;
    try {
      // 1人プレイは自己ベスト（players 行）だけ更新する。
      // matches / match_players はオンライン対戦専用で、クライアントからは
      // 直接書けない（サーバーRPCのみ）。letters は今は未使用。
      final isNewBest = score > player.bestScore;
      final newBest = isNewBest ? score : player.bestScore;
      final newGames = player.gamesPlayed + 1;

      await _client.from('players').update({
        'best_score': newBest,
        'games_played': newGames,
      }).eq('id', uid);
      currentPlayer =
          player.copyWith(bestScore: newBest, gamesPlayed: newGames);

      // 自己ベストでの全国順位＝自分よりベストが高い人数＋1
      // （プレイヤー数は多くないので、該当行を引いて数えるだけで十分）
      final higher = await _client
          .from('players')
          .select('id')
          .gt('best_score', newBest);
      final rank = (higher as List).length + 1;

      return GameResultOutcome(
        score: score,
        bestScore: newBest,
        isNewBest: isNewBest,
        rank: rank,
        gamesPlayed: newGames,
      );
    } catch (_) {
      return null;
    }
  }
}
