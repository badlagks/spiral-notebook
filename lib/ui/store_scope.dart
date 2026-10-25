import 'package:flutter/widgets.dart';

import '../data/notebook_store.dart';

/// Makes the [NotebookStore] available to every widget below it.
class StoreScope extends InheritedNotifier<NotebookStore> {
  const StoreScope({super.key, required NotebookStore store, required super.child})
      : super(notifier: store);

  /// The store, rebuilding the caller whenever the notebook changes.
  static NotebookStore of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StoreScope>()!.notifier!;

  /// The store, without subscribing to changes. Use in callbacks.
  static NotebookStore read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<StoreScope>()!.notifier!;
}
