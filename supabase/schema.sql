-- Word Battle — Supabase スキーマ
-- Supabaseダッシュボードの SQL Editor に貼って実行すると、対戦・ランキング・
-- レートに必要なテーブルと RLS（行レベルセキュリティ）が作られる。
-- 匿名認証（Anonymous sign-ins）を前提にしている。

-- ============================================================
-- テーブル
-- ============================================================

-- プレイヤー（プロフィール＋レート＋成績＋ハイスコア）
create table if not exists players (
  id           uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default 'ゲスト',
  rating       int  not null default 1200,   -- レート（Elo方式の初期値。対戦実装後に変動）
  wins         int  not null default 0,
  losses       int  not null default 0,
  best_score   int  not null default 0,       -- 1人プレイの自己ベストスコア（ハイスコアランキング用）
  games_played int  not null default 0,       -- 1人プレイの通算プレイ回数
  created_at   timestamptz not null default now()
);

-- 既存DB向けの追加（best_score / games_played を後から足す場合）。
-- create table は「if not exists」で既存テーブルを作り直さないため、
-- 途中から列を足すにはこの2行を実行する（何度実行しても安全）。
alter table players add column if not exists best_score   int not null default 0;
alter table players add column if not exists games_played int not null default 0;

-- 1試合
create table if not exists matches (
  id         uuid primary key default gen_random_uuid(),
  letters    text not null,                    -- お題の11文字
  status     text not null default 'waiting',  -- waiting / playing / finished
  created_at timestamptz not null default now(),
  started_at timestamptz,
  ended_at   timestamptz
);

-- 「どの試合に誰が出て何点取ったか」（matches と players の中間テーブル）
create table if not exists match_players (
  match_id      uuid not null references matches(id) on delete cascade,
  player_id     uuid not null references players(id) on delete cascade,
  score         int  not null default 0,
  rating_before int,
  rating_after  int,
  primary key (match_id, player_id)
);

-- 試合中に出された単語（重複判定・リプレイ用）
create table if not exists submitted_words (
  id         bigint generated always as identity primary key,
  match_id   uuid not null references matches(id) on delete cascade,
  player_id  uuid not null references players(id) on delete cascade,
  word       text not null,
  points     int  not null,
  created_at timestamptz not null default now()
);

-- ============================================================
-- RLS（行レベルセキュリティ）
-- publishable キーは公開値なので、これを設定しないと誰でも全データを
-- 読み書きできてしまう。必ず有効化すること。
-- ============================================================

alter table players         enable row level security;
alter table matches         enable row level security;
alter table match_players   enable row level security;
alter table submitted_words enable row level security;

-- players: 誰でも閲覧OK（ランキング表示用）／自分の行だけ作成・更新できる
create policy "players readable"  on players for select using (true);
create policy "insert own player" on players for insert with check (auth.uid() = id);
create policy "update own player" on players for update using (auth.uid() = id);

-- matches: ログイン済みなら閲覧・作成OK
create policy "matches readable"  on matches for select using (true);
create policy "create match"      on matches for insert
  with check (auth.uid() is not null);

-- match_players: 誰でも閲覧OK（対戦結果表示用）／自分の参加行だけ登録できる
create policy "mp readable"       on match_players for select using (true);
create policy "join as self"      on match_players for insert
  with check (auth.uid() = player_id);

-- submitted_words: 誰でも閲覧OK／自分の単語だけ登録できる
create policy "words readable"    on submitted_words for select using (true);
create policy "submit own word"   on submitted_words for insert
  with check (auth.uid() = player_id);

-- ============================================================
-- テーブル権限（GRANT）
-- RLSはあくまで「どの行を触れるか」の制御で、その手前に「テーブルを触る
-- 権限があるか」というPostgreSQLのGRANTがある。両方そろわないと操作できない。
-- 通常Supabaseは自動付与するが、環境によっては付かないので明示的に付ける。
-- 実際の行の可否はRLSが決めるので、ここは広めに許可してよい。
-- ============================================================

grant usage on schema public to anon, authenticated;

grant select, insert, update, delete
  on players, matches, match_players, submitted_words
  to anon, authenticated;

-- submitted_words の id（自動採番）が使うシーケンス用
grant usage, select on all sequences in schema public to anon, authenticated;
