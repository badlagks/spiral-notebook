import 'dart:async';

import 'package:flutter/material.dart';

import '../data/alarms/alarms.dart';
import '../data/notebook_store.dart';
import '../data/phone_calendar.dart';
import '../models/notebook.dart';
import 'store_scope.dart';

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// "Today 9:00 AM", "Tomorrow 8:00 PM" or "Tue 28 Oct, 9:00 AM".
String friendlyTime(BuildContext context, DateTime at, {DateTime? now}) {
  final today = _day(now ?? DateTime.now());
  final time = MaterialLocalizations.of(context)
      .formatTimeOfDay(TimeOfDay.fromDateTime(at), alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context));
  final days = _day(at).difference(today).inDays;
  final day = switch (days) {
    0 => 'Today',
    1 => 'Tomorrow',
    -1 => 'Yesterday',
    _ =>
      '${_weekdays[at.weekday - 1]} ${at.day} ${_months[at.month - 1]}${at.year != today.year ? ' ${at.year}' : ''},',
  };
  return '$day $time';
}

/// Lets you pick when to be reminded about [block], or remove the reminder.
Future<void> showReminderEditor(BuildContext context, Block block) async {
  final store = StoreScope.read(context);
  final now = DateTime.now();
  final today = _day(now);
  final quick = <String, DateTime>{
    'In 1 hour': now.add(const Duration(hours: 1)),
    if (now.hour < 18) 'This evening': today.add(const Duration(hours: 19)),
    'Tomorrow morning': today.add(const Duration(days: 1, hours: 9)),
    // Monday morning, but never the same as "Tomorrow morning".
    'Next week': today.add(Duration(days: now.weekday == DateTime.sunday ? 8 : 8 - now.weekday, hours: 9)),
  };
  DateTime? at = block.reminder?.at;
  var toCalendar = block.reminder?.calendarEventId != null;

  final result = await showDialog<String>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setDialog) {
        Future<void> pick() async {
          final start = at ?? now.add(const Duration(hours: 1));
          final date = await showDatePicker(
            context: c,
            initialDate: start.isBefore(now) ? now : start,
            firstDate: today,
            lastDate: today.add(const Duration(days: 365 * 5)),
          );
          if (date == null || !c.mounted) return;
          final time = await showTimePicker(context: c, initialTime: TimeOfDay.fromDateTime(start));
          if (time == null) return;
          setDialog(() => at = DateTime(date.year, date.month, date.day, time.hour, time.minute));
        }

        final past = at != null && !at!.isAfter(DateTime.now());
        return AlertDialog(
          icon: const Icon(Icons.notifications_active_outlined),
          title: const Text('Remind me'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('About: ${reminderLabel(block)}', style: const TextStyle(color: Color(0xFF555555))),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final MapEntry(key: label, value: time) in quick.entries)
                      ChoiceChip(
                        label: Text(label),
                        selected: at == time,
                        onSelected: (_) => setDialog(() => at = time),
                      ),
                    ActionChip(
                      avatar: const Icon(Icons.event, size: 18),
                      label: const Text('Pick a day and time'),
                      onPressed: pick,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  at == null ? 'Choose when it should ring.' : 'Rings ${friendlyTime(c, at!)}',
                  style: TextStyle(fontWeight: FontWeight.w600, color: past ? Colors.red.shade700 : null),
                ),
                if (past) Text('That time has passed. Pick a later one.', style: TextStyle(color: Colors.red.shade700)),
                if (phoneCalendar.available)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: toCalendar,
                    onChanged: (v) => setDialog(() => toCalendar = v ?? false),
                    title: const Text("Also add it to my phone's calendar"),
                  ),
                if (!alarms.ringsWhenClosed)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Text(
                      'In a browser, reminders ring only while the notebook is open. '
                      'The phone and Mac apps ring even when it is closed.',
                      style: TextStyle(fontSize: 13, color: Color(0xFF666666)),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            if (block.reminder != null)
              TextButton(onPressed: () => Navigator.pop(c, 'remove'), child: const Text('Remove reminder')),
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
            FilledButton(
              onPressed: at == null || past ? null : () => Navigator.pop(c, 'set'),
              child: const Text('Set reminder'),
            ),
          ],
        );
      },
    ),
  );
  if (result == 'remove') {
    await store.setReminder(block, null);
  } else if (result == 'set' && at != null) {
    await store.setReminder(block, Reminder(at: at!), addToPhoneCalendar: toCalendar);
    // Not awaited: a browser waits for an answer that may never come.
    unawaited(alarms.askPermission());
  }
}

/// A small bell over a widget that has a reminder. Tap it to change it.
class ReminderBadge extends StatelessWidget {
  const ReminderBadge({super.key, required this.block});

  final Block block;

  @override
  Widget build(BuildContext context) {
    final r = block.reminder!;
    final done = r.rang || !r.at.isAfter(DateTime.now());
    final color = done ? const Color(0xFF8A8A8A) : const Color(0xFFB26A00);
    return Tooltip(
      message: done ? 'This reminder has rung. Tap to set it again.' : 'Reminder. Tap to change it.',
      child: Material(
        color: done ? const Color(0xFFF1F1F1) : const Color(0xFFFFF1D6),
        shape: StadiumBorder(side: BorderSide(color: color.withValues(alpha: 0.5))),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => showReminderEditor(context, block),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(done ? Icons.notifications_none : Icons.notifications_active, size: 14, color: color),
                const SizedBox(width: 4),
                Text(friendlyTime(context, r.at), style: TextStyle(fontSize: 11.5, color: color)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Watches the clock while the notebook is open. When a reminder is due it
/// rings and shows what it's about, with a button to open its page.
class ReminderWatcher extends StatefulWidget {
  const ReminderWatcher({super.key, required this.child});

  final Widget child;

  @override
  State<ReminderWatcher> createState() => _ReminderWatcherState();
}

class _ReminderWatcherState extends State<ReminderWatcher> with WidgetsBindingObserver {
  Timer? _timer;
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _check());
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    if (_showing || !mounted) return;
    final store = StoreScope.read(context);
    final due = store.takeDue(DateTime.now());
    if (due.isEmpty) return;
    _showing = true;
    final first = due.first;
    final hidden = store.isLocked(first.section);
    unawaited(
      alarms.ring(
        hidden ? 'Notebook reminder' : first.section.name,
        hidden ? 'A reminder in a locked section' : reminderLabel(first.block),
      ),
    );
    final open = await showDialog<SetReminder>(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.notifications_active, color: Color(0xFFB26A00), size: 32),
        title: Text(due.length == 1 ? 'Reminder' : '${due.length} reminders'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final r in due)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(radius: 6, backgroundColor: Color(r.section.color)),
                  title: Text(store.isLocked(r.section) ? 'In a locked section' : reminderLabel(r.block)),
                  subtitle: Text('${r.section.name} · page ${r.pageIndex + 1} · ${friendlyTime(c, r.reminder.at)}'),
                  trailing: TextButton(onPressed: () => Navigator.pop(c, r), child: const Text('Open')),
                ),
            ],
          ),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
      ),
    );
    _showing = false;
    if (open != null) store.openPage(open.sectionIndex, open.pageIndex);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
