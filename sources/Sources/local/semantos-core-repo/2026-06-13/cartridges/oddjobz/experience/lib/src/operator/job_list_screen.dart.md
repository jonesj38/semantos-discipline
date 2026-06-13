---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/experience/lib/src/operator/job_list_screen.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.464393+00:00
---

# cartridges/oddjobz/experience/lib/src/operator/job_list_screen.dart

```dart
// JobListScreen — fetches and renders the live jobs list via REPL.

import 'package:flutter/material.dart';

import 'brain_client.dart';
import 'job.dart';
import 'job_detail_screen.dart';

class JobListScreen extends StatefulWidget {
  final BrainClient client;
  final VoidCallback onLogout;

  const JobListScreen({
    super.key,
    required this.client,
    required this.onLogout,
  });

  @override
  State<JobListScreen> createState() => _JobListScreenState();
}

class _JobListScreenState extends State<JobListScreen> {
  List<Job> _jobs = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final jobs = await widget.client.findJobs();
      if (!mounted) return;
      setState(() => _jobs = jobs);
    } on BrainClientError catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
      if (e.isUnauthorised) {
        await Future.delayed(Duration.zero);
        if (mounted) widget.onLogout();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('oddjobz'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: const Icon(Icons.power_settings_new),
            onPressed: widget.onLogout,
            tooltip: 'Log out',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (_jobs.isEmpty) {
      return const Center(child: Text('No jobs found.'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _jobs.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) => _JobRow(
          job: _jobs[i],
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  JobDetailScreen(job: _jobs[i], client: widget.client),
            ),
          ),
        ),
      ),
    );
  }
}

class _JobRow extends StatelessWidget {
  final Job job;
  final VoidCallback onTap;

  const _JobRow({required this.job, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      title: Text(
        job.customerName.isNotEmpty ? job.customerName : job.id,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (job.propertyAddress != null)
            Text(
              job.propertyAddress!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: cs.onSurfaceVariant,
              ),
            ),
          if (job.services != null)
            Text(
              job.services!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: cs.onSurfaceVariant,
              ),
            ),
        ],
      ),
      trailing: Chip(
        label: Text(
          job.stateLabel.toUpperCase(),
          style: TextStyle(
            fontSize: 9,
            fontFamily: 'monospace',
            letterSpacing: 0.6,
            color: job.isDone ? cs.onTertiaryContainer : cs.primary,
          ),
        ),
        backgroundColor: job.isDone
            ? cs.tertiaryContainer
            : cs.primaryContainer,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
      ),
      onTap: onTap,
    );
  }
}

```
