import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/game_theme.dart';

class EditPlayerNameModal extends StatefulWidget {
  final GameTheme theme;
  final String currentName;
  final ValueChanged<String> onSave;

  const EditPlayerNameModal({
    super.key,
    required this.theme,
    required this.currentName,
    required this.onSave,
  });

  static Future<String?> show(
    BuildContext context, {
    required GameTheme theme,
    required String currentName,
    required ValueChanged<String> onSave,
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => EditPlayerNameModal(
        theme: theme,
        currentName: currentName,
        onSave: onSave,
      ),
    );
  }

  @override
  State<EditPlayerNameModal> createState() => _EditPlayerNameModalState();
}

class _EditPlayerNameModalState extends State<EditPlayerNameModal> {
  late TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.currentName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _handleSave() {
    final trimmed = _nameController.text.trim();
    if (trimmed.isNotEmpty) {
      FocusScope.of(context).unfocus();
      Navigator.of(context).pop(trimmed);
      widget.onSave(trimmed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 380),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: theme.panelBg.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: theme.accentColor.withValues(alpha: 0.6),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: theme.accentColor.withValues(alpha: 0.25),
              blurRadius: 30,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.badge_outlined, color: theme.accentColor, size: 22),
                const SizedBox(width: 8),
                Text(
                  'EDIT GAMER TAG',
                  style: GoogleFonts.orbitron(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2.0,
                    color: theme.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              maxLength: 14,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _handleSave(),
              style: TextStyle(
                color: theme.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
              decoration: InputDecoration(
                hintText: 'Enter gamer tag...',
                hintStyle: TextStyle(
                  color: theme.textPrimary.withValues(alpha: 0.4),
                ),
                filled: true,
                fillColor: theme.tileDefault.withValues(alpha: 0.3),
                counterStyle: TextStyle(
                  color: theme.textPrimary.withValues(alpha: 0.5),
                  fontSize: 10,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: theme.panelBorder.withValues(alpha: 0.4),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: theme.accentColor, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    FocusScope.of(context).unfocus();
                    Navigator.of(context).pop();
                  },
                  child: Text(
                    'CANCEL',
                    style: TextStyle(
                      color: theme.textPrimary.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _handleSave,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.accentColor,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'SAVE',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
