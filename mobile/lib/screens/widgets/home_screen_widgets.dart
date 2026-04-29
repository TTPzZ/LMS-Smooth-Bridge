part of '../home_screen.dart';

class _SectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.child,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final responsive = AppResponsive.of(context);
    final gap = responsive.sectionGap(compact: 8, medium: 10, expanded: 12);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFDE4E4), width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(
          responsive.sectionGap(compact: 12, medium: 14, expanded: 16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: const Color(0xFF8E1B1B),
                    fontWeight: FontWeight.w800,
                  ),
            ),
            if (subtitle != null) ...[
              SizedBox(height: gap - 4),
              Text(
                subtitle!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.blueGrey.shade600,
                    ),
              ),
            ],
            SizedBox(height: gap),
            child,
          ],
        ),
      ),
    );
  }
}

class _KpiTile extends StatelessWidget {
  final String label;
  final String value;
  final String hint;
  final IconData icon;
  final bool wide;
  final bool stretch;
  final bool loading;

  const _KpiTile({
    required this.label,
    required this.value,
    required this.hint,
    required this.icon,
    this.wide = false,
    this.stretch = false,
  }) : loading = false;

  const _KpiTile.loading({
    required this.label,
    this.stretch = false,
  })  : value = '...',
        hint = 'Đang tải',
        icon = Icons.hourglass_top_rounded,
        wide = false,
        loading = true;

  @override
  Widget build(BuildContext context) {
    final responsive = AppResponsive.of(context);
    final constraints = wide
        ? BoxConstraints(
            minWidth: responsive.clampWidth(150, 180, 220),
            maxWidth: responsive.isExpanded ? 420 : 340,
            minHeight: 102,
          )
        : BoxConstraints(
            minWidth: responsive.clampWidth(120, 130, 170),
            maxWidth: responsive.isExpanded ? 260 : 220,
            minHeight: 102,
          );

    final tile = Container(
      width: stretch ? double.infinity : null,
      constraints: stretch ? null : constraints,
      padding: EdgeInsets.all(
        responsive.sectionGap(compact: 8, medium: 10, expanded: 12),
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: const Color(0xFFFFF4F4),
        border: Border.all(color: const Color(0xFFFDE4E4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon,
                  size: responsive.scale(18), color: const Color(0xFFD32F2F)),
              SizedBox(
                  width: responsive.sectionGap(
                      compact: 4, medium: 6, expanded: 8)),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF8E1B1B),
                      ),
                ),
              ),
            ],
          ),
          SizedBox(
              height:
                  responsive.sectionGap(compact: 4, medium: 6, expanded: 8)),
          if (loading)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SkeletonLine(
                  width: responsive.clampWidth(76, 96, 116),
                  height: 16,
                ),
                SizedBox(
                  height: responsive.sectionGap(
                    compact: 5,
                    medium: 6,
                    expanded: 7,
                  ),
                ),
                _SkeletonLine(
                  width: responsive.clampWidth(110, 130, 156),
                  height: 10,
                ),
              ],
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  flex: 5,
                  child: Text(
                    value,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFFD32F2F),
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(
                    width: responsive.sectionGap(
                        compact: 6, medium: 8, expanded: 10)),
                Expanded(
                  flex: 4,
                  child: Text(
                    hint,
                    textAlign: TextAlign.end,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.blueGrey.shade600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
        ],
      ),
    );

    if (stretch) {
      return tile;
    }

    return ConstrainedBox(
      constraints: constraints,
      child: tile,
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MiniStat({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final responsive = AppResponsive.of(context);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: responsive.sectionGap(compact: 8, medium: 10, expanded: 12),
        vertical: responsive.sectionGap(compact: 6, medium: 8, expanded: 10),
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: const Color(0xFFFFF8F8),
        border: Border.all(color: const Color(0xFFFDE4E4)),
      ),
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxWidth: responsive.isExpanded ? 340 : 260),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: responsive.scale(15), color: const Color(0xFFD32F2F)),
            SizedBox(
                width:
                    responsive.sectionGap(compact: 4, medium: 6, expanded: 8)),
            Flexible(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF8E1B1B),
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;
  final IconData? icon;

  const _Pill({
    required this.label,
    required this.background,
    required this.foreground,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final responsive = AppResponsive.of(context);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: responsive.sectionGap(compact: 8, medium: 9, expanded: 10),
        vertical: responsive.sectionGap(compact: 4, medium: 5, expanded: 6),
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxWidth: responsive.isExpanded ? 280 : 220),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: responsive.scale(12), color: foreground),
              SizedBox(
                  width: responsive.sectionGap(
                      compact: 3, medium: 4, expanded: 5)),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClassSectionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;

  const _ClassSectionButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final responsive = AppResponsive.of(context);
    return FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        elevation: 0,
        padding: EdgeInsets.symmetric(
          horizontal:
              responsive.sectionGap(compact: 10, medium: 11, expanded: 12),
          vertical: responsive.sectionGap(compact: 9, medium: 10, expanded: 11),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: selected
              ? const BorderSide(color: Color(0xFFFDE4E4))
              : BorderSide.none,
        ),
        backgroundColor: selected ? const Color(0xFFFFECEC) : Colors.white,
        foregroundColor:
            selected ? const Color(0xFFD32F2F) : Colors.blueGrey.shade600,
      ),
      icon: Icon(icon, size: responsive.scale(16)),
      label: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style:
            TextStyle(fontWeight: selected ? FontWeight.w800 : FontWeight.w600),
      ),
    );
  }
}

class _PullActionButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onPressed;

  const _PullActionButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final responsive = AppResponsive.of(context);
    return Material(
      color: const Color(0xFFFFF4F4),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFFDE4E4), width: 1.5),
          ),
          padding: EdgeInsets.symmetric(
            horizontal:
                responsive.sectionGap(compact: 10, medium: 12, expanded: 14),
            vertical:
                responsive.sectionGap(compact: 12, medium: 14, expanded: 14),
          ),
          child: Row(
            children: [
              Container(
                width: responsive.scale(36),
                height: responsive.scale(36),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: responsive.scale(18), color: accent),
              ),
              SizedBox(
                  width: responsive.sectionGap(
                      compact: 8, medium: 10, expanded: 12)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF8E1B1B),
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.blueGrey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineLoading extends StatelessWidget {
  const _InlineLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: Color(0xFFD32F2F)),
        ),
      ),
    );
  }
}

class _ErrorLabel extends StatelessWidget {
  final String message;

  const _ErrorLabel({required this.message});

  @override
  Widget build(BuildContext context) {
    final responsive = AppResponsive.of(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(
        responsive.sectionGap(compact: 10, medium: 12, expanded: 14),
      ),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.red.shade700,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _EmptyLabel extends StatelessWidget {
  final String message;

  const _EmptyLabel({required this.message});

  @override
  Widget build(BuildContext context) {
    final responsive = AppResponsive.of(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(
        responsive.sectionGap(compact: 10, medium: 12, expanded: 14),
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8F8),
        border: Border.all(color: const Color(0xFFFDE4E4)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: const Color(0xFF8E1B1B)),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  const _ErrorView({required this.message});

  @override
  Widget build(BuildContext context) {
    final responsive = AppResponsive.of(context);
    final centered = (responsive.width - responsive.contentMaxWidth) / 2;
    final horizontal = centered > responsive.pageHorizontalPadding
        ? centered
        : responsive.pageHorizontalPadding;
    return Center(
      child: Padding(
        padding: EdgeInsets.fromLTRB(horizontal, 16, horizontal, 16),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: responsive.contentMaxWidth),
          child: Text(
            message,
            style: const TextStyle(color: Colors.red),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  final String message;
  const _EmptyView({required this.message});

  @override
  Widget build(BuildContext context) {
    final responsive = AppResponsive.of(context);
    final centered = (responsive.width - responsive.contentMaxWidth) / 2;
    final horizontal = centered > responsive.pageHorizontalPadding
        ? centered
        : responsive.pageHorizontalPadding;
    return Center(
      child: Padding(
        padding: EdgeInsets.fromLTRB(horizontal, 16, horizontal, 16),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: responsive.contentMaxWidth),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.inbox_rounded,
                size: 40,
                color: Color(0xFFFDE4E4),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF8E1B1B),
                    ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RefreshingStrip extends StatelessWidget {
  final String message;

  const _RefreshingStrip({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6F6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF9D6D6)),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Color(0xFFD32F2F),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF8E1B1B),
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SkeletonLine extends StatelessWidget {
  final double? width;
  final double height;
  final BorderRadius? borderRadius;

  const _SkeletonLine({
    this.width,
    this.height = 12,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFF6DCDC),
        borderRadius: borderRadius ?? BorderRadius.circular(999),
      ),
    );
  }
}

class _ClassesPageSkeletonCard extends StatelessWidget {
  const _ClassesPageSkeletonCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFDE4E4), width: 1.5),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          _SkeletonLine(width: 160, height: 14),
          SizedBox(height: 10),
          _SkeletonLine(width: 110, height: 10),
          SizedBox(height: 16),
          _SkeletonLine(
              height: 42, borderRadius: BorderRadius.all(Radius.circular(10))),
          SizedBox(height: 10),
          _SkeletonLine(
              height: 42, borderRadius: BorderRadius.all(Radius.circular(10))),
        ],
      ),
    );
  }
}

class _PayrollPageSkeletonCard extends StatelessWidget {
  final int lines;

  const _PayrollPageSkeletonCard({this.lines = 4});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFDE4E4), width: 1.5),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List<Widget>.generate(lines * 2 - 1, (index) {
          if (index.isOdd) {
            return const SizedBox(height: 10);
          }
          final lineIndex = index ~/ 2;
          final width = lineIndex % 3 == 0
              ? 170.0
              : lineIndex % 3 == 1
                  ? 130.0
                  : 220.0;
          return _SkeletonLine(width: width, height: 12);
        }),
      ),
    );
  }
}

class _CardListSkeleton extends StatelessWidget {
  final int itemCount;

  const _CardListSkeleton({this.itemCount = 3});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List<Widget>.generate(itemCount * 2 - 1, (index) {
        if (index.isOdd) {
          return const SizedBox(height: 10);
        }
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFDE4E4)),
            color: Colors.white,
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SkeletonLine(width: 170, height: 12),
              SizedBox(height: 8),
              _SkeletonLine(width: 120, height: 10),
            ],
          ),
        );
      }),
    );
  }
}

class _ChipSkeletonWrap extends StatelessWidget {
  final int itemCount;

  const _ChipSkeletonWrap({this.itemCount = 6});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List<Widget>.generate(
        itemCount,
        (index) => const _SkeletonLine(
          width: 116,
          height: 30,
          borderRadius: BorderRadius.all(Radius.circular(999)),
        ),
      ),
    );
  }
}
