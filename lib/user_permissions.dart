import 'package:flutter/material.dart';

import 'i18n.dart';

// Per-user Jellyfin download permission in the add/edit-user dialog.
//
// The gateway maps `can_download` onto Jellyfin's EnableContentDownloading and
// EnableSyncTranscoding, and merges it into the user's existing policy. GET
// /users reports it as true/false, or null when Jellyfin could not be asked.
// PUT treats a missing field as "leave it alone", which is what an edit must
// send whenever the admin did not touch the switch — above all when the current
// value is unknown, so a dialog that could not read the setting never writes a
// guess back.

/// The `can_download` value an add/edit should send, or null to omit it.
/// A new user gets whatever the switch shows (on by default); an edit sends the
/// switch only if the admin changed it.
bool? downloadToSend({
  required bool isEdit,
  required bool? initial,
  required bool current,
  required bool touched,
}) {
  if (!isEdit) return current;
  if (!touched) return null;
  return current == initial ? null : current;
}

class DownloadPermissionTile extends StatelessWidget {
  const DownloadPermissionTile({
    super.key,
    required this.value,
    required this.unknown,
    required this.onChanged,
  });

  /// Current switch position.
  final bool value;

  /// The current Jellyfin setting could not be read (shown as a hint; nothing
  /// is written unless the admin flips the switch).
  final bool unknown;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(tr('canDownload')),
      subtitle: Text(
        unknown ? tr('canDownloadUnknown') : tr('canDownloadHint'),
        style: TextStyle(
            fontSize: 12, color: unknown ? cs.error : cs.onSurfaceVariant),
      ),
      value: value,
      onChanged: onChanged,
    );
  }
}
