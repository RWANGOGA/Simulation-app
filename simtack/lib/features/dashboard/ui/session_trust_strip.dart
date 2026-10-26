import 'package:flutter/material.dart';

import '../../../core/network/auth_service.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/theme/github_palette.dart';

/// One line, at the top of every practitioner screen, saying how current the
/// session actually is.
///
/// A sign-in answered from the device's own cache returns the same [Doctor] a
/// server sign-in returns, and the dashboard renders it identically. Before this
/// existed, nothing on screen distinguished "the server checked this account ten
/// seconds ago" from "a copy on this device was checked against a hash we stored
/// up to seven days ago" — and a practitioner reading a patient's triage under a
/// false assumption of freshness is a clinical risk, not a cosmetic one.
///
/// Renders nothing when the server answered, so a normal online session sees no
/// extra chrome.
class SessionTrustStrip extends StatefulWidget {
  /// Where the trust state comes from. Defaults to the live session; a test
  /// supplies a future so the strip can be checked without a network or a
  /// signed-in singleton.
  final Future<SessionTrust> Function()? loadTrust;

  const SessionTrustStrip({super.key, this.loadTrust});

  @override
  State<SessionTrustStrip> createState() => _SessionTrustStripState();
}

class _SessionTrustStripState extends State<SessionTrustStrip> {
  /// Read once when the console is built. A session's source only changes
  /// through sign-in, sign-out or a rejected token, and each of those rebuilds
  /// the screens underneath this one.
  late final Future<SessionTrust> _trust =
      (widget.loadTrust ?? () => AuthService.instance.sessionTrust())();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SessionTrust>(
      future: _trust,
      builder: (context, snapshot) {
        final trust = snapshot.data;
        if (trust == null || !trust.needsNotice) return const SizedBox.shrink();

        final l10n = AppLocalizations.of(context)!;
        final isDeviceAccount = trust.source == SessionSource.deviceAccount;
        final days = trust.daysSinceConfirmed;
        final message = isDeviceAccount
            ? l10n.sessionDeviceAccountNotice
            : days == null
                ? l10n.sessionCachedCopyUndatedNotice(trust.windowDays)
                : l10n.sessionCachedCopyNotice(days, trust.windowDays);

        return Material(
          // The console's own surface: this states a fact about the session, so
          // it sits in the chrome rather than inside one screen's content.
          color: GhColors.attentionSubtle(context),
          child: SafeArea(
            top: true,
            bottom: false,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: GhColors.border(context)),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isDeviceAccount
                        ? Icons.smartphone_rounded
                        : Icons.wifi_off_rounded,
                    size: 14,
                    color: GhColors.attention(context),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      message,
                      style: GhType.meta.copyWith(
                        color: GhColors.fg(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
