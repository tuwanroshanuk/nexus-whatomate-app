import 'dart:convert';

import 'package:flutter/material.dart';

import 'branding.dart';

class FlowGraphEditor extends StatefulWidget {
  const FlowGraphEditor({super.key, required this.nodesJson, required this.edgesJson, required this.onChanged});
  final String nodesJson;
  final String edgesJson;
  final void Function(List<Map<String, dynamic>> nodes, List<Map<String, dynamic>> edges) onChanged;

  @override
  State<FlowGraphEditor> createState() => _FlowGraphEditorState();
}

class _FlowGraphEditorState extends State<FlowGraphEditor> {
  late List<Map<String, dynamic>> nodes = _decode(widget.nodesJson);
  late List<Map<String, dynamic>> edges = _decode(widget.edgesJson);

  static List<Map<String, dynamic>> _decode(String raw) {
    try {
      final value = jsonDecode(raw.isEmpty ? '[]' : raw);
      return value is List ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : [];
    } catch (_) { return []; }
  }

  void emit() {
    for (var i = 0; i < nodes.length; i++) {
      nodes[i]['position'] = {'x': 48 + (i.isOdd ? 32 : 0), 'y': 48 + i * 150};
    }
    widget.onChanged(nodes, edges);
    setState(() {});
  }

  void add(String type) {
    final id = 'mobile_${DateTime.now().microsecondsSinceEpoch}';
    final data = <String, dynamic>{'label': _label(type)};
    if (type == 'message' || type == 'play_audio' || type == 'tts') data['message'] = '';
    nodes.add({'id': id, 'type': type, 'position': {'x': 48, 'y': 48 + nodes.length * 150}, 'data': data});
    if (nodes.length > 1) {
      edges.add({'id': 'e_${nodes[nodes.length - 2]['id']}_$id', 'source': nodes[nodes.length - 2]['id'], 'target': id});
    }
    emit();
  }

  void edit(int index) async {
    final node = nodes[index];
    final data = node['data'] is Map ? Map<String, dynamic>.from(node['data'] as Map) : <String, dynamic>{};
    final title = TextEditingController(text: (data['label'] ?? data['title'] ?? '').toString());
    final content = TextEditingController(text: (data['message'] ?? data['text'] ?? data['prompt'] ?? '').toString());
    final ok = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: Text('Edit ${_label(node['type']?.toString() ?? 'step')}'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: title, decoration: const InputDecoration(labelText: 'Step name')),
        const SizedBox(height: 12),
        TextField(controller: content, minLines: 3, maxLines: 7, decoration: const InputDecoration(labelText: 'Message / prompt / value')),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Apply'))],
    ));
    if (ok == true) {
      data['label'] = title.text.trim().isEmpty ? _label(node['type']?.toString() ?? 'step') : title.text.trim();
      if (content.text.isNotEmpty) data['message'] = content.text;
      node['data'] = data;
      emit();
    }
    title.dispose(); content.dispose();
  }

  void remove(int index) {
    final id = nodes[index]['id']?.toString();
    nodes.removeAt(index);
    edges.removeWhere((e) => e['source']?.toString() == id || e['target']?.toString() == id);
    emit();
  }

  @override
  Widget build(BuildContext context) => Card(
    color: const Color(0xfff4f6ff),
    child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const Icon(Icons.account_tree_outlined, color: nexusBlue), const SizedBox(width: 8),
        Expanded(child: Text('Visual Flow Builder', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
        PopupMenuButton<String>(
          tooltip: 'Add step', icon: const Icon(Icons.add_circle, color: nexusBlue), onSelected: add,
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'start', child: Text('Start')),
            PopupMenuItem(value: 'message', child: Text('Send message')),
            PopupMenuItem(value: 'menu', child: Text('Menu / collect digits')),
            PopupMenuItem(value: 'condition', child: Text('Condition')),
            PopupMenuItem(value: 'transfer', child: Text('Transfer to agent/team')),
            PopupMenuItem(value: 'webhook', child: Text('Webhook / custom action')),
            PopupMenuItem(value: 'tts', child: Text('Text to speech')),
            PopupMenuItem(value: 'end', child: Text('End')),
          ],
        ),
      ]),
      const Text('Drag to reorder. Steps and connections are saved to the same nodes/edges fields used by the web builder.'),
      const SizedBox(height: 12),
      if (nodes.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Add a start step to begin.'))),
      ReorderableListView.builder(
        shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: nodes.length,
        onReorder: (oldIndex, newIndex) { if (newIndex > oldIndex) newIndex--; final item = nodes.removeAt(oldIndex); nodes.insert(newIndex, item); emit(); },
        itemBuilder: (context, i) { final node = nodes[i]; final data = node['data'] is Map ? node['data'] as Map : const {}; return Column(key: ValueKey(node['id'] ?? i), children: [
          ListTile(
            tileColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            leading: CircleAvatar(backgroundColor: i == 0 ? nexusBlue : nexusPink, foregroundColor: i == 0 ? Colors.white : Colors.black, child: Icon(_icon(node['type']?.toString()))),
            title: Text((data['label'] ?? data['title'] ?? _label(node['type']?.toString() ?? 'step')).toString()),
            subtitle: Text(_label(node['type']?.toString() ?? 'step')),
            onTap: () => edit(i),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.drag_handle), IconButton(onPressed: () => remove(i), icon: const Icon(Icons.delete_outline))]),
          ),
          if (i < nodes.length - 1) const SizedBox(height: 26, child: Icon(Icons.arrow_downward, size: 18, color: nexusBlue)),
        ]); },
      ),
    ])),
  );
}

String _label(String value) => value.replaceAll('_', ' ').split(' ').map((part) => part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}').join(' ');
IconData _icon(String? type) => switch (type) {
  'start' => Icons.play_arrow, 'message' => Icons.message_outlined, 'menu' => Icons.dialpad_outlined,
  'condition' => Icons.call_split_outlined, 'transfer' => Icons.phone_forwarded_outlined,
  'webhook' => Icons.webhook_outlined, 'tts' => Icons.record_voice_over_outlined, 'end' => Icons.stop,
  _ => Icons.circle_outlined,
};
