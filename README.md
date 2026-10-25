# Spiral Notebook

A skeuomorphic spiral notebook for notes, outlines, checklists, little spreadsheets and quick math.
One Flutter codebase for iPhone, Mac, Android phones and Chromebooks (plus a web build).

## What's in the MVP

- Two-page spread with a spiral binding on wide screens; one page with swipe-to-turn on phones
- Colored section tabs (Ideas, Daily, Finances, Tasks). Long-press or right-click a tab to rename, recolor or delete; **+** adds one
- Pages on ruled, grid or blank paper, with a handwritten title
- Writing in a handwriting font. Lines starting with `- ` become an outline that continues on Enter
- Highlighted notes, checklists, an embedded spreadsheet (`=B2*C2`, `=SUM(D2:D8)`, AVG, MIN, MAX, COUNT; `$` amounts show as money) and a desk calculator (works with the keyboard too)
- Search across every page (Cmd/Ctrl+F)
- Everything is saved on the device automatically

Not yet: sync between devices, drawing with a finger or stylus, export.

## Run it

Install Flutter (stable), then:

```bash
flutter pub get
flutter run -d macos        # Mac (needs Xcode)
flutter run -d ios          # iPhone or simulator (needs Xcode)
flutter run -d android      # Android phone or emulator; also how it runs on Chromebooks
flutter run -d chrome       # web
flutter test                # 21 tests
```

## Code map

- `lib/models/notebook.dart`: notebook, sections, pages and blocks, with JSON save format
- `lib/data/`: the store that saves to the device, and the starter notebook
- `lib/logic/`: spreadsheet formulas and the calculator, both pure Dart and unit-tested
- `lib/ui/`: the notebook screen, paper and spiral painters, tabs, search, and one view per block type

Fonts: Kalam, Caveat and Roboto (SIL Open Font License), bundled in `assets/fonts`.
