import "package:flutter/material.dart";
import "../services/alert_utils.dart";
import "hydracam_surface.dart";

/// A reusable widget for settings options with an optional info icon.
class SettingsOption extends StatelessWidget {
  final String title;
  final String? description;
  final Widget control;

  const SettingsOption({
    super.key,
    required this.title,
    this.description,
    required this.control,
  });

  @override
  Widget build(BuildContext context) {
    return HydraCamSurface(
      tone: HydraCamSurfaceTone.muted,
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final label = _SettingsOptionLabel(
            title: title,
            description: description,
          );

          final labeledControl = Semantics(label: title, child: control);
          if (constraints.maxWidth < 520 ||
              MediaQuery.textScalerOf(context).scale(16) > 20) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                label,
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: labeledControl,
                ),
              ],
            );
          }

          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: label),
              const SizedBox(width: 16),
              Expanded(child: labeledControl),
            ],
          );
        },
      ),
    );
  }
}

class _SettingsOptionLabel extends StatelessWidget {
  const _SettingsOptionLabel({
    required this.title,
    this.description,
  });

  final String title;
  final String? description;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            title,
            style: Theme.of(context).textTheme.bodyLarge!,
          ),
        ),
        if (description != null)
          IconButton(
            tooltip: title,
            icon: Icon(
              Icons.info_outline,
              size: 20,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            onPressed: () {
              AlertUtils.showInfoDialog(
                title: title,
                message: description!,
                context: context,
              );
            },
          ),
      ],
    );
  }
}
