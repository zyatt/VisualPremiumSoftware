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
      barrierDismissible: true,
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

    return PopScope(
      canPop: !_downloading,
      child: Dialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 460,
          padding: const EdgeInsets.all(28),
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'v${info.currentVersion}  →  v${info.latestVersion}',
                        style: GoogleFonts.nunito(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!_downloading)
                  IconButton(
                    icon: Icon(Icons.close_rounded, size: 20),
                    color: Theme.of(context).colorScheme.outline,
                    onPressed: () => Navigator.pop(context),
                    style: IconButton.styleFrom().copyWith(
                        mouseCursor: WidgetStateProperty.all(
                            SystemMouseCursors.click)),
                  ),
              ],
            ),

            SizedBox(height: 20),
            Divider(color: Theme.of(context).colorScheme.outlineVariant),
            SizedBox(height: 16),

            if (info.releaseNotes.isNotEmpty) ...[
              Text(
                'O que há de novo',
                style: GoogleFonts.raleway(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              SizedBox(height: 8),
              Container(
                width: double.infinity,
                constraints: BoxConstraints(maxHeight: 140),
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    info.releaseNotes,
                    style: GoogleFonts.nunito(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],

            if (_downloading) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _progress < 1.0 ? 'Baixando atualização...' : 'Instalando...',
                    style: GoogleFonts.nunito(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
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
              SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: _progress,
                  minHeight: 8,
                  backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
                ),
              ),
              SizedBox(height: 8),
              Text(
                'O aplicativo será reiniciado automaticamente após a instalação.',
                style: GoogleFonts.nunito(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ],

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

            if (!_downloading) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom().copyWith(
                        mouseCursor: WidgetStateProperty.all(
                            SystemMouseCursors.click)),
                    child: const Text('Mais tarde'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _startUpdate,
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: Text(_error != null ? 'Tentar novamente' : 'Atualizar agora'),
                    style: ElevatedButton.styleFrom().copyWith(
                        mouseCursor: WidgetStateProperty.all(
                            SystemMouseCursors.click)),
                  ),
                ],
              ),
            ],
          ],
        ),
        ),
      ),
    );
  }
}