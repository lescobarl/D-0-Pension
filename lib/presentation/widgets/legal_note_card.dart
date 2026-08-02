import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// A reusable card displaying a legal/informational note with an info icon.
///
/// Used across all views to eliminate duplicated [_buildLegalNote] methods.
///
/// Compact design for mobile with clear visual hierarchy.
class LegalNoteCard extends StatelessWidget {
  final String note;

  const LegalNoteCard({
    super.key,
    required this.note,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: AppTheme.accentLight.withValues(alpha: 0.15),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        side: BorderSide(color: AppTheme.accent.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingMd),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: AppTheme.fontSizeIcon, color: AppTheme.accent),
            const SizedBox(width: AppTheme.spacingSm),
            Expanded(
              child: Text(
                note,
                style: const TextStyle(
                  fontSize: AppTheme.fontSizeBodySmall,
                  color: AppTheme.textSecondary,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
