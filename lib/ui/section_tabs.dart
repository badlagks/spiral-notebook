import 'package:flutter/material.dart';

import '../data/sample_notebook.dart';
import '../models/notebook.dart';
import 'store_scope.dart';
import 'theme.dart';

/// Colored index tabs sticking out of the notebook's right edge.
class SectionTabs extends StatelessWidget {
  const SectionTabs({super.key, this.tabWidth = 34, this.tabHeight = 92});

  final double tabWidth;
  final double tabHeight;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 18, bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < store.sections.length; i++)
            _Tab(
              section: store.sections[i],
              selected: i == store.sectionIndex,
              width: tabWidth,
              height: tabHeight,
              onTap: () => store.openSection(i),
              onEdit: () => showSectionEditor(context, store.sections[i]),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: IconButton(
              tooltip: 'New section',
              iconSize: 20,
              color: Colors.white70,
              onPressed: () => showSectionEditor(context, null),
              icon: const Icon(Icons.add_circle_outline),
            ),
          ),
        ],
      ),
    );
  }
}

/// The sections as a row of coloured labels, for the plain paper look.
class SectionChips extends StatelessWidget {
  const SectionChips({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        children: [
          for (var i = 0; i < store.sections.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _Chip(
                section: store.sections[i],
                selected: i == store.sectionIndex,
                onTap: () => store.openSection(i),
                onEdit: () => showSectionEditor(context, store.sections[i]),
              ),
            ),
          IconButton(
            tooltip: 'New section',
            iconSize: 20,
            visualDensity: VisualDensity.compact,
            color: Chrome.normal,
            onPressed: () => showSectionEditor(context, null),
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.section, required this.selected, required this.onTap, required this.onEdit});

  final Section section;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final color = Color(section.color);
    return Tooltip(
      message: '${section.name} · long-press or right-click to edit',
      child: GestureDetector(
        onLongPress: onEdit,
        onSecondaryTap: onEdit,
        child: Material(
          color: selected ? color : color.withValues(alpha: 0.28),
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Center(
                widthFactor: 1,
                child: Text(
                  section.name,
                  style: TextStyle(
                    fontFamily: 'Kalam',
                    fontSize: 15,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                    color: const Color(0xFF2B2B2B),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.section,
    required this.selected,
    required this.width,
    required this.height,
    required this.onTap,
    required this.onEdit,
  });

  final Section section;
  final bool selected;
  final double width;
  final double height;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final color = Color(section.color);
    return Tooltip(
      message: '${section.name} · long-press or right-click to edit',
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onEdit,
        onSecondaryTap: onEdit,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: selected ? width + 6 : width,
          height: height,
          margin: const EdgeInsets.only(bottom: 4),
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.horizontal(right: Radius.circular(9)),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Color.lerp(color, Colors.black, selected ? 0.0 : 0.12)!,
                Color.lerp(color, Colors.white, 0.2)!,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: selected ? 0.35 : 0.2),
                blurRadius: selected ? 5 : 2,
                offset: const Offset(2, 1),
              ),
            ],
          ),
          child: RotatedBox(
            quarterTurns: 1,
            child: Center(
              child: Text(
                section.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Kalam',
                  fontSize: 15,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                  color: const Color(0xFF2B2B2B),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens a dialog to create a section, or rename, recolor or remove one.
Future<void> showSectionEditor(BuildContext context, Section? section) async {
  final store = StoreScope.read(context);
  final name = TextEditingController(text: section?.name ?? '');
  var color = section?.color ?? tabColors[store.sections.length % tabColors.length];

  final result = await showDialog<String>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setDialog) => AlertDialog(
        title: Text(section == null ? 'New section' : 'Edit section'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Name'),
              onSubmitted: (_) => Navigator.pop(c, 'save'),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              children: [
                for (final option in tabColors)
                  GestureDetector(
                    onTap: () => setDialog(() => color = option),
                    child: CircleAvatar(
                      radius: 15,
                      backgroundColor: Color(option),
                      child: option == color ? const Icon(Icons.check, size: 16, color: Colors.black87) : null,
                    ),
                  ),
              ],
            ),
          ],
        ),
        actions: [
          if (section != null && store.sections.length > 1)
            TextButton(
              onPressed: () => Navigator.pop(c, 'delete'),
              child: const Text('Delete section'),
            ),
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, 'save'), child: const Text('Save')),
        ],
      ),
    ),
  );
  final text = name.text.trim();
  name.dispose();
  if (result == 'save' && text.isNotEmpty) {
    if (section == null) {
      store.addSection(text, color);
    } else {
      store.renameSection(section, text, color);
    }
  } else if (result == 'delete' && section != null && context.mounted) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Delete "${section.name}"?'),
        content: const Text('Its pages go to Torn-out pages, where you can restore them for 30 days.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) store.deleteSection(section);
  }
}
