import '../models/notebook.dart';

/// Tab colors offered when making or editing a section.
const tabColors = <int>[
  0xFFF4A261, // tangerine
  0xFFF2D06B, // butter
  0xFF9CCB86, // sage
  0xFF7FB3D5, // sky
  0xFFB39DDB, // lavender
  0xFFE88B9C, // rose
];

/// The notebook a person sees the first time they open the app.
/// Positions are in paper units on a 480 × 680 sheet.
Notebook sampleNotebook() => Notebook(
  title: 'My Notebook',
  sections: [
    Section(
      name: 'Ideas',
      color: tabColors[0],
      pages: [
        NotePage(
          title: 'Draft Outline',
          paper: PaperStyle.grid,
          blocks: [
            TextBlock(
              x: 40,
              y: 92,
              width: 250,
              text: '- Draft design\n  - Assert consideration\n- Overview\n  - Hands-on controls\n- Measurement',
            ),
            StickyBlock(x: 292, y: 100, width: 150, text: 'Call Sam about the sketches'),
            TextBlock(x: 150, y: 262, text: '2 mass minimised', highlight: true),
            SheetBlock(
              x: 24,
              y: 320,
              width: 400,
              cells: [
                ['Item', 'Quantity', 'Price', 'Total'],
                ['Item', '1', '\$10.00', '=B2*C2'],
                ['Draft design', '1', '\$1.00', '=B3*C3'],
                ['Revise invoice', '1', '\$5.00', '=B4*C4'],
                ['', '', '', ''],
                ['', '', '=SUM(C2:C5)', '=SUM(D2:D5)'],
              ],
            ),
            TextBlock(x: 40, y: 560, width: 200, text: '<- Ideas work'),
          ],
        ),
        NotePage(
          title: 'Project Budget',
          blocks: [
            TextBlock(
              x: 60,
              y: 96,
              width: 230,
              text: '- Print design\n- Draft design\n- Project launcher\n  - Plan design',
            ),
            TextBlock(x: 290, y: 124, width: 160, text: 'Find highlight', highlight: true),
            ChecklistBlock(
              x: 60,
              y: 264,
              width: 210,
              items: [
                ChecklistItem(text: 'Call client', done: true),
                ChecklistItem(text: 'Draft design', done: true),
                ChecklistItem(text: 'Draft design', done: true),
                ChecklistItem(text: 'Revise invoice', done: true),
                ChecklistItem(text: 'Repair mixing'),
                ChecklistItem(text: 'Revise writing'),
                ChecklistItem(text: 'Salary'),
                ChecklistItem(text: 'Revise invoice'),
              ],
            ),
            CalculatorBlock(x: 286, y: 276, width: 170, display: '1,450.00'),
          ],
        ),
      ],
    ),
    Section(
      name: 'Daily',
      color: tabColors[1],
      pages: [
        NotePage(
          title: 'Today',
          blocks: [
            TextBlock(x: 60, y: 96, text: '- Morning pages\n- Walk\n- Write 500 words'),
            ChecklistBlock(x: 60, y: 210, items: [ChecklistItem(text: 'Water the plants')]),
          ],
        ),
      ],
    ),
    Section(
      name: 'Finances',
      color: tabColors[2],
      pages: [
        NotePage(
          title: 'Monthly budget',
          paper: PaperStyle.grid,
          blocks: [
            SheetBlock(
              x: 24,
              y: 100,
              width: 420,
              cells: [
                ['Category', 'Budget', 'Spent', 'Left'],
                ['Rent', '\$1,200.00', '\$1,200.00', '=B2-C2'],
                ['Groceries', '\$400.00', '\$310.50', '=B3-C3'],
                ['Fun', '\$150.00', '\$90.00', '=B4-C4'],
                ['Total', '=SUM(B2:B4)', '=SUM(C2:C4)', '=SUM(D2:D4)'],
              ],
            ),
          ],
        ),
      ],
    ),
    Section(
      name: 'Tasks',
      color: tabColors[4],
      pages: [
        NotePage(
          title: 'This week',
          blocks: [
            ChecklistBlock(
              x: 60,
              y: 100,
              width: 300,
              items: [
                ChecklistItem(text: 'Send invoice'),
                ChecklistItem(text: 'Book dentist'),
              ],
            ),
          ],
        ),
      ],
    ),
  ],
);
