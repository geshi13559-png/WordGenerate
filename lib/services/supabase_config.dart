/// Supabaseの接続情報。
///
/// 値はソースに埋め込まず、起動時に --dart-define で渡す：
///   flutter run \
///     --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///     --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_xxx
///
/// publishable キーはクライアント埋め込み用の公開可能な値だが、Gitに残さない
/// ため環境変数で渡している。secret キーはここには絶対に入れないこと。
class SupabaseConfig {
  static const url = String.fromEnvironment('SUPABASE_URL');
  static const publishableKey =
      String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  /// 接続情報が渡されているか（未設定ならオンライン機能は無効化する）
  static bool get isConfigured => url.isNotEmpty && publishableKey.isNotEmpty;
}
