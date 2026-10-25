import 'package:flutter/material.dart';

import '../data/templates.dart';
import '../models/notebook.dart';
import 'paper_page.dart';

/// Shows each template as a page preview. Returns the filled-in page, or null.
Future<NotePage?> showTemplatePicker(BuildContext context) => showDialog<NotePage>(
      context: context,
      builder: (context) {
        final today = DateTime.now();
        final previews = [for (final t in pageTemplates) (t, t.build(today))];
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          backgroundColor: const Color(0xFFF6F1E4),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760, maxHeight: 680),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text('Start from a template', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: GridView.extent(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    maxCrossAxisExtent: 230,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: 0.6,
                    children: [
                      for (final (template, page) in previews)
                        _TemplateCard(
                          template: template,
                          page: page,
                          onTap: () => Navigator.pop(context, template.build(DateTime.now())),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({required this.template, required this.page, required this.onTap});

  final PageTemplate template;
  final NotePage page;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRect(
                child: FittedBox(
                  child: PaperPage(
                    section: Section(name: '', color: 0, pages: [page]),
                    page: page,
                    pageNumber: 0,
                    bindingOnLeft: true,
                    interactive: false,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(template.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(
                    template.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF666666)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
