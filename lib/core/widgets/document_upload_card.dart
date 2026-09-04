import 'dart:io';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class DocumentUploadCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final File? file;
  final bool isUploading;
  final double? uploadProgress;
  final String? error;
  final VoidCallback onPick;
  final VoidCallback? onRemove;

  const DocumentUploadCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.file,
    this.isUploading = false,
    this.uploadProgress,
    this.error,
    required this.onPick,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: error != null
              ? AppTheme.error
              : file != null
                  ? AppTheme.primaryGreen.withOpacity(0.3)
                  : AppTheme.cardBorder,
          width: file != null ? 1.5 : 1,
        ),
      ),
      child: file != null ? _buildPreview() : _buildEmpty(),
    );
  }

  Widget _buildEmpty() {
    return InkWell(
      onTap: isUploading ? null : onPick,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppTheme.primaryGreen.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: isUploading
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        value: uploadProgress,
                        color: AppTheme.primaryGreen,
                      ),
                    )
                  : const Icon(Icons.add_a_photo_outlined,
                      color: AppTheme.primaryGreen, size: 24),
            ),
            const SizedBox(height: 12),
            Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: AppTheme.textPrimary)),
            const SizedBox(height: 4),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.textMuted)),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(error!,
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.error)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(
            file!,
            width: double.infinity,
            height: 160,
            fit: BoxFit.cover,
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: Row(
            children: [
              _circleIcon(Icons.refresh, onTap: onPick),
              if (onRemove != null) ...[
                const SizedBox(width: 6),
                _circleIcon(Icons.close, onTap: onRemove),
              ],
            ],
          ),
        ),
        if (isUploading)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: CircularProgressIndicator(
                  value: uploadProgress,
                  color: Colors.white,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _circleIcon(IconData icon, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: const BoxDecoration(
          color: Colors.black54,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }
}
