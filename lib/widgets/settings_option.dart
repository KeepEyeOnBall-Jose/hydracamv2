import "package:flutter/material.dart";
import "../app_theme.dart";
import "../services/alert_utils.dart";

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
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 10.0,
      ), // Space between options
      child: LayoutBuilder(
        builder: (context, constraints) {
          final label = _SettingsOptionLabel(
            title: title,
            description: description,
          );

          if (constraints.maxWidth < 520) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                label,
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: control,
                ),
              ],
            );
          }

          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: label),
              control,
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
            style: AppTheme.bodyText1,
          ),
        ),
        if (description != null)
          IconButton(
            icon: const Icon(
              Icons.info_outline,
              size: 20,
              color: AppTheme.accentColor,
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
