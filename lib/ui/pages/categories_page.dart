import 'package:flutter/material.dart';

import '../../models/domain_models.dart';
import '../../state/app_controller.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';

class CategoriesPage extends StatelessWidget {
  const CategoriesPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: responsivePagePadding(context),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          title: 'Categories',
          subtitle: 'Organize income and spending into meaningful groups.',
          actions: [
            FilledButton.icon(
              onPressed: controller.hasSavedCategories
                  ? () => _showEditor(context)
                  : null,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('Add category'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (!controller.hasSavedCategories)
          const SectionCard(
            child: EmptyState(
              icon: Icons.cloud_off_rounded,
              title: 'Categories are not saved on this device',
              message: 'Your categories could not be read. Try refreshing your saved data.',
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 850;
              final expense = _CategorySection(
                title: 'Expense categories',
                subtitle: 'Where your money goes',
                items: controller.expenseCategories,
                onEdit: (item) => _showEditor(context, item),
                onDelete: (item) => _delete(context, item),
              );
              final income = _CategorySection(
                title: 'Income categories',
                subtitle: 'Where your money comes from',
                items: controller.incomeCategories,
                onEdit: (item) => _showEditor(context, item),
                onDelete: (item) => _delete(context, item),
              );
              if (stacked) {
                return Column(
                  children: [expense, const SizedBox(height: 18), income],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: expense),
                  const SizedBox(width: 18),
                  Expanded(child: income),
                ],
              );
            },
          ),
      ],
    ),
  );

  Future<void> _showEditor(BuildContext context, [Category? category]) =>
      showDialog<void>(
        context: context,
        builder: (context) =>
            _CategoryDialog(controller: controller, existing: category),
      );

  Future<void> _delete(BuildContext context, Category category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${category.name}?'),
        content: const Text(
          'This removes the category from active lists and new transactions. '
          'Past transactions and reports keep their category history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.palette.orange,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await controller.deleteCategory(category);
      if (context.mounted) showSuccess(context, 'Category deleted.');
    } catch (error) {
      if (context.mounted) showError(context, error);
    }
  }
}

class _CategorySection extends StatelessWidget {
  const _CategorySection({
    required this.title,
    required this.subtitle,
    required this.items,
    required this.onEdit,
    required this.onDelete,
  });

  final String title;
  final String subtitle;
  final List<Category> items;
  final ValueChanged<Category> onEdit;
  final ValueChanged<Category> onDelete;

  @override
  Widget build(BuildContext context) => SectionCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: TextStyle(color: context.palette.muted, fontSize: 12),
        ),
        const SizedBox(height: 17),
        if (items.isEmpty)
          const EmptyState(
            icon: Icons.category_outlined,
            title: 'No categories',
            message: 'Add a category to organize transactions.',
          )
        else
          ...items.map(
            (category) => Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: context.palette.border),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: colorFromHex(
                        category.color,
                        fallback: context.palette.green,
                        legacyReplacement: context.palette.greenDark,
                      ).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _icon(category.icon),
                      color: colorFromHex(
                        category.color,
                        fallback: context.palette.green,
                        legacyReplacement: context.palette.greenDark,
                      ),
                      size: 19,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          category.name,
                          style: TextStyle(
                            color: context.palette.ink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (category.isTransferFee)
                          Text(
                            'System-managed transfer and card-payment service charges',
                            style: TextStyle(
                              color: context.palette.muted,
                              fontSize: 11.5,
                            ),
                          ),
                        if (category.isSavingsInterest)
                          Text(
                            'System-managed monthly interest added to savings',
                            style: TextStyle(
                              color: context.palette.muted,
                              fontSize: 11.5,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (category.isSystem)
                    Tooltip(
                      message: 'Managed automatically by Budget Flow',
                      child: Padding(
                        padding: EdgeInsets.all(10),
                        child: Icon(
                          Icons.lock_outline_rounded,
                          color: context.palette.muted,
                          size: 19,
                        ),
                      ),
                    )
                  else
                    PopupMenuButton<String>(
                      tooltip: 'Category actions',
                      onSelected: (value) => value == 'edit'
                          ? onEdit(category)
                          : onDelete(category),
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'edit',
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.edit_rounded, size: 19),
                            title: Text('Edit'),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              Icons.delete_outline_rounded,
                              color: context.palette.red,
                              size: 19,
                            ),
                            title: Text(
                              'Delete',
                              style: TextStyle(color: context.palette.red),
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
      ],
    ),
  );

  static IconData _icon(String value) => switch (value) {
    'food' => Icons.restaurant_rounded,
    'home' => Icons.home_rounded,
    'transport' => Icons.directions_car_rounded,
    'shopping' => Icons.shopping_bag_rounded,
    'health' => Icons.favorite_rounded,
    'salary' => Icons.work_rounded,
    'business' => Icons.business_center_rounded,
    _ => Icons.category_rounded,
  };
}

class _CategoryDialog extends StatefulWidget {
  const _CategoryDialog({required this.controller, this.existing});
  final AppController controller;
  final Category? existing;

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  final key = GlobalKey<FormState>();
  late final TextEditingController nameController;
  late String kind;
  String color = '#43D98B';
  String icon = 'category';
  bool saving = false;

  static const colors = [
    '#43D98B',
    '#6F92FF',
    '#55D7E8',
    '#C74AF3',
    '#FFA13D',
    '#FF607B',
  ];
  static const icons = [
    'category',
    'food',
    'home',
    'transport',
    'shopping',
    'health',
    'salary',
    'business',
  ];

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: widget.existing?.name ?? '');
    kind = widget.existing?.kind ?? 'expense';
    color = widget.existing?.color ?? colors.first;
    icon = widget.existing?.icon ?? icons.first;
  }

  @override
  void dispose() {
    nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    insetPadding: EdgeInsets.symmetric(
      horizontal: MediaQuery.sizeOf(context).width < 480 ? 16 : 40,
      vertical: 24,
    ),
    title: Text(widget.existing == null ? 'Add category' : 'Edit category'),
    content: SizedBox(
      width: 500,
      child: Form(
        key: key,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Category name'),
              validator: (value) => (value?.trim().isEmpty ?? true)
                  ? 'Enter a category name.'
                  : null,
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: kind,
              decoration: const InputDecoration(labelText: 'Type'),
              items: const [
                DropdownMenuItem(value: 'expense', child: Text('Expense')),
                DropdownMenuItem(value: 'income', child: Text('Income')),
              ],
              onChanged: widget.existing == null
                  ? (value) => kind = value ?? kind
                  : null,
            ),
            const SizedBox(height: 17),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Color',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            const SizedBox(height: 9),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: colors.map((value) {
                final selected = color == value;
                final label =
                    '${_colorName(value)}${selected ? ', selected' : ''}';
                return Semantics(
                  button: true,
                  selected: selected,
                  label: label,
                  excludeSemantics: true,
                  child: Tooltip(
                    message: label,
                    child: InkWell(
                      onTap: () => setState(() => color = value),
                      customBorder: const CircleBorder(),
                      child: SizedBox.square(
                        dimension: 48,
                        child: Center(
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: colorFromHex(
                                value,
                                fallback: context.palette.green,
                                legacyReplacement: context.palette.greenDark,
                              ),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: selected
                                    ? context.palette.ink
                                    : Colors.transparent,
                                width: 3,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 17),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Icon',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            const SizedBox(height: 9),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: icons.map((value) {
                final selected = icon == value;
                final name = _iconName(value);
                final label = '$name icon${selected ? ', selected' : ''}';
                return Semantics(
                  button: true,
                  selected: selected,
                  label: label,
                  excludeSemantics: true,
                  child: Tooltip(
                    message: label,
                    child: InkWell(
                      onTap: () => setState(() => icon = value),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: selected
                              ? context.palette.mint
                              : context.palette.surfaceMuted,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: selected
                                ? context.palette.green
                                : context.palette.border,
                          ),
                        ),
                        child: Icon(
                          _CategorySection._icon(value),
                          size: 21,
                          color: context.palette.inkSoft,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: saving ? null : _save,
        child: Text(saving ? 'Saving…' : 'Save category'),
      ),
    ],
  );

  static String _colorName(String value) => switch (value.toUpperCase()) {
    '#6F92FF' => 'Blue',
    '#55D7E8' => 'Cyan',
    '#43D98B' => 'Green',
    '#C74AF3' => 'Purple',
    '#FFA13D' => 'Orange',
    '#FF607B' => 'Red',
    '#1B1B1B' => 'Legacy black',
    '#111111' => 'Legacy charcoal',
    '#159A73' => 'Legacy green',
    '#245C73' => 'Legacy blue',
    '#E9844A' => 'Legacy orange',
    '#7A61C9' => 'Legacy purple',
    '#D75050' => 'Legacy red',
    '#B18B2E' => 'Legacy gold',
    _ => 'Custom color',
  };

  static String _iconName(String value) => switch (value) {
    'food' => 'Food',
    'home' => 'Home',
    'transport' => 'Transport',
    'shopping' => 'Shopping',
    'health' => 'Health',
    'salary' => 'Salary',
    'business' => 'Business',
    _ => 'Category',
  };

  Future<void> _save() async {
    if (!key.currentState!.validate()) return;
    setState(() => saving = true);
    try {
      await widget.controller.saveCategory(
        existing: widget.existing,
        name: nameController.text.trim(),
        kind: kind,
        color: color,
        icon: icon,
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}
