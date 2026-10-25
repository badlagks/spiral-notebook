import '../models/notebook.dart';

/// A ready-made page layout, laid out fresh each time it is used.
class PageTemplate {
  const PageTemplate(this.name, this.description, this.build);
  final String name;
  final String description;
  final NotePage Function(DateTime today) build;
}

const _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String _longDate(DateTime d) => '${_days[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';

List<ChecklistItem> _blankItems(int n) => [for (var i = 0; i < n; i++) ChecklistItem()];

TextBlock _heading(String text, double x, double y, {double width = 200}) =>
    TextBlock(text: text, kind: TextKind.heading, x: x, y: y, width: width);

final pageTemplates = <PageTemplate>[
  PageTemplate('Daily planner', 'Top three, the day hour by hour, and notes', (today) {
    return NotePage(
      title: _longDate(today),
      paper: PaperStyle.blank,
      blocks: [
        _heading('Top 3', 56, 92),
        ChecklistBlock(items: _blankItems(3), x: 56, y: 140, width: 190),
        _heading('Schedule', 262, 92),
        SheetBlock(
          x: 262,
          y: 140,
          width: 190,
          cells: [
            ['Time', 'Plan'],
            for (var h = 8; h <= 18; h += 2) ['$h:00', ''],
          ],
        ),
        _heading('Notes', 56, 400),
        TextBlock(x: 56, y: 446, width: 380),
      ],
    );
  }),
  PageTemplate('Week ahead', 'Each day of the week, and what must get done', (today) {
    final monday = today.subtract(Duration(days: today.weekday - 1));
    return NotePage(
      title: 'Week of ${monday.day} ${_months[monday.month - 1]}',
      paper: PaperStyle.blank,
      blocks: [
        for (var i = 0; i < 7; i++) ...[
          TextBlock(
            text: '${_days[i].substring(0, 3)} ${monday.add(Duration(days: i)).day}',
            highlight: true,
            x: 48,
            y: 92 + i * 58,
            width: 110,
          ),
          TextBlock(x: 170, y: 92 + i * 58, width: 280),
        ],
        ChecklistBlock(items: _blankItems(3), x: 48, y: 510, width: 400),
      ],
    );
  }),
  PageTemplate('Meeting notes', 'Who was there, what was said, and actions', (today) {
    return NotePage(
      title: 'Meeting',
      paper: PaperStyle.ruled,
      blocks: [
        TextBlock(text: '${_longDate(today)}\nWith: ', x: 56, y: 92, width: 380),
        _heading('Notes', 56, 170),
        TextBlock(text: '- ', x: 56, y: 214, width: 380),
        _heading('Actions', 56, 430),
        ChecklistBlock(items: _blankItems(3), x: 56, y: 476, width: 380),
      ],
    );
  }),
  PageTemplate('Shopping list', 'Things to buy, with prices that add up', (today) {
    return NotePage(
      title: 'Shopping',
      paper: PaperStyle.ruled,
      blocks: [
        ChecklistBlock(items: _blankItems(6), x: 56, y: 96, width: 200),
        SheetBlock(
          x: 270,
          y: 96,
          width: 180,
          cells: [
            ['Item', 'Price'],
            ['', ''],
            ['', ''],
            ['', ''],
            ['', ''],
            ['Total', '=SUM(B2:B5)'],
          ],
        ),
      ],
    );
  }),
  PageTemplate('Habit tracker', 'Tick off habits for each day of the week', (today) {
    return NotePage(
      title: 'Habits',
      paper: PaperStyle.blank,
      blocks: [
        SheetBlock(
          x: 40,
          y: 100,
          width: 410,
          cells: [
            ['Habit', 'M', 'T', 'W', 'T', 'F', 'S', 'S'],
            for (final h in ['Water', 'Walk', 'Read', 'Sleep by 11', '']) [h, '', '', '', '', '', '', ''],
          ],
        ),
        TextBlock(text: 'Put an x for each day you did it.', x: 48, y: 330, width: 380),
      ],
    );
  }),
];
