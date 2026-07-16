-- ============================================================
-- Word Battle — オンライン対戦（合言葉方式・サーバー計算）
-- ・単語の正解判定と採点、レート計算をすべてサーバー側(RPC)で行う
-- ・クライアントは matches / match_players / submitted_words を直接書けない
--   （不正防止）。書き込みは下の RPC 経由のみ。
-- 先に words テーブルへ CSV(supabase/words.csv) を投入してから実行すること。
-- ============================================================

-- ---------- 0. スキーマ追加 ----------
alter table matches add column if not exists code      text;  -- 合言葉（4文字）
alter table matches add column if not exists mode      text not null default 'solo'; -- solo / online
alter table matches add column if not exists winner_id uuid;  -- 勝者（引き分けは null）
alter table match_players add column if not exists done boolean not null default false; -- 自分が終了したか

-- 待機中/進行中の部屋をコードで早く引けるように
create index if not exists idx_matches_code on matches(code) where status in ('waiting','playing');

-- ---------- 1. サーバー辞書（word,points）----------
-- ※テーブルは Table Editor で作成し、words.csv をインポートしてから本SQLを流す。
--   もし未作成ならここで作る（空のまま。CSVは別途インポート）。
create table if not exists words (
  word   text primary key,
  points int  not null
);

-- ---------- 2. 内部ヘルパー関数 ----------

-- お題文字を生成（クライアント LetterGenerator と同じ規則）
create or replace function gen_letters(cnt int default 11)
returns text language plpgsql as $$
declare
  weighted text := 'eeeeeeeeeeeetttttttttttaaaaaaaaaooooooooiiiiiiinnnnnnnsssssssrrrrrrhhhhhhddddllllccccuuuummmmwwffggyypbvkjxqz';
  vowels   text := 'aeiou';
  res  text[] := '{}';
  ch   text;
  vcnt int;
  repl int[];
  result_str text;
begin
  -- 母音を2つ保証（同じ母音は2個まで）
  loop
    select count(*) into vcnt from unnest(res) c where position(c in vowels) > 0;
    exit when vcnt >= 2;
    ch := substr(vowels, 1 + floor(random()*length(vowels))::int, 1);
    if (select count(*) from unnest(res) c where c = ch) < 2 then
      res := array_append(res, ch);
    end if;
  end loop;
  -- 残りを重み付きで埋める（母音は上限2個まで）
  while coalesce(array_length(res,1),0) < cnt loop
    ch := substr(weighted, 1 + floor(random()*length(weighted))::int, 1);
    if position(ch in vowels) > 0 then
      if (select count(*) from unnest(res) c where c = ch) < 2 then
        res := array_append(res, ch);
      end if;
    else
      res := array_append(res, ch);
    end if;
  end loop;
  -- q があって u が無ければ、q以外の子音1つを u に置換
  if 'q' = any(res) and not ('u' = any(res)) then
    select array_agg(i) into repl
      from generate_subscripts(res,1) i
      where res[i] <> 'q' and position(res[i] in vowels) = 0;
    if repl is not null then
      res[repl[1 + floor(random()*array_length(repl,1))::int]] := 'u';
    end if;
  end if;
  -- シャッフルして文字列化
  select string_agg(c, '' order by random()) into result_str from unnest(res) c;
  return result_str;
end; $$;

-- 単語が letters（多重集合）だけで作れるか
create or replace function can_form(letters text, word text)
returns boolean language plpgsql as $$
declare pool text := letters; i int; ch text; pos int;
begin
  for i in 1..length(word) loop
    ch  := substr(word, i, 1);
    pos := position(ch in pool);
    if pos = 0 then return false; end if;
    pool := overlay(pool placing '' from pos for 1); -- 使った1文字を消す
  end loop;
  return true;
end; $$;

-- 紛らわしい文字を除いた4文字の合言葉を生成（進行中の部屋と衝突しないもの）
-- ※変数名は v_code。matches.code 列と同名にすると曖昧参照エラーになるため。
create or replace function gen_room_code()
returns text language plpgsql as $$
declare chars text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; v_code text; i int;
begin
  loop
    v_code := '';
    for i in 1..4 loop
      v_code := v_code || substr(chars, 1 + floor(random()*length(chars))::int, 1);
    end loop;
    exit when not exists (
      select 1 from matches m where m.code = v_code and m.status in ('waiting','playing')
    );
  end loop;
  return v_code;
end; $$;

-- ---------- 3. RPC（クライアントが呼ぶ入口。すべてサーバー権限で実行）----------

-- 部屋を作る（ホスト）。合言葉とお題を発行して待機状態にする。
create or replace function create_room()
returns json language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); mid uuid; c text; lt text;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  c  := gen_room_code();
  lt := gen_letters(11);
  insert into matches(letters, status, code, mode)
    values (lt, 'waiting', c, 'online') returning id into mid;
  insert into match_players(match_id, player_id, score) values (mid, uid, 0);
  return json_build_object('match_id', mid, 'code', c, 'letters', lt);
end; $$;

-- 合言葉で部屋に入る（ゲスト）。2人そろったら開始（playing・開始時刻を刻む）。
create or replace function join_room(p_code text)
returns json language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); m matches;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select * into m from matches
    where code = upper(trim(p_code)) and status = 'waiting'
    order by created_at desc limit 1 for update;
  if not found then raise exception 'room_not_found'; end if;
  if exists (select 1 from match_players where match_id = m.id and player_id = uid) then
    raise exception 'already_joined';
  end if;
  if (select count(*) from match_players where match_id = m.id) >= 2 then
    raise exception 'room_full';
  end if;
  insert into match_players(match_id, player_id, score) values (m.id, uid, 0);
  -- 開始は13秒後に予約（最初5秒は無表示＋準備8秒）
  update matches set status = 'playing', started_at = now() + interval '13 seconds' where id = m.id;
  return json_build_object('match_id', m.id, 'letters', m.letters);
end; $$;

-- ランダムマッチ（合言葉なし）。待機中のランダム部屋があれば入り、無ければ作って待つ。
-- ランダム部屋は code = null で見分ける（合言葉部屋は code あり）。
-- for update skip locked で、同時に押した2人が同じ部屋を奪い合わないようにする。
create or replace function find_match()
returns json language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); m matches;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  -- 自分以外が待っているランダム部屋を1つ確保
  select * into m from matches
    where status = 'waiting' and code is null and mode = 'online'
      and not exists (
        select 1 from match_players mp where mp.match_id = matches.id and mp.player_id = uid
      )
    order by created_at asc
    for update skip locked
    limit 1;
  if found then
    insert into match_players(match_id, player_id, score) values (m.id, uid, 0);
    -- 開始は13秒後に予約（最初5秒は無表示＋準備8秒）
    update matches set status = 'playing', started_at = now() + interval '13 seconds' where id = m.id;
    return json_build_object('match_id', m.id, 'letters', m.letters, 'role', 'guest');
  end if;
  -- 無ければ自分がホストとして待機部屋を作る（code なし＝ランダム）
  insert into matches(letters, status, code, mode)
    values (gen_letters(11), 'waiting', null, 'online') returning * into m;
  insert into match_players(match_id, player_id, score) values (m.id, uid, 0);
  return json_build_object('match_id', m.id, 'letters', m.letters, 'role', 'host');
end; $$;

-- 単語を提出。サーバーが検証＋採点し、スコアを加算して返す。
create or replace function submit_word(p_match uuid, p_word text)
returns json language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); m matches; w text := lower(trim(p_word)); pts int; newscore int;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select * into m from matches where id = p_match;
  if not found then raise exception 'no_match'; end if;
  if m.status <> 'playing' then return json_build_object('ok', false, 'reason', 'not_playing'); end if;
  if not exists (select 1 from match_players where match_id = p_match and player_id = uid) then
    raise exception 'not_participant';
  end if;
  -- カウントダウン中（開始時刻前）はまだ提出できない
  if now() < m.started_at then
    return json_build_object('ok', false, 'reason', 'not_started');
  end if;
  -- 制限時間：開始から95秒（固定90秒＋通信の猶予5秒。オンラインは時間ボーナス無し）
  if now() > m.started_at + interval '95 seconds' then
    return json_build_object('ok', false, 'reason', 'time_up');
  end if;
  if length(w) < 2 then return json_build_object('ok', false, 'reason', 'too_short'); end if;
  if not can_form(m.letters, w) then return json_build_object('ok', false, 'reason', 'bad_letters'); end if;
  select points into pts from words where word = w;
  if pts is null then return json_build_object('ok', false, 'reason', 'not_a_word'); end if;
  if exists (select 1 from submitted_words where match_id = p_match and player_id = uid and word = w) then
    return json_build_object('ok', false, 'reason', 'duplicate');
  end if;
  insert into submitted_words(match_id, player_id, word, points) values (p_match, uid, w, pts);
  update match_players set score = score + pts
    where match_id = p_match and player_id = uid returning score into newscore;
  return json_build_object('ok', true, 'points', pts, 'score', newscore, 'word', w);
end; $$;

-- 対戦終了を申告。両者が終了 or 時間切れなら勝敗を判定し Elo レートを更新（1回だけ）。
create or replace function finish_match(p_match uuid)
returns json language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  m   matches;
  pa uuid; pb uuid; sa int; sb int; ra int; rb int;
  ea float; resa float; na int; nb int; k int := 32;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  -- 自分を「終了」に
  update match_players set done = true where match_id = p_match and player_id = uid;

  select * into m from matches where id = p_match for update;  -- 決着処理を直列化
  if not found then raise exception 'no_match'; end if;

  -- まだ決着していなくて、両者終了 or 時間切れなら精算する
  if m.status <> 'finished'
     and ( (select count(*) from match_players where match_id = p_match and done) >= 2
           or now() > m.started_at + interval '95 seconds' ) then
    select player_id, score into pa, sa from match_players where match_id = p_match order by player_id limit 1;
    select player_id, score into pb, sb from match_players where match_id = p_match and player_id <> pa limit 1;
    select rating into ra from players where id = pa;
    select rating into rb from players where id = pb;

    ea   := 1.0 / (1.0 + power(10.0, (rb - ra) / 400.0));
    resa := case when sa > sb then 1.0 when sa = sb then 0.5 else 0.0 end;
    na   := round(ra + k * (resa - ea));
    nb   := round(rb + k * ((1.0 - resa) - (1.0 - ea)));

    update players set rating = na,
      wins   = wins   + (case when resa = 1.0 then 1 else 0 end),
      losses = losses + (case when resa = 0.0 then 1 else 0 end)
      where id = pa;
    update players set rating = nb,
      wins   = wins   + (case when resa = 0.0 then 1 else 0 end),
      losses = losses + (case when resa = 1.0 then 1 else 0 end)
      where id = pb;

    update match_players set rating_before = ra, rating_after = na where match_id = p_match and player_id = pa;
    update match_players set rating_before = rb, rating_after = nb where match_id = p_match and player_id = pb;
    update matches set status = 'finished', ended_at = now(),
      winner_id = case when sa > sb then pa when sb > sa then pb else null end
      where id = p_match;
  end if;

  -- 呼び出したプレイヤー視点の結果を返す（未決着なら status=playing のまま）
  select status into m.status from matches where id = p_match;
  return (
    select json_build_object(
      'status',       mt.status,
      'winner_id',    mt.winner_id,
      'my_score',     me.score,
      'opp_score',    opp.score,
      'rating_before',me.rating_before,
      'rating_after', me.rating_after
    )
    from matches mt
    join match_players me  on me.match_id = mt.id and me.player_id = uid
    left join match_players opp on opp.match_id = mt.id and opp.player_id <> uid
    where mt.id = p_match
  );
end; $$;

-- ---------- 4. 権限（不正防止の要）----------
-- クライアントは matches / match_players / submitted_words を直接書けない。
-- 書き込みは上の RPC（SECURITY DEFINER）だけが行う。
revoke insert, update, delete on matches         from anon, authenticated;
revoke insert, update, delete on match_players   from anon, authenticated;
revoke insert, update, delete on submitted_words from anon, authenticated;

-- players はレートだけサーバー専用にする（表示名・自己ベストは本人が更新可）。
revoke update on players from anon, authenticated;
grant  update (display_name, best_score, games_played) on players to anon, authenticated;

-- RPC の実行権限
grant execute on function create_room()                to anon, authenticated;
grant execute on function find_match()                 to anon, authenticated;
grant execute on function join_room(text)              to anon, authenticated;
grant execute on function submit_word(uuid, text)      to anon, authenticated;
grant execute on function finish_match(uuid)           to anon, authenticated;

-- ---------- 5. Realtime（相手の得点・状態をライブ受信）----------
-- matches / match_players の変更を購読できるようにする（RLSのSELECTは既に true）。
-- 何度実行しても大丈夫なように、未登録のときだけ追加する。
do $$
begin
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and tablename = 'matches') then
    alter publication supabase_realtime add table matches;
  end if;
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and tablename = 'match_players') then
    alter publication supabase_realtime add table match_players;
  end if;
end $$;
