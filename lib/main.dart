import 'package:flutter/material.dart';

import 'data/notebook_store.dart';
import 'ui/ink.dart';
import 'ui/notebook_screen.dart';
import 'ui/section_lock.dart';
import 'ui/store_scope.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await NotebookStore.load();
  runApp(NotebookApp(store: store));
}

class NotebookApp extends StatefulWidget {
  const NotebookApp({super.key, required this.store});

  final NotebookStore store;

  @override
  State<NotebookApp> createState() => _NotebookAppState();
}

class _NotebookAppState extends State<NotebookApp> with WidgetsBindingObserver {
  final _ink = InkController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Don't lose the last few keystrokes when the app is backgrounded or closed.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      widget.store.saveNow();
    }
    // Locked sections close again once the app is put away, but not when
    // only the face or fingerprint prompt is covering it.
    if ((state == AppLifecycleState.paused || state == AppLifecycleState.hidden) && !deviceCheckShowing) {
      widget.store.lockAll();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StoreScope(
      store: widget.store,
      child: InkScope(
        controller: _ink,
        child: ValueListenableBuilder(
          valueListenable: widget.store.appearance,
          builder: (context, appearance, _) {
            final (look, tone) = appearance;
            Paper.look = look;
            Paper.tone = tone;
            return MaterialApp(
              title: 'Spiral Notebook',
              debugShowCheckedModeBanner: false,
              theme: buildTheme(),
              // A new look redraws everything, paper included.
              home: NotebookScreen(key: ValueKey(appearance)),
            );
          },
        ),
      ),
    );
  }
}
