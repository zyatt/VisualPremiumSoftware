import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

class UpdateChecker {
  static Future<void> checkForUpdates(BuildContext context) async {
    try {
      final url = dotenv.env['UPDATE_CHECK_URL'];
      if (url == null || url.isEmpty) return;

      final info = await PackageInfo.fromPlatform();
      final current = info.version;

      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return;

      final latest = res.body.trim();
      if (latest != current && context.mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Atualização disponível'),
            content: Text('Nova versão: $latest\nVersão atual: $current'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar')),
            ],
          ),
        );
      }
    } catch (_) {
      // Silencioso — update check não pode travar o app
    }
  }
}
