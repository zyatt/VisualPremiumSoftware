import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../utils/update_service.dart';
import '../theme/app_theme.dart';

class AutoUpdateDialog extends StatefulWidget {
  final UpdateInfo updateInfo;

  const AutoUpdateDialog({super.key, required this.updateInfo});

  static Future<void> show(BuildContext context, UpdateInfo updateInfo) {
    return showDialog(
      context: context,
      barrierDismissible: !updateInfo.mandatory,
      builder: (_) => AutoUpdateDialog(updateInfo: updateInfo),
    );
  }

  @override
  State<AutoUpdateDialog> createState() => _AutoUpdateDialogState();
}

class _AutoUpdateDialogState extends State<AutoUpdateDialog> {
  bool _downloading = false;
  double _progress = 0;
  String? _error;

  Future<void> _startUpdate() async {
    setState(() {
      _downloading = true;
      _error = null;
      _progress = 0;
    });

    final error = await UpdateService.downloadAndInstallUpdate(
      widget.updateInfo.downloadUrl,
      (p) => setState(() => _progress = p),
    );

    if (mounted && error != null) {
      setState(() {
        _downloading = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.updateInfo;

    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 460,
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.system_update_rounded,
                    color: AppTheme.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Nova atualização disponível',
                        style: GoogleFonts.raleway(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'v${info.currentVersion}  →  v${info.latestVersion}',
                        style: GoogleFonts.nunito(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!info.mandatory && !_downloading)
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    color: AppTheme.textHint,
                    onPressed: () => Navigator.pop(context),
                  ),
              ],
            ),

            const SizedBox(height: 20),
            const Divider(color: AppTheme.divider),
            const SizedBox(height: 16),

            // Release notes
            if (info.releaseNotes.isNotEmpty) ...[
              Text(
                'O que há de novo',
                style: GoogleFonts.raleway(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 140),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.divider),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    info.releaseNotes,
                    style: GoogleFonts.nunito(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Barra de progresso
            if (_downloading) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _progress < 1.0 ? 'Baixando atualização...' : 'Instalando...',
                    style: GoogleFonts.nunito(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  Text(
                    '${(_progress * 100).toStringAsFixed(0)}%',
                    style: GoogleFonts.nunito(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: _progress,
                  minHeight: 8,
                  backgroundColor: AppTheme.surfaceVariant,
                  valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'O aplicativo será reiniciado automaticamente após a instalação.',
                style: GoogleFonts.nunito(
                  fontSize: 12,
                  color: AppTheme.textHint,
                ),
              ),
            ],

            // Erro
            if (_error != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.error.withValues(alpha: 0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        color: AppTheme.error, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: GoogleFonts.nunito(
                          fontSize: 12,
                          color: AppTheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Botões
            if (!_downloading) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (!info.mandatory)
                    OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Agora não'),
                    ),
                  if (!info.mandatory) const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _startUpdate,
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: Text(_error != null ? 'Tentar novamente' : 'Atualizar agora'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}