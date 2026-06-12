import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/moona_colors.dart';
import '../../shared/widgets/widgets.dart';
import '../activity/activity_screen.dart';
import '../admin/admin_screen.dart';
import '../insights/insights_screen.dart';
import 'contact_picker.dart';

/// Opens the Settings sheet (account, language/theme, sharing, logout).
Future<void> showSettingsSheet(BuildContext context) {
  final t = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(appControllerProvider).t;
  return showMoonaSheet(
    context: context,
    title: t.settings,
    builder: (_) => const _SettingsContent(),
  );
}

class _SettingsContent extends ConsumerWidget {
  const _SettingsContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final t = state.t;
    final profile = state.profile;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (profile != null)
          MoonaSection(
            title: t.account,
            children: [
              MoonaRow(
                onTap: () => showDisplayNameDialog(context, ref),
                child: Row(
                  children: [
                    Avatar(name: profile.displayName),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            profile.displayName,
                            style: TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.w900,
                              color: c.onSurface,
                            ),
                          ),
                          Text(
                            profile.phone,
                            textDirection: TextDirection.ltr,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: c.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    MoonaIcon('edit', size: 20, color: c.onSurfaceVariant),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _SharingBlock(onShare: () => showContactFlow(context, ref)),
            ],
          ),
        const SizedBox(height: 22),
        _NavRow(
          icon: 'list',
          label: t.activity,
          onTap: () => _openScreen(context, const ActivityScreen()),
        ),
        const SizedBox(height: 9),
        _NavRow(
          icon: 'sort',
          label: t.insights,
          onTap: () => _openScreen(context, const InsightsScreen()),
        ),
        if (profile?.isAdmin ?? false) ...[
          const SizedBox(height: 9),
          _NavRow(
            icon: 'shield',
            label: t.admin,
            onTap: () => _openScreen(context, const AdminScreen()),
          ),
        ],
        const SizedBox(height: 22),
        MoonaSection(
          title: t.settings,
          children: [
            MoonaRow(
              child: Row(
                children: [
                  MoonaIcon('globe', size: 22, color: c.onSurfaceVariant),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      t.language,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: c.onSurface,
                      ),
                    ),
                  ),
                  MoonaSegmented<String>(
                    options: [('ar', t.arabic), ('en', t.english)],
                    value: state.lang,
                    onChanged: (k) {
                      if (k != state.lang) controller.toggleLang();
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 9),
            MoonaRow(
              child: Row(
                children: [
                  MoonaIcon(
                    state.dark ? 'moon' : 'sun',
                    size: 22,
                    color: c.onSurfaceVariant,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      t.theme,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: c.onSurface,
                      ),
                    ),
                  ),
                  MoonaSegmented<String>(
                    options: [('light', t.light), ('dark', t.dark)],
                    value: state.dark ? 'dark' : 'light',
                    onChanged: (k) {
                      if ((k == 'dark') != state.dark) controller.toggleTheme();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        MoonaButton(
          label: t.logout,
          icon: 'logout',
          variant: MoonaButtonVariant.outlined,
          danger: true,
          full: true,
          onPressed: () {
            Navigator.of(context).pop();
            controller.logout();
          },
        ),
      ],
    );
  }
}

/// Closes the settings sheet, then pushes [screen] on the app navigator. The
/// navigator is captured before the pop so the reference stays valid.
void _openScreen(BuildContext context, Widget screen) {
  final navigator = Navigator.of(context);
  navigator.pop();
  navigator.push(MaterialPageRoute(builder: (_) => screen));
}

/// A tappable settings row: leading icon, label, trailing chevron.
class _NavRow extends StatelessWidget {
  const _NavRow({required this.icon, required this.label, required this.onTap});

  final String icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return MoonaRow(
      onTap: onTap,
      child: Row(
        children: [
          MoonaIcon(icon, size: 22, color: c.onSurfaceVariant),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
                color: c.onSurface,
              ),
            ),
          ),
          MoonaIcon('chevron', size: 18, color: c.onSurfaceVariant),
        ],
      ),
    );
  }
}

class _SharingBlock extends ConsumerWidget {
  const _SharingBlock({required this.onShare});

  final VoidCallback onShare;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final t = state.t;
    final outgoing = state.sharing.acceptedOutgoing;

    if (state.isShared) {
      return _LinkedRow(
        caption: t.receivingFrom,
        name: state.ownerName,
        showDot: false,
        note: null,
        unlinkLabel: t.unlink,
        onUnlink: controller.unlink,
      );
    }
    if (outgoing != null) {
      return _LinkedRow(
        caption: t.sharingWith,
        name: outgoing.counterpartyName ?? state.nameFor(outgoing.viewerId),
        showDot: true,
        note: t.bothEdit,
        unlinkLabel: t.unlink,
        onUnlink: controller.unlink,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 4, bottom: 12),
          child: Text(
            t.shareDesc,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.45,
              color: c.onSurfaceVariant,
            ),
          ),
        ),
        MoonaButton(
          label: t.shareViaContacts,
          icon: 'person',
          full: true,
          onPressed: onShare,
        ),
      ],
    );
  }
}

class _LinkedRow extends StatelessWidget {
  const _LinkedRow({
    required this.caption,
    required this.name,
    required this.showDot,
    required this.note,
    required this.unlinkLabel,
    required this.onUnlink,
  });

  final String caption;
  final String name;
  final bool showDot;
  final String? note;
  final String unlinkLabel;
  final VoidCallback onUnlink;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return MoonaRow(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Avatar(name: name, tint: true),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      caption,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: c.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: c.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              if (showDot)
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: c.primary,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
          if (note != null) ...[
            const SizedBox(height: 12),
            Text(
              note!,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: c.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 12),
          MoonaButton(
            label: unlinkLabel,
            icon: 'close',
            variant: MoonaButtonVariant.outlined,
            full: true,
            onPressed: onUnlink,
          ),
        ],
      ),
    );
  }
}
