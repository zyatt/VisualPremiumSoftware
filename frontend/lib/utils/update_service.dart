import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class UpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final String downloadUrl;
  final String releaseNotes;
  final bool mandatory;

  UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.downloadUrl,
    required this.releaseNotes,
    required this.mandatory,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json, String currentVersion) {
    return UpdateInfo(
      currentVersion: currentVersion,
      latestVersion: json['latestVersion'] ?? '',
      downloadUrl: json['downloadUrl'] ?? '',
      releaseNotes: json['releaseNotes'] ?? '',
      mandatory: json['mandatory'] ?? false,
    );
  }
}

class UpdateService {
  static const String _updateCheckUrl = 'UPDATE_CHECK_URL';

  static void _log(String msg) {
    debugPrint('[UpdateService] $msg');
  }

  static Future<UpdateInfo?> checkForUpdates() async {
    try {
      _log('Iniciando verificação de atualização...');

      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      _log('Versão atual: $currentVersion');

      final apiUrl = dotenv.env[_updateCheckUrl];
      if (apiUrl == null || apiUrl.isEmpty) {
        _log('ERRO: UPDATE_CHECK_URL não definida no .env');
        return null;
      }
      _log('URL de verificação: $apiUrl');

      final response = await http.get(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      _log('Status HTTP: ${response.statusCode}');

      if (response.statusCode != 200) {
        _log('ERRO: Status não-200 recebido');
        return null;
      }

      final data = json.decode(response.body);
      Map<String, dynamic> updateData;

      if (data.containsKey('tag_name')) {
        _log('Formato detectado: GitHub Releases API');
        final latestVersion =
            (data['tag_name'] as String).replaceFirst(RegExp(r'^v'), '');

        final assets = data['assets'] as List?;
        if (assets == null || assets.isEmpty) {
          _log('ERRO: Nenhum asset encontrado no release');
          return null;
        }

        final exeAsset = assets.firstWhere(
          (a) => (a['name'] as String).toLowerCase().endsWith('.exe'),
          orElse: () => null,
        );

        if (exeAsset == null) {
          _log('ERRO: Nenhum .exe encontrado nos assets');
          return null;
        }

        updateData = {
          'latestVersion': latestVersion,
          'downloadUrl': exeAsset['browser_download_url'],
          'releaseNotes': data['body'] ?? '',
          'mandatory': false,
        };
      } else if (data.containsKey('latestVersion')) {
        _log('Formato detectado: JSON customizado');
        updateData = data;
      } else {
        _log('ERRO: Formato desconhecido. Chaves: ${data.keys.toList()}');
        return null;
      }

      final latestVersion = updateData['latestVersion'] as String;

      if (_shouldUpdate(currentVersion, latestVersion)) {
        _log('Atualização necessária: $currentVersion → $latestVersion');
        return UpdateInfo.fromJson(updateData, currentVersion);
      } else {
        _log('App já na versão mais recente ($currentVersion)');
        return null;
      }
    } catch (e, stack) {
      _log('EXCEÇÃO em checkForUpdates: $e');
      _log('Stack: $stack');
      return null;
    }
  }

  static bool _shouldUpdate(String current, String latest) {
    try {
      final c = current.split('.').map(int.parse).toList();
      final l = latest.split('.').map(int.parse).toList();
      for (int i = 0; i < 3; i++) {
        final cv = i < c.length ? c[i] : 0;
        final lv = i < l.length ? l[i] : 0;
        if (lv > cv) return true;
        if (lv < cv) return false;
      }
    } catch (e) {
      _log('ERRO ao comparar versões: $e');
    }
    return false;
  }

  static Future<String?> downloadAndInstallUpdate(
    String downloadUrl,
    Function(double) onProgress,
  ) async {
    try {
      _log('Iniciando download: $downloadUrl');

      final tempDir = await getTemporaryDirectory();
      final installerPath = '${tempDir.path}\\VisualPremiumSetup.exe';

      final request = http.Request('GET', Uri.parse(downloadUrl));
      final streamedResponse = await request.send();

      if (streamedResponse.statusCode != 200) {
        return 'Servidor retornou status ${streamedResponse.statusCode} ao baixar o instalador.';
      }

      final totalBytes = streamedResponse.contentLength ?? 0;
      int downloadedBytes = 0;
      final List<int> bytes = [];

      await for (final chunk in streamedResponse.stream) {
        bytes.addAll(chunk);
        downloadedBytes += chunk.length;
        if (totalBytes > 0) {
          onProgress(downloadedBytes / totalBytes);
        }
      }

      if (downloadedBytes == 0) {
        return 'Download falhou: nenhum byte recebido.';
      }

      final file = File(installerPath);
      await file.writeAsBytes(bytes, flush: true);
      onProgress(1.0);

      final fileSize = await file.length();
      if (fileSize == 0) {
        return 'Arquivo gravado está vazio (0 bytes). Verifique a URL de download.';
      }

      await Future.delayed(const Duration(milliseconds: 800));

      if (!await file.exists()) {
        return 'Arquivo não encontrado após gravação:\n$installerPath';
      }

      final process = await Process.start(
        installerPath,
        ['/SILENT', '/CLOSEAPPLICATIONS', '/RESTARTAPPLICATIONS'],
        mode: ProcessStartMode.detached,
      );
      _log('Processo iniciado. PID: ${process.pid}');

      await Future.delayed(const Duration(milliseconds: 500));
      exit(0);
    } catch (e, stack) {
      _log('EXCEÇÃO em downloadAndInstallUpdate: $e');
      _log('Stack: $stack');
      return 'Erro inesperado:\n$e';
    }
  }
}