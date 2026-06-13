---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/helm/schedule_sheet.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.895054+00:00
---

# archive/apps-semantos-monolith/lib/src/helm/schedule_sheet.dart

```dart
// Schedule sheet — date + time picker for job scheduling.
//
// Call showScheduleSheet() to show a modal bottom sheet that lets the
// operator pick a date and optional time.  Returns a DateTime on
// confirm, or null on dismiss.
//
// The returned DateTime is local — callers should pass it to
// JobsRepository.scheduleJob(id, at: result) which will ISO-encode it.

import 'package:flutter/material.dart';

Future<DateTime?> showScheduleSheet(
  BuildContext context, {
  DateTime? initial,
}) {
  return showModalBottomSheet<DateTime>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ScheduleSheet(initial: initial),
  );
}

class _ScheduleSheet extends StatefulWidget {
  final DateTime? initial;
  const _ScheduleSheet({this.initial});

  @override
  State<_ScheduleSheet> createState() => _ScheduleSheetState();
}

class _ScheduleSheetState extends State<_ScheduleSheet> {
  late DateTime _date;
  TimeOfDay? _time;

  @override
  void initState() {
    super.initState();
    final seed = widget.initial ?? DateTime.now();
    _date = DateTime(seed.year, seed.month, seed.day);
    if (widget.initial != null && widget.initial!.hour != 0) {
      _time = TimeOfDay.fromDateTime(seed);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time ?? const TimeOfDay(hour: 8, minute: 0),
    );
    if (picked != null) setState(() => _time = picked);
  }

  void _clearTime() => setState(() => _time = null);

  void _confirm() {
    final t = _time;
    final result = t == null
        ? _date
        : DateTime(_date.year, _date.month, _date.day, t.hour, t.minute);
    Navigator.of(context).pop(result);
  }

  String _formatDate(DateTime d) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    const days = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${days[d.weekday]} ${d.day} ${months[d.month]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text('Schedule job',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text('Date', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                border: Border.all(color: cs.outline),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_outlined, size: 20),
                  const SizedBox(width: 12),
                  Text(_formatDate(_date),
                      style: const TextStyle(fontSize: 15)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Time (optional)',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          InkWell(
            onTap: _pickTime,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                border: Border.all(color: cs.outline),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.schedule, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _time == null
                          ? 'No specific time'
                          : _time!.format(context),
                      style: TextStyle(
                        fontSize: 15,
                        color: _time == null ? Colors.grey : null,
                      ),
                    ),
                  ),
                  if (_time != null)
                    IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: _clearTime,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: _confirm,
            child: const Text('Schedule'),
          ),
        ],
      ),
    );
  }
}

```
