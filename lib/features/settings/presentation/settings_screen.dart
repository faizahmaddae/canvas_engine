import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../editor/application/export_quality.dart';
import '../application/settings_controller.dart';

/// User-facing preferences screen.
///
/// Layout follows native Material 3 settings conventions: grouped
/// sections, switch tiles for toggles, and a dialog for the radio
/// selection of export quality (mirrors the user's preference for
/// dialog-based pickers over inline chips).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final controller = ref.read(settingsControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _SectionHeader('Canvas Interaction'),
          _SwitchTile(
            icon: Icons.pan_tool_alt_outlined,
            title: 'Enable canvas pan',
            subtitle: 'Drag the canvas to reposition it',
            value: settings.canvasPanEnabled,
            onChanged: controller.setCanvasPanEnabled,
          ),
          _SwitchTile(
            icon: Icons.zoom_in_rounded,
            title: 'Enable canvas zoom',
            subtitle: 'Pinch to zoom in and out',
            value: settings.canvasZoomEnabled,
            onChanged: controller.setCanvasZoomEnabled,
          ),
          _SwitchTile(
            icon: Icons.screen_rotation_alt_outlined,
            title: 'Enable canvas rotation',
            subtitle: 'Reserved for future two-finger rotate gesture',
            value: settings.canvasRotationEnabled,
            onChanged: controller.setCanvasRotationEnabled,
          ),
          const SizedBox(height: 8),
          _SectionHeader('Export'),
          _NavTile(
            icon: Icons.high_quality_outlined,
            title: 'Default export quality',
            subtitle:
                '${settings.defaultExportQuality.label} '
                '· ${settings.defaultExportQuality.multiplier}',
            onTap: () => _openQualityPicker(context, ref, settings),
          ),
          const SizedBox(height: 8),
          _SectionHeader('Editor'),
          _SwitchTile(
            icon: Icons.straighten_rounded,
            title: 'Snap to guides',
            subtitle: 'Auto-align layers to nearby edges and centers',
            value: settings.snapToGuides,
            onChanged: controller.setSnapToGuides,
          ),
          _SwitchTile(
            icon: Icons.space_bar_rounded,
            title: 'Show spacing guides',
            subtitle: 'Highlight equal gaps between layers while dragging',
            value: settings.showSpacingGuides,
            onChanged: controller.setShowSpacingGuides,
          ),
          _SwitchTile(
            icon: Icons.touch_app_outlined,
            title: 'Multi-finger undo / redo',
            subtitle:
                'Two-finger tap to undo, three-finger tap to redo. '
                'Off by default — can conflict with pinch gestures.',
            value: settings.multiFingerUndoRedoEnabled,
            onChanged: controller.setMultiFingerUndoRedoEnabled,
          ),
          _SwitchTile(
            icon: Icons.front_hand_outlined,
            title: 'Right-handed toolbar',
            subtitle:
                'Aligns the bottom strip to the right edge so tools '
                'sit closer to your right thumb. Tool order stays the '
                'same — only placement changes.',
            value: settings.rightHandedToolbar,
            onChanged: controller.setRightHandedToolbar,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _openQualityPicker(
    BuildContext context,
    WidgetRef ref,
    AppSettings current,
  ) async {
    final picked = await showDialog<ExportQuality>(
      context: context,
      builder: (_) => _QualityPickerDialog(initial: current.defaultExportQuality),
    );
    if (picked == null) return;
    await ref
        .read(settingsControllerProvider.notifier)
        .setDefaultExportQuality(picked);
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Text(
        title.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      secondary: Icon(icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

class _QualityPickerDialog extends StatefulWidget {
  const _QualityPickerDialog({required this.initial});
  final ExportQuality initial;

  @override
  State<_QualityPickerDialog> createState() => _QualityPickerDialogState();
}

class _QualityPickerDialogState extends State<_QualityPickerDialog> {
  late ExportQuality _selected = widget.initial;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Default export quality'),
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RadioGroup<ExportQuality>(
            groupValue: _selected,
            onChanged: (v) {
              if (v != null) setState(() => _selected = v);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final q in ExportQuality.values)
                  RadioListTile<ExportQuality>(
                    value: q,
                    title: Text(q.label),
                    secondary: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        q.multiplier,
                        style: TextStyle(
                          color: scheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _selected),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
