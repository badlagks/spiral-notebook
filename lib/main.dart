import 'package:flutter/material.dart';

import 'data/notebook_store.dart';
import 'ui/notebook_screen.dart';
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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StoreScope(
      store: widget.store,
      child: MaterialApp(
        title: 'Spiral Notebook',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const NotebookScreen(),
      ),
    );
  }
}
