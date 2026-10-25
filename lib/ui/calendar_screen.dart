import 'package:flutter/material.dart';

import '../data/notebook_store.dart';
import '../data/phone_calendar.dart';
import 'store_scope.dart';

/// A month of reminders, with the phone's own calendar beside them if
/// you turn it on. Tap a day to see what's on it, and a reminder to open
/// its page.
Future<void> showCalendar(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _Calendar());

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June', //
  'July', 'August', 'September', 'October', 'November', 'December',
];
const _dayLetters = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _phoneColor = Color(0xFF7A8796);

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

class _Calendar extends StatefulWidget {
  const _Calendar();

  @override
  State<_Calendar> createState() => _CalendarState();
}

class _CalendarState extends State<_Calendar> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  late DateTime _selected = _day(DateTime.now());
  List<PhoneEvent> _phone = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPhone());
  }

  /// The six weeks shown, starting on the Monday on or before the 1st.
  DateTime get _gridStart => _month.subtract(Duration(days: _month.weekday - 1));

  Future<void> _loadPhone() async {
    final store = StoreScope.read(context);
    if (!phoneCalendar.available || !store.notebook.showPhoneCalendar) {
      if (_phone.isNotEmpty) setState(() => _phone = []);
      return;
    }
    final from = _gridStart;
    final events = await phoneCalendar.events(from, from.add(const Duration(days: 42)));
    if (mounted) setState(() => _phone = events);
  }

  void _goMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
    _loadPhone();
  }

  Future<void> _togglePhone(bool on) async {
    final store = StoreScope.read(context);
    if (on && !await phoneCalendar.askPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The notebook needs permission to read your calendar. You can allow it in Settings.'),
          ),
        );
      }
      return;
    }
    store.notebook.showPhoneCalendar = on;
    store.changed();
    await _loadPhone();
  }

  bool _onDay(DateTime start, DateTime end, DateTime day) {
    final next = day.add(const Duration(days: 1));
    return start.isBefore(next) && (end.isAfter(day) || _day(start) == day);
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final reminders = store.reminders;
    List<SetReminder> remindersOn(DateTime d) => [
      for (final r in reminders)
        if (_day(r.reminder.at) == d) r,
    ];
    List<PhoneEvent> phoneOn(DateTime d) => [
      for (final e in _phone)
        if (_onDay(e.start, e.end, d)) e,
    ];

    final grid = _MonthGrid(
      start: _gridStart,
      month: _month.month,
      selected: _selected,
      dots: (d) => [for (final r in remindersOn(d)) Color(r.section.color), for (final _ in phoneOn(d)) _phoneColor],
      onTap: (d) => setState(() => _selected = d),
    );

    final dayList = _DayList(
      day: _selected,
      reminders: remindersOn(_selected),
      phone: phoneOn(_selected),
      store: store,
    );

    return Dialog.fullscreen(
      backgroundColor: const Color(0xFFF3EEE2),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 12, 0),
              child: Row(
                children: [
                  IconButton(tooltip: 'Close', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                  const SizedBox(width: 4),
                  const Expanded(
                    child: Text('Calendar', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  ),
                  TextButton(
                    onPressed: () {
                      final now = DateTime.now();
                      setState(() {
                        _month = DateTime(now.year, now.month);
                        _selected = _day(now);
                      });
                      _loadPhone();
                    },
                    child: const Text('Today'),
                  ),
                ],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Previous month',
                  onPressed: () => _goMonth(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                SizedBox(
                  width: 180,
                  child: Text(
                    '${_monthNames[_month.month - 1]} ${_month.year}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontFamily: 'Kalam', fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(tooltip: 'Next month', onPressed: () => _goMonth(1), icon: const Icon(Icons.chevron_right)),
              ],
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, c) {
                  final wide = c.maxWidth > 760;
                  if (wide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: Padding(padding: const EdgeInsets.all(12), child: grid),
                        ),
                        Expanded(flex: 2, child: dayList),
                      ],
                    );
                  }
                  return ListView(
                    children: [
                      Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: grid),
                      dayList,
                    ],
                  );
                },
              ),
            ),
            if (phoneCalendar.available)
              SwitchListTile(
                secondary: const Icon(Icons.event_note_outlined),
                title: const Text("Show my phone's calendar"),
                subtitle: const Text('Stays on this phone. Nothing is sent anywhere.'),
                value: store.notebook.showPhoneCalendar,
                onChanged: _togglePhone,
              ),
          ],
        ),
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.start,
    required this.month,
    required this.selected,
    required this.dots,
    required this.onTap,
  });

  final DateTime start;
  final int month;
  final DateTime selected;
  final List<Color> Function(DateTime day) dots;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final today = _day(DateTime.now());
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            for (final d in _dayLetters)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    d,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF777777)),
                  ),
                ),
              ),
          ],
        ),
        for (var week = 0; week < 6; week++)
          Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Builder(
                    builder: (context) {
                      // Built from the date, not by adding days, so clock changes don't shift it.
                      final day = DateTime(start.year, start.month, start.day + week * 7 + i);
                      final colors = dots(day);
                      final isSelected = day == selected;
                      final isToday = day == today;
                      return AspectRatio(
                        aspectRatio: 1.1,
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: Material(
                            color: isSelected ? const Color(0xFFE6D8B8) : Colors.white.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(8),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () => onTap(day),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 28,
                                    height: 28,
                                    alignment: Alignment.center,
                                    decoration: isToday
                                        ? const BoxDecoration(color: Color(0xFF8B5A1B), shape: BoxShape.circle)
                                        : null,
                                    child: Text(
                                      '${day.day}',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: isToday || isSelected ? FontWeight.w700 : FontWeight.w400,
                                        color: isToday
                                            ? Colors.white
                                            : day.month == month
                                            ? const Color(0xFF2B2B2B)
                                            : const Color(0xFFAAAAAA),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  SizedBox(
                                    height: 7,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        for (final c in colors.take(4))
                                          Container(
                                            width: 6,
                                            height: 6,
                                            margin: const EdgeInsets.symmetric(horizontal: 1),
                                            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _DayList extends StatelessWidget {
  const _DayList({required this.day, required this.reminders, required this.phone, required this.store});

  final DateTime day;
  final List<SetReminder> reminders;
  final List<PhoneEvent> phone;
  final NotebookStore store;

  @override
  Widget build(BuildContext context) {
    final loc = MaterialLocalizations.of(context);
    String time(DateTime t) => loc.formatTimeOfDay(
      TimeOfDay.fromDateTime(t),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(loc.formatFullDate(day), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (reminders.isEmpty && phone.isEmpty)
            const Text(
              'Nothing on this day. To add a reminder, tap ⋯ on any widget and choose "Remind me".',
              style: TextStyle(color: Color(0xFF666666)),
            ),
          for (final r in reminders)
            Card(
              elevation: 0,
              color: Colors.white.withValues(alpha: 0.8),
              child: ListTile(
                leading: Icon(
                  r.reminder.rang ? Icons.notifications_none : Icons.notifications_active,
                  color: Color(r.section.color),
                ),
                title: Text(store.isLocked(r.section) ? 'In a locked section' : reminderLabel(r.block)),
                subtitle: Text('${time(r.reminder.at)} · ${r.section.name}, page ${r.pageIndex + 1}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(context);
                  store.openPage(r.sectionIndex, r.pageIndex);
                },
              ),
            ),
          for (final e in phone)
            ListTile(
              leading: const Icon(Icons.event_outlined, color: _phoneColor),
              title: Text(e.title.isEmpty ? '(No title)' : e.title),
              subtitle: Text(e.allDay ? 'All day · phone calendar' : '${time(e.start)} · phone calendar'),
            ),
        ],
      ),
    );
  }
}
