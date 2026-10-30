import 'package:flutter/material.dart';

/// The ✕ at the end of a text field: empties it in one tap. Shown only while the field
/// has text. Put it in the field's `suffixIcon`; [onCleared] runs after the text is
/// gone, for a field whose screen reacts only on submit (the library search).
class ClearButton extends StatelessWidget {
  const ClearButton(this.controller, {super.key, this.onCleared});

  final TextEditingController controller;
  final VoidCallback? onCleared;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (BuildContext context, TextEditingValue value, Widget? _) => value.text.isEmpty
          ? const SizedBox.shrink()
          : IconButton(
              icon: const Icon(Icons.clear),
              tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
              onPressed: () {
                controller.clear();
                onCleared?.call();
              },
            ),
    );
  }
}
