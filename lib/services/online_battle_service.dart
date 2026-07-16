import 'package:supabase_flutter/supabase_flutter.dart';

/// 部屋を作った/入ったときの情報
class RoomInfo {
  final String matchId;
  final String? code; // ホスト（部屋作成）だけ持つ合言葉
  final String letters;
  final String? role; // ランダムマッチ時のみ 'host'（待機）/ 'guest'（即開始）
  const RoomInfo({
    required this.matchId,
    this.code,
    required this.letters,
    this.role,
  });

  bool get isWaiting => role == 'host'; // 相手を待つ側か
}

/// 単語提出の結果（サーバー採点）
class SubmitOutcome {
  final bool ok;
  final int points;   // 加点（ok時）
  final int score;    // 加点後の自分の合計
  final String? reason; // 失敗理由（not_a_word / duplicate / bad_letters など）
  const SubmitOutcome({
    required this.ok,
    this.points = 0,
    this.score = 0,
    this.reason,
  });
}

/// 対戦結果（決着後）
class MatchResult {
  final String status;   // playing / finished
  final String? winnerId;
  final int myScore;
  final int oppScore;
  final int? ratingBefore;
  final int? ratingAfter;
  const MatchResult({
    required this.status,
    this.winnerId,
    required this.myScore,
    required this.oppScore,
    this.ratingBefore,
    this.ratingAfter,
  });

  bool get finished => status == 'finished';
}

/// オンライン対戦（合言葉方式・サーバー計算）のRPC/Realtimeをまとめた部品。
/// 書き込みは全部サーバーのRPCが行い、こちらは呼ぶだけ。
class OnlineBattleService {
  SupabaseClient get _client => Supabase.instance.client;

  String? get myId => _client.auth.currentUser?.id;

  /// 部屋を作る（ホスト）。合言葉・お題・matchIdが返る。
  Future<RoomInfo> createRoom() async {
    final res = await _client.rpc('create_room') as Map<String, dynamic>;
    return RoomInfo(
      matchId: res['match_id'] as String,
      code: res['code'] as String,
      letters: res['letters'] as String,
    );
  }

  /// ランダムマッチ。待機中の相手がいれば即対戦開始（role=guest）、
  /// いなければ自分が待機ホストになる（role=host）。
  Future<RoomInfo> findMatch() async {
    final res = await _client.rpc('find_match') as Map<String, dynamic>;
    return RoomInfo(
      matchId: res['match_id'] as String,
      letters: res['letters'] as String,
      role: res['role'] as String?,
    );
  }

  /// 合言葉で部屋に入る（ゲスト）。成功すると対戦開始状態になる。
  /// 失敗時は PostgrestException が飛ぶ（room_not_found / room_full など）。
  Future<RoomInfo> joinRoom(String code) async {
    final res = await _client.rpc('join_room', params: {'p_code': code})
        as Map<String, dynamic>;
    return RoomInfo(
      matchId: res['match_id'] as String,
      letters: res['letters'] as String,
    );
  }

  /// 単語を提出。サーバーが検証・採点して結果を返す。
  Future<SubmitOutcome> submitWord(String matchId, String word) async {
    final res = await _client.rpc('submit_word', params: {
      'p_match': matchId,
      'p_word': word,
    }) as Map<String, dynamic>;
    return SubmitOutcome(
      ok: res['ok'] as bool? ?? false,
      points: res['points'] as int? ?? 0,
      score: res['score'] as int? ?? 0,
      reason: res['reason'] as String?,
    );
  }

  /// 対戦終了を申告。両者終了 or 時間切れなら決着＆レート更新される。
  Future<MatchResult> finishMatch(String matchId) async {
    final res = await _client.rpc('finish_match', params: {'p_match': matchId})
        as Map<String, dynamic>;
    return MatchResult(
      status: res['status'] as String? ?? 'playing',
      winnerId: res['winner_id'] as String?,
      myScore: res['my_score'] as int? ?? 0,
      oppScore: res['opp_score'] as int? ?? 0,
      ratingBefore: res['rating_before'] as int?,
      ratingAfter: res['rating_after'] as int?,
    );
  }

  /// 試合中の1件を取得（開始時刻・状態・お題などを読む）。
  Future<Map<String, dynamic>?> fetchMatch(String matchId) async {
    return await _client
        .from('matches')
        .select()
        .eq('id', matchId)
        .maybeSingle();
  }

  /// この試合の参加者スコアを取得（自分/相手）。
  Future<List<Map<String, dynamic>>> fetchPlayers(String matchId) async {
    final rows =
        await _client.from('match_players').select().eq('match_id', matchId);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// この試合で出された単語を取得（試合後に相手の単語を見せるのに使う）。
  Future<List<Map<String, dynamic>>> fetchSubmittedWords(String matchId) async {
    final rows = await _client
        .from('submitted_words')
        .select('player_id, word, points')
        .eq('match_id', matchId)
        .order('created_at', ascending: true);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// matches 行の変更を購読（status: waiting→playing→finished を受け取る）。
  RealtimeChannel subscribeMatch(
    String matchId,
    void Function(Map<String, dynamic> row) onChange,
  ) {
    final channel = _client.channel('match_$matchId');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'matches',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: matchId,
          ),
          callback: (payload) => onChange(payload.newRecord),
        )
        .subscribe();
    return channel;
  }

  /// match_players の変更を購読（相手が入室=insert、得点更新=update）。
  RealtimeChannel subscribePlayers(
    String matchId,
    void Function(Map<String, dynamic> row) onChange,
  ) {
    final channel = _client.channel('players_$matchId');
    for (final ev in [PostgresChangeEvent.insert, PostgresChangeEvent.update]) {
      channel.onPostgresChanges(
        event: ev,
        schema: 'public',
        table: 'match_players',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'match_id',
          value: matchId,
        ),
        callback: (payload) => onChange(payload.newRecord),
      );
    }
    channel.subscribe();
    return channel;
  }

  void removeChannel(RealtimeChannel channel) {
    _client.removeChannel(channel);
  }
}
