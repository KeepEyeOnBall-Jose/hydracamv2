import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../services/alert_utils.dart';

/// A reusable widget for settings options with an optional info icon.
class SettingsOption extends StatelessWidget {
  final String title;
  final String? description;
  final Widget control;

  const SettingsOption({
    Key? key,
    required this.title,
    this.description,
    required this.control,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 10.0,
      ), // Space between options
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
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
            ),
          ),
          control,
        ],
      ),
    );
  }
}
