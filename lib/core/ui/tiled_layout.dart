import 'package:flutter/material.dart';

/// 打开三个调试窗口时的可选布局方式。
enum TripleLayout {
  oneTopTwoBottom('上一下二'),
  twoTopOneBottom('上二下一'),
  threeColumns('三栏并排');

  const TripleLayout(this.label);

  final String label;
}

/// 三窗口布局选择器（仅在恰好打开 3 个窗口时显示）。
class TripleLayoutPicker extends StatelessWidget {
  const TripleLayoutPicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final TripleLayout value;
  final ValueChanged<TripleLayout> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopupMenuButton<TripleLayout>(
      tooltip: '选择三窗口布局',
      initialValue: value,
      onSelected: onChanged,
      itemBuilder: (_) => [
        for (final layout in TripleLayout.values)
          PopupMenuItem(
            value: layout,
            child: Row(
              children: [
                Icon(Icons.dashboard_customize,
                    size: 18, color: scheme.primary),
                const SizedBox(width: 10),
                Text(layout.label),
                if (layout == value) ...[
                  const Spacer(),
                  Icon(Icons.check,
                      size: 18, color: scheme.primary),
                ],
              ],
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.dashboard_customize,
                size: 18, color: scheme.primary),
            const SizedBox(width: 6),
            Text(value.label, style: const TextStyle(fontSize: 13)),
            const Icon(Icons.arrow_drop_down, size: 20),
          ],
        ),
      ),
    );
  }
}

/// 调试窗口通用平铺布局，按子项数量自动排布：
///
/// - 1 个：占满
/// - 2 个：左右并排
/// - 3 个：上一下二 / 上二下一 / 三栏并排（可选）
/// - 4 个：田字排布
class TiledLayout extends StatelessWidget {
  const TiledLayout({
    super.key,
    required this.children,
    this.tripleLayout = TripleLayout.oneTopTwoBottom,
  });

  /// 1~4 个子面板。
  final List<Widget> children;

  final TripleLayout tripleLayout;

  @override
  Widget build(BuildContext context) {
    final dividerColor = Theme.of(context).colorScheme.outlineVariant;
    final vDivider = Container(width: 1, color: dividerColor);
    final hDivider = Container(height: 1, color: dividerColor);

    switch (children.length) {
      case 1:
        return children[0];
      case 2:
        // 两个面板：左右并排。
        return Row(
          children: [
            Expanded(child: children[0]),
            vDivider,
            Expanded(child: children[1]),
          ],
        );
      case 3:
        switch (tripleLayout) {
          case TripleLayout.oneTopTwoBottom:
            return Column(
              children: [
                Expanded(child: children[0]),
                hDivider,
                Expanded(
                  child: Row(
                    children: [
                      Expanded(child: children[1]),
                      vDivider,
                      Expanded(child: children[2]),
                    ],
                  ),
                ),
              ],
            );
          case TripleLayout.twoTopOneBottom:
            return Column(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Expanded(child: children[0]),
                      vDivider,
                      Expanded(child: children[1]),
                    ],
                  ),
                ),
                hDivider,
                Expanded(child: children[2]),
              ],
            );
          case TripleLayout.threeColumns:
            return Row(
              children: [
                Expanded(child: children[0]),
                vDivider,
                Expanded(child: children[1]),
                vDivider,
                Expanded(child: children[2]),
              ],
            );
        }
      default: // 4 个：田字排布
        return Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(child: children[0]),
                  vDivider,
                  Expanded(child: children[1]),
                ],
              ),
            ),
            hDivider,
            Expanded(
              child: Row(
                children: [
                  Expanded(child: children[2]),
                  vDivider,
                  Expanded(child: children[3]),
                ],
              ),
            ),
          ],
        );
    }
  }
}
