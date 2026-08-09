import 'package:flutter/material.dart';

import '../core/data_repository.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.repo});
  final DataRepository repo;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic> stats = {};
  List<Map<String, dynamic>> widgets = [];
  Map<String, dynamic> widgetData = {};
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() { loading = true; error = null; });
    try {
      final results = await Future.wait<dynamic>([
        widget.repo.dashboard(),
        widget.repo.genericList('/widgets', const ['widgets'], query: const {}),
        widget.repo.api.get('/widgets/data'),
      ]);
      stats = Map<String, dynamic>.from(results[0] as Map);
      widgets = List<Map<String, dynamic>>.from(results[1] as List);
      final raw = widget.repo.api.unwrap(results[2]);
      widgetData = raw is Map ? Map<String, dynamic>.from(raw['data'] is Map ? raw['data'] as Map : raw) : {};
    } catch (e) {
      error = widget.repo.api.normalize(e).message;
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Dashboard'), actions: [IconButton(onPressed: load, icon: const Icon(Icons.refresh))]),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : error != null
            ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(error!, textAlign: TextAlign.center)))
            : RefreshIndicator(
                onRefresh: load,
                child: ListView(
                  padding: const EdgeInsets.all(14),
                  children: [
                    Text('Overview', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    LayoutBuilder(builder: (context, constraints) {
                      final metrics = _flattenNumbers(stats).entries.toList();
                      final width = constraints.maxWidth;
                      final columns = width > 900 ? 4 : width > 560 ? 3 : 2;
                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: metrics.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: columns, childAspectRatio: 1.65, crossAxisSpacing: 8, mainAxisSpacing: 8),
                        itemBuilder: (_, i) {
                          final entry = metrics[i];
                          return Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(_label(entry.key), maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelLarge),
                            const Spacer(),
                            Text(_number(entry.value), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                          ])));
                        },
                      );
                    }),
                    if (widgets.isNotEmpty) ...[
                      const SizedBox(height: 22),
                      Text('Widgets', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 10),
                      for (final config in widgets) _WidgetCard(config: config, data: _dataFor(config)),
                    ],
                  ],
                ),
              ),
  );

  Map<String, dynamic> _dataFor(Map<String, dynamic> config) {
    final id = config['id']?.toString();
    final value = id == null ? null : widgetData[id];
    return value is Map ? Map<String, dynamic>.from(value) : {};
  }
}

class _WidgetCard extends StatelessWidget {
  const _WidgetCard({required this.config, required this.data});
  final Map<String, dynamic> config;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final value = data['value'];
    final change = data['change'];
    final points = data['chart_data'] is List ? data['chart_data'] as List : const [];
    final rows = data['table_rows'] is List ? data['table_rows'] as List : const [];
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text((config['name'] ?? 'Widget').toString(), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
            if (change is num) Chip(label: Text('${change >= 0 ? '+' : ''}${change.toStringAsFixed(1)}%')),
          ]),
          if ((config['description'] ?? '').toString().isNotEmpty) Text(config['description'].toString()),
          if (value is num) ...[const SizedBox(height: 12), Text(_number(value), style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700))],
          if (points.isNotEmpty) ...[
            const SizedBox(height: 14),
            SizedBox(height: 130, child: CustomPaint(painter: _MiniChart(points), child: const SizedBox.expand())),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text((points.first is Map ? (points.first as Map)['label'] : '')?.toString() ?? '', style: Theme.of(context).textTheme.labelSmall),
              Text((points.last is Map ? (points.last as Map)['label'] : '')?.toString() ?? '', style: Theme.of(context).textTheme.labelSmall),
            ]),
          ],
          if (rows.isNotEmpty) ...[
            const Divider(height: 24),
            for (final raw in rows.take(8)) if (raw is Map)
              ListTile(contentPadding: EdgeInsets.zero, dense: true, title: Text((raw['label'] ?? raw['id'] ?? '').toString()), subtitle: Text((raw['sub_label'] ?? raw['status'] ?? '').toString()), trailing: raw['status'] == null ? null : Text(raw['status'].toString())),
          ],
        ]),
      ),
    );
  }
}

class _MiniChart extends CustomPainter {
  _MiniChart(this.points);
  final List points;

  @override
  void paint(Canvas canvas, Size size) {
    final values = <double>[];
    for (final raw in points) {
      if (raw is Map && raw['value'] is num) values.add((raw['value'] as num).toDouble());
    }
    if (values.length < 2) return;
    var minV = values.first, maxV = values.first;
    for (final v in values) { if (v < minV) minV = v; if (v > maxV) maxV = v; }
    final range = (maxV - minV).abs() < .0001 ? 1.0 : maxV - minV;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = size.width * i / (values.length - 1);
      final y = size.height - ((values[i] - minV) / range * (size.height - 12)) - 6;
      if (i == 0) path.moveTo(x, y); else path.lineTo(x, y);
    }
    final paint = Paint()..color = Colors.blue..strokeWidth = 2.2..style = PaintingStyle.stroke..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _MiniChart oldDelegate) => oldDelegate.points != points;
}

Map<String, num> _flattenNumbers(dynamic value, [String prefix = '']) {
  final result = <String, num>{};
  if (value is Map) {
    for (final entry in value.entries) {
      final key = prefix.isEmpty ? entry.key.toString() : '$prefix.${entry.key}';
      if (entry.value is num) result[key] = entry.value as num;
      else result.addAll(_flattenNumbers(entry.value, key));
    }
  }
  return result;
}
String _label(String key) => key.split('.').last.split('_').map((v) => v.isEmpty ? v : '${v[0].toUpperCase()}${v.substring(1)}').join(' ');
String _number(num value) {
  if (value is int) return value.toString();
  if (value.abs() >= 1000) return value.toStringAsFixed(0);
  return value.toStringAsFixed(value.abs() < 10 ? 2 : 1);
}
