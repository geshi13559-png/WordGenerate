import 'package:http/http.dart' as http;
import 'supabase_config.dart';

/// Supabaseへの接続状態を確認する部品
enum SupabaseConnectionStatus {
  notConfigured, // URL/キーが渡されていない
  connected,     // 接続確認OK
  failed,        // 接続失敗（URL/キーが違う・ネットワーク不通など）
}

class SupabaseService {
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
}
