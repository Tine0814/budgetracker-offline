import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/config_store.dart';
import '../../state/app_controller.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late String currency;
  late String locale;
  late int weekStartsOn;
  late bool showJewelryInReports;
  late bool showCreditCardsInReports;
  late AppThemePreference themePreference;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    _readPreferences();
  }

  void _readPreferences() {
    currency = widget.controller.settings.currencyCode;
    locale = widget.controller.settings.locale;
    weekStartsOn = widget.controller.settings.weekStartsOn;
    showJewelryInReports = widget.controller.settings.showJewelryInReports;
    showCreditCardsInReports =
        widget.controller.settings.showCreditCardsInReports;
    themePreference = widget.controller.config.themePreference;
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: responsivePagePadding(context),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeader(
          title: 'Settings',
          subtitle:
              'Make your tracker feel like yours and keep a copy of your data.',
        ),
        const SizedBox(height: 24),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Preferences',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 18),
              DropdownButtonFormField<AppThemePreference>(
                key: const ValueKey('settings-theme-mode-selector'),
                initialValue: themePreference,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Theme',
                  prefixIcon: Icon(Icons.contrast_rounded),
                ),
                items: const [
                  DropdownMenuItem(
                    value: AppThemePreference.dark,
                    child: Text('Dark'),
                  ),
                  DropdownMenuItem(
                    value: AppThemePreference.light,
                    child: Text('Light'),
                  ),
                  DropdownMenuItem(
                    value: AppThemePreference.system,
                    child: Text('System — follow this phone'),
                  ),
                ],
                onChanged: saving
                    ? null
                    : (value) async {
                        if (value == null) return;
                        setState(() => saving = true);
                        try {
                          await widget.controller.updateThemePreference(value);
                          if (mounted) setState(() => themePreference = value);
                        } catch (error) {
                          if (context.mounted) showError(context, error);
                        } finally {
                          if (mounted) setState(() => saving = false);
                        }
                      },
              ),
              const Divider(height: 36),
              Text(
                'Currency & reporting',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Changing currency changes the display label; existing amounts are not converted.',
                style: TextStyle(color: context.palette.muted, fontSize: 12),
              ),
              const SizedBox(height: 18),
              DropdownButtonFormField<String>(
                key: ValueKey('currency-$currency'),
                initialValue: currency,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Currency'),
                items: [
                  if (!const ['PHP', 'USD', 'EUR'].contains(currency))
                    DropdownMenuItem(value: currency, child: Text(currency)),
                  const DropdownMenuItem(
                    value: 'PHP',
                    child: Text('PHP — Philippine peso'),
                  ),
                  const DropdownMenuItem(
                    value: 'USD',
                    child: Text('USD — US dollar'),
                  ),
                  const DropdownMenuItem(
                    value: 'EUR',
                    child: Text('EUR — Euro'),
                  ),
                ],
                onChanged: saving
                    ? null
                    : (value) => setState(() => currency = value ?? currency),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                key: ValueKey('locale-$locale'),
                initialValue: locale,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Number format'),
                items: [
                  if (!const ['en_PH', 'en_US'].contains(locale))
                    DropdownMenuItem(value: locale, child: Text(locale)),
                  const DropdownMenuItem(
                    value: 'en_PH',
                    child: Text('English (Philippines)'),
                  ),
                  const DropdownMenuItem(
                    value: 'en_US',
                    child: Text('English (United States)'),
                  ),
                ],
                onChanged: saving
                    ? null
                    : (value) => setState(() => locale = value ?? locale),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<int>(
                key: ValueKey('week-start-$weekStartsOn'),
                initialValue: weekStartsOn,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Week starts on'),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('Monday')),
                  DropdownMenuItem(value: 2, child: Text('Tuesday')),
                  DropdownMenuItem(value: 3, child: Text('Wednesday')),
                  DropdownMenuItem(value: 4, child: Text('Thursday')),
                  DropdownMenuItem(value: 5, child: Text('Friday')),
                  DropdownMenuItem(value: 6, child: Text('Saturday')),
                  DropdownMenuItem(value: 0, child: Text('Sunday')),
                ],
                onChanged: saving
                    ? null
                    : (value) =>
                          setState(() => weekStartsOn = value ?? weekStartsOn),
              ),
              const Divider(height: 36),
              Text(
                'Report visibility',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Choose which summaries appear in Overview and Reports. Recorded income and expenses still count in cashflow totals.',
                style: TextStyle(color: context.palette.muted, fontSize: 12),
              ),
              SwitchListTile.adaptive(
                key: const Key('settings-show-jewelry-in-reports'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Show jewelry'),
                subtitle: const Text('Gold value and gain or loss summary'),
                value: showJewelryInReports,
                onChanged: saving
                    ? null
                    : (value) => setState(() => showJewelryInReports = value),
              ),
              SwitchListTile.adaptive(
                key: const Key('settings-show-credit-cards-in-reports'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Show credit cards'),
                subtitle: const Text(
                  'Card debt, net cash position, and upcoming billing',
                ),
                value: showCreditCardsInReports,
                onChanged: saving
                    ? null
                    : (value) =>
                          setState(() => showCreditCardsInReports = value),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: saving ? null : _savePreferences,
                icon: const Icon(Icons.save_rounded, size: 18),
                label: const Text('Save preferences'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your data & backups',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(
                'All accounts, transactions, budgets, and jewelry are stored on this phone. You can use the app in airplane mode.',
                style: TextStyle(color: context.palette.inkSoft, height: 1.5),
              ),
              const SizedBox(height: 12),
              Text(
                'Copy a backup and save it somewhere you control. Uninstalling the app, clearing its storage, or losing your phone can remove your records.',
                style: TextStyle(color: context.palette.muted, height: 1.5),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    key: const Key('export-backup-button'),
                    onPressed: saving ? null : _exportBackup,
                    icon: const Icon(Icons.save_alt_rounded),
                    label: const Text('Export backup'),
                  ),
                  OutlinedButton.icon(
                    key: const Key('import-backup-button'),
                    onPressed: saving ? null : _importBackup,
                    icon: const Icon(Icons.restore_rounded),
                    label: const Text('Restore backup'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Future<void> _savePreferences() async {
    setState(() => saving = true);
    try {
      await widget.controller.saveSettings(
        widget.controller.settings.copyWith(
          currencyCode: currency,
          locale: locale,
          weekStartsOn: weekStartsOn,
          showJewelryInReports: showJewelryInReports,
          showCreditCardsInReports: showCreditCardsInReports,
        ),
      );
      if (mounted) showSuccess(context, 'Preferences saved on this phone.');
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _exportBackup() async {
    setState(() => saving = true);
    try {
      final backup = await widget.controller.exportBackup();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Export backup'),
          scrollable: true,
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Copy all backup text and save it in a private note or a .json file. It contains your financial records.',
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 240,
                  child: SingleChildScrollView(
                    child: SelectableText(
                      backup,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
            FilledButton.icon(
              key: const Key('copy-backup-button'),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: backup));
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                if (mounted) {
                  showSuccess(
                    context,
                    'Backup copied. Paste it somewhere safe.',
                  );
                }
              },
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copy backup'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _importBackup() async {
    setState(() => saving = true);
    final restored = await restoreLocalBackup(context, widget.controller);
    if (!mounted) return;
    setState(() {
      saving = false;
      if (restored) _readPreferences();
    });
  }
}

Future<bool> restoreLocalBackup(
  BuildContext context,
  AppController controller,
) async {
  final backup = await showDialog<String>(
    context: context,
    builder: (_) => const _BackupTextDialog(),
  );
  if (backup == null || !context.mounted) return false;
  if (backup.isEmpty) {
    showError(context, 'Paste a backup first.');
    return false;
  }
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Replace this phone’s records?'),
      content: const Text(
        'Restoring replaces all current tracker records with this backup. Export your current records first if you want to keep them.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Replace & restore'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;
  try {
    await controller.importBackup(backup);
    if (context.mounted) showSuccess(context, 'Backup restored on this phone.');
    return true;
  } catch (error) {
    if (context.mounted) showError(context, error);
    return false;
  }
}

class _BackupTextDialog extends StatefulWidget {
  const _BackupTextDialog();
  @override
  State<_BackupTextDialog> createState() => _BackupTextDialogState();
}

class _BackupTextDialogState extends State<_BackupTextDialog> {
  final field = TextEditingController();
  @override
  void dispose() {
    field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Restore backup'),
    scrollable: true,
    content: SizedBox(
      width: 500,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Paste the complete backup text. You will confirm before replacing the records on this phone.',
          ),
          const SizedBox(height: 14),
          TextField(
            key: const Key('restore-backup-text'),
            controller: field,
            minLines: 6,
            maxLines: 12,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Backup text',
              alignLabelWithHint: true,
            ),
          ),
          TextButton.icon(
            onPressed: () async {
              final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
              if (context.mounted) field.text = clipboard?.text ?? '';
            },
            icon: const Icon(Icons.paste_rounded),
            label: const Text('Paste from clipboard'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, field.text.trim()),
        child: const Text('Continue'),
      ),
    ],
  );
}
