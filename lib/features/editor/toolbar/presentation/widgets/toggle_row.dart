import 'package:flutter/material.dart';

import '../../../../../core/utils/haptics.dart';

/// Shared toggle row for any binary sub-tool option (fill on/off,
/// border on/off, shadow on/off, dash on/off, …).
///
/// Single visual grammar so toggles never look out-of-place across
/// modes. Caller owns state; this widget only renders.
class ToggleRow extends StatelessWidget {
  const ToggleRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.icon,
    this.subtitle,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final IconData? icon;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          EditorHaptics.toggle();
          onChanged(!value);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: scheme.onSurfaceVariant),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Switch.adaptive(
                value: value,
                onChanged: (v) {
                  EditorHaptics.toggle();
                  onChanged(v);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
