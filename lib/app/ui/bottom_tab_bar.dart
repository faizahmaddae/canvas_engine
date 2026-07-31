import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/app_tokens.dart';
import '../theme/app_typography.dart';

/// One destination on the [BottomTabBar].
class BottomTabItem {
  const BottomTabItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
}

/// v2 bottom tab bar (navigation doc): paper bg, hairline top,
/// active = saffron icon + ink label, inactive = muted. Quiet chrome
/// — no indicator pill, no elevation; the saffron icon is the whole
/// selection signal.
class BottomTabBar extends StatelessWidget {
  const BottomTabBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onSelect,
  });

  final List<BottomTabItem> items;
  final int currentIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.pageBg,
        border: Border(top: BorderSide(color: tokens.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: _TabButton(
                    item: items[i],
                    active: i == currentIndex,
                    onTap: () => onSelect(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.item,
    required this.active,
    required this.onTap,
  });

  final BottomTabItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return InkWell(
      onTap: onTap,
      child: Semantics(
        selected: active,
        button: true,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              active ? item.activeIcon : item.icon,
              size: 22,
              color: active ? tokens.accentText : tokens.textMuted,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              item.label,
              style: AppTypeScale.caption.copyWith(
                fontSize: 11,
                height: 1.2,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? tokens.textPrimary : tokens.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
