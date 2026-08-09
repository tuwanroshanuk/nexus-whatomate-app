import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/data_repository.dart';

class ModuleAction {
  const ModuleAction(this.label, this.pathSuffix, {this.method = 'POST', this.icon = Icons.play_arrow, this.body = const {}});
  final String label;
  final String pathSuffix;
  final String method;
  final IconData icon;
  final Map<String, dynamic> body;
}

class RelatedCollection {
  const RelatedCollection({
    required this.label,
    required this.listPath,
    required this.keys,
    this.createPath,
    this.updatePath,
    this.deletePath,
    this.seed = const {},
    this.editableKeys,
    this.idField = 'id',
    this.wrapCreateKey,
  });
  final String label;
  final String listPath;
  final List<String> keys;
  final String? createPath;
  final String? updatePath;
  final String? deletePath;
  final Map<String, dynamic> seed;
  final List<String>? editableKeys;
  final String idField;
  final String? wrapCreateKey;
}

class ApiModule {
  const ApiModule({
    required this.title,
    required this.path,
    required this.keys,
    required this.icon,
    this.seed = const {},
    this.editableKeys,
    this.idField = 'id',
    this.canCreate = true,
    this.canUpdate = true,
    this.canDelete = true,
    this.actions = const [],
    this.globalActions = const [],
    this.related = const [],
    this.readOnly = false,
  });
  final String title;
  final String path;
  final List<String> keys;
  final IconData icon;
  final Map<String, dynamic> seed;
  final List<String>? editableKeys;
  final String idField;
  final bool canCreate;
  final bool canUpdate;
  final bool canDelete;
  final List<ModuleAction> actions;
  final List<ModuleAction> globalActions;
  final List<RelatedCollection> related;
  final bool readOnly;
}

class AdminModuleScreen extends StatefulWidget {
  const AdminModuleScreen({super.key, required this.repo, required this.module});
  final DataRepository repo;
  final ApiModule module;

  @override
  State<AdminModuleScreen> createState() => _AdminModuleScreenState();
}

class _AdminModuleScreenState extends State<AdminModuleScreen> {
  final search = TextEditingController();
  List<Map<String, dynamic>> items = [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      items = await widget.repo.genericList(widget.module.path, widget.module.keys, query: {
        'page': 1,
        'limit': 100,
        if (search.text.trim().isNotEmpty) 'search': search.text.trim(),
      });
    } catch (e) {
      error = widget.repo.api.normalize(e).message;
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _create() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => RecordEditorScreen(
          api: widget.repo.api,
          title: 'New ${widget.module.title}',
          path: widget.module.path,
          initial: widget.module.seed,
          editableKeys: widget.module.editableKeys,
          create: true,
        ),
      ),
    );
    if (changed == true) await load();
  }

  Future<void> _open(Map<String, dynamic> item) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => RecordDetailScreen(repo: widget.repo, module: widget.module, item: item),
      ),
    );
    if (changed == true) await load();
  }

  Future<void> _runGlobal(ModuleAction action) async {
    try {
      await _request(widget.repo.api, action.method, '${widget.module.path}${action.pathSuffix}', action.body);
      if (mounted) _snack('${action.label} completed');
      await load();
    } catch (e) {
      if (mounted) _snack(widget.repo.api.normalize(e).message);
    }
  }

  void _snack(String value) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.module.title),
        actions: [
          for (final action in widget.module.globalActions)
            IconButton(onPressed: () => _runGlobal(action), tooltip: action.label, icon: Icon(action.icon)),
          IconButton(onPressed: load, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: widget.module.canCreate && !widget.module.readOnly
          ? FloatingActionButton.extended(onPressed: _create, icon: const Icon(Icons.add), label: const Text('New'))
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: search,
              onSubmitted: (_) => load(),
              decoration: InputDecoration(
                hintText: 'Search ${widget.module.title.toLowerCase()}',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(onPressed: load, icon: const Icon(Icons.arrow_forward)),
              ),
            ),
          ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : error != null
                    ? _ErrorState(message: error!, retry: load)
                    : RefreshIndicator(
                        onRefresh: load,
                        child: items.isEmpty
                            ? ListView(children: const [SizedBox(height: 180), Center(child: Text('No records'))])
                            : ListView.separated(
                                itemCount: items.length,
                                separatorBuilder: (_, __) => const Divider(height: 1),
                                itemBuilder: (_, index) {
                                  final item = items[index];
                                  return ListTile(
                                    leading: CircleAvatar(child: Icon(widget.module.icon, size: 20)),
                                    title: Text(_bestTitle(item), maxLines: 1, overflow: TextOverflow.ellipsis),
                                    subtitle: Text(_bestSubtitle(item), maxLines: 2, overflow: TextOverflow.ellipsis),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () => _open(item),
                                  );
                                },
                              ),
                      ),
          ),
        ],
      ),
    );
  }
}

class RecordDetailScreen extends StatefulWidget {
  const RecordDetailScreen({super.key, required this.repo, required this.module, required this.item});
  final DataRepository repo;
  final ApiModule module;
  final Map<String, dynamic> item;

  @override
  State<RecordDetailScreen> createState() => _RecordDetailScreenState();
}

class _RecordDetailScreenState extends State<RecordDetailScreen> {
  late Map<String, dynamic> item = Map<String, dynamic>.from(widget.item);
  bool busy = false;

  String get id => item[widget.module.idField]?.toString() ?? '';

  Future<void> _refresh() async {
    if (id.isEmpty) return;
    try {
      final raw = widget.repo.api.unwrap(await widget.repo.api.get('${widget.module.path}/${Uri.encodeComponent(id)}'));
      if (raw is Map && mounted) setState(() => item = Map<String, dynamic>.from(raw));
    } catch (_) {}
  }

  Future<void> _edit() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => RecordEditorScreen(
          api: widget.repo.api,
          title: 'Edit ${widget.module.title}',
          path: '${widget.module.path}/${Uri.encodeComponent(id)}',
          initial: item,
          editableKeys: widget.module.editableKeys,
          create: false,
        ),
      ),
    );
    if (changed == true) {
      await _refresh();
      if (mounted) Navigator.pop(context, true);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete record?'),
        content: Text('Delete “${_bestTitle(item)}”? This action uses the server delete endpoint.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.repo.api.delete('${widget.module.path}/${Uri.encodeComponent(id)}');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) _snack(widget.repo.api.normalize(e).message);
    }
  }

  Future<void> _run(ModuleAction action) async {
    if (busy) return;
    setState(() => busy = true);
    final suffix = action.pathSuffix.replaceAll('{id}', Uri.encodeComponent(id));
    final path = suffix.startsWith('/') && suffix.startsWith('/api/') ? suffix : '${widget.module.path}$suffix';
    try {
      final response = await _request(widget.repo.api, action.method, path, action.body);
      if (mounted) {
        _snack('${action.label} completed');
        final data = widget.repo.api.unwrap(response);
        if (data is Map && data.isNotEmpty) {
          await showDialog<void>(context: context, builder: (_) => _JsonDialog(title: action.label, value: data));
        }
      }
      await _refresh();
    } catch (e) {
      if (mounted) _snack(widget.repo.api.normalize(e).message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _snack(String value) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));

  @override
  Widget build(BuildContext context) {
    final entries = item.entries.where((e) => !_hiddenDetailKeys.contains(e.key)).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(_bestTitle(item)),
        actions: [
          if (widget.module.canUpdate && !widget.module.readOnly) IconButton(onPressed: _edit, icon: const Icon(Icons.edit_outlined)),
          if (widget.module.canDelete && !widget.module.readOnly) IconButton(onPressed: _delete, icon: const Icon(Icons.delete_outline)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  CircleAvatar(radius: 25, child: Icon(widget.module.icon)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_bestTitle(item), style: Theme.of(context).textTheme.titleLarge),
                    Text(_bestSubtitle(item), style: Theme.of(context).textTheme.bodyMedium),
                  ])),
                ]),
                if (widget.module.actions.isNotEmpty) ...[
                  const Divider(height: 28),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final action in widget.module.actions)
                      FilledButton.tonalIcon(onPressed: busy ? null : () => _run(action), icon: Icon(action.icon), label: Text(action.label)),
                  ]),
                ],
              ]),
            ),
          ),
          const SizedBox(height: 10),
          for (final entry in entries) _FieldCard(name: entry.key, value: entry.value),
          for (final relation in widget.module.related)
            Card(
              child: ListTile(
                leading: const Icon(Icons.hub_outlined),
                title: Text(relation.label),
                subtitle: const Text('Open related records'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RelatedCollectionScreen(api: widget.repo.api, parent: item, spec: relation))),
              ),
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => showDialog<void>(context: context, builder: (_) => _JsonDialog(title: 'Raw server record', value: item)),
            icon: const Icon(Icons.data_object),
            label: const Text('Advanced JSON view'),
          ),
        ],
      ),
    );
  }
}

class RelatedCollectionScreen extends StatefulWidget {
  const RelatedCollectionScreen({super.key, required this.api, required this.parent, required this.spec});
  final WhatomateApi api;
  final Map<String, dynamic> parent;
  final RelatedCollection spec;

  @override
  State<RelatedCollectionScreen> createState() => _RelatedCollectionScreenState();
}

class _RelatedCollectionScreenState extends State<RelatedCollectionScreen> {
  List<Map<String, dynamic>> items = [];
  bool loading = true;
  String? error;

  String expand(String template, [Map<String, dynamic>? item]) {
    var result = template;
    final values = {...widget.parent, ...?item};
    for (final e in values.entries) {
      result = result.replaceAll('{${e.key}}', Uri.encodeComponent(e.value?.toString() ?? ''));
    }
    return result;
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => loading = true);
    try {
      final response = await widget.api.get(expand(widget.spec.listPath));
      items = _extract(response.data, widget.spec.keys);
      error = null;
    } catch (e) {
      error = widget.api.normalize(e).message;
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> create() async {
    final createPath = widget.spec.createPath ?? widget.spec.listPath;
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => RecordEditorScreen(
        api: widget.api,
        title: 'New ${widget.spec.label}',
        path: expand(createPath),
        initial: widget.spec.seed,
        editableKeys: widget.spec.editableKeys,
        create: true,
        wrapCreateKey: widget.spec.wrapCreateKey,
      )),
    );
    if (changed == true) load();
  }

  Future<void> edit(Map<String, dynamic> item) async {
    final template = widget.spec.updatePath;
    if (template == null) {
      showDialog<void>(context: context, builder: (_) => _JsonDialog(title: widget.spec.label, value: item));
      return;
    }
    final changed = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => RecordEditorScreen(
      api: widget.api,
      title: 'Edit ${widget.spec.label}',
      path: expand(template, item),
      initial: item,
      editableKeys: widget.spec.editableKeys,
      create: false,
    )));
    if (changed == true) load();
  }

  Future<void> remove(Map<String, dynamic> item) async {
    final template = widget.spec.deletePath;
    if (template == null) return;
    try {
      await widget.api.delete(expand(template, item));
      load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.api.normalize(e).message)));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.spec.label), actions: [IconButton(onPressed: load, icon: const Icon(Icons.refresh))]),
    floatingActionButton: (widget.spec.createPath != null || widget.spec.seed.isNotEmpty)
        ? FloatingActionButton(onPressed: create, child: const Icon(Icons.add))
        : null,
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : error != null
            ? _ErrorState(message: error!, retry: load)
            : ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) => ListTile(
                  title: Text(_bestTitle(items[i])),
                  subtitle: Text(_bestSubtitle(items[i])),
                  onTap: () => edit(items[i]),
                  trailing: widget.spec.deletePath == null ? const Icon(Icons.chevron_right) : IconButton(onPressed: () => remove(items[i]), icon: const Icon(Icons.delete_outline)),
                ),
              ),
  );
}

class RecordEditorScreen extends StatefulWidget {
  const RecordEditorScreen({
    super.key,
    required this.api,
    required this.title,
    required this.path,
    required this.initial,
    required this.create,
    this.editableKeys,
    this.wrapCreateKey,
  });
  final WhatomateApi api;
  final String title;
  final String path;
  final Map<String, dynamic> initial;
  final bool create;
  final List<String>? editableKeys;
  final String? wrapCreateKey;

  @override
  State<RecordEditorScreen> createState() => _RecordEditorScreenState();
}

class _RecordEditorScreenState extends State<RecordEditorScreen> {
  late final List<String> keys;
  final controllers = <String, TextEditingController>{};
  final boolValues = <String, bool>{};
  bool saving = false;

  @override
  void initState() {
    super.initState();
    final sourceKeys = widget.editableKeys ?? {...widget.initial.keys}.where((k) => !_readOnlyKeys.contains(k)).toList();
    keys = sourceKeys.where((k) => !_readOnlyKeys.contains(k)).toList();
    for (final key in keys) {
      final value = widget.initial[key];
      if (value is bool) {
        boolValues[key] = value;
      } else {
        controllers[key] = TextEditingController(text: _editorText(value));
      }
    }
  }

  @override
  void dispose() {
    for (final controller in controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  dynamic _parse(String key, String text) {
    final original = widget.initial[key];
    final value = text.trim();
    if (original is Map || original is List || value.startsWith('{') || value.startsWith('[')) {
      if (value.isEmpty) return original is List ? <dynamic>[] : <String, dynamic>{};
      return jsonDecode(value);
    }
    if (original is int) return int.tryParse(value) ?? original;
    if (original is double) return double.tryParse(value) ?? original;
    if (value == 'null') return null;
    return text;
  }

  Future<void> save() async {
    if (saving) return;
    setState(() => saving = true);
    try {
      final payload = <String, dynamic>{};
      for (final key in keys) {
        if (boolValues.containsKey(key)) {
          payload[key] = boolValues[key];
        } else {
          payload[key] = _parse(key, controllers[key]?.text ?? '');
        }
      }
      dynamic requestData = payload;
      if (widget.create && widget.wrapCreateKey != null) requestData = {widget.wrapCreateKey!: [payload]};
      final response = widget.create
          ? await widget.api.post(widget.path, data: requestData)
          : await widget.api.put(widget.path, data: requestData);
      final returned = widget.api.unwrap(response);
      if (!mounted) return;
      if (returned is Map && returned.keys.any((k) => {'key', 'token', 'secret'}.contains(k))) {
        await showDialog<void>(context: context, builder: (_) => _JsonDialog(title: 'Created credentials', value: returned));
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.api.normalize(e).message)));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title), actions: [TextButton(onPressed: saving ? null : save, child: const Text('Save'))]),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (keys.isEmpty)
          const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('This endpoint has no editable fields configured.'))),
        for (final key in keys)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: boolValues.containsKey(key)
                ? SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    title: Text(_label(key)),
                    value: boolValues[key] ?? false,
                    onChanged: (value) => setState(() => boolValues[key] = value),
                  )
                : TextField(
                    controller: controllers[key],
                    minLines: _isComplex(widget.initial[key]) ? 5 : 1,
                    maxLines: _isComplex(widget.initial[key]) ? 14 : (key.contains('description') || key.contains('content') || key.contains('body') ? 6 : 1),
                    obscureText: key.contains('password') || key.contains('secret'),
                    keyboardType: _keyboard(widget.initial[key], key),
                    decoration: InputDecoration(labelText: _label(key), helperText: _isComplex(widget.initial[key]) ? 'JSON value' : null, alignLabelWithHint: true),
                  ),
          ),
        const SizedBox(height: 8),
        FilledButton.icon(onPressed: saving ? null : save, icon: saving ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined), label: Text(widget.create ? 'Create' : 'Save changes')),
      ],
    ),
  );
}

class SettingsEditorScreen extends StatefulWidget {
  const SettingsEditorScreen({super.key, required this.api, required this.title, required this.path, this.editableKeys});
  final WhatomateApi api;
  final String title;
  final String path;
  final List<String>? editableKeys;

  @override
  State<SettingsEditorScreen> createState() => _SettingsEditorScreenState();
}

class _SettingsEditorScreenState extends State<SettingsEditorScreen> {
  Map<String, dynamic>? data;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final raw = widget.api.unwrap(await widget.api.get(widget.path));
      data = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{'value': raw};
      error = null;
    } catch (e) {
      error = widget.api.normalize(e).message;
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title), actions: [IconButton(onPressed: load, icon: const Icon(Icons.refresh))]),
    body: data == null
        ? error != null ? _ErrorState(message: error!, retry: load) : const Center(child: CircularProgressIndicator())
        : ListView(padding: const EdgeInsets.all(16), children: [
            Card(child: ListTile(leading: const Icon(Icons.settings_outlined), title: Text(widget.title), subtitle: const Text('Server-backed settings'))),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () async {
                final changed = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => RecordEditorScreen(api: widget.api, title: 'Edit ${widget.title}', path: widget.path, initial: data!, editableKeys: widget.editableKeys, create: false)));
                if (changed == true) load();
              },
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit settings'),
            ),
            const SizedBox(height: 12),
            ...data!.entries.map((e) => _FieldCard(name: e.key, value: e.value)),
          ]),
  );
}

class _FieldCard extends StatelessWidget {
  const _FieldCard({required this.name, required this.value});
  final String name;
  final dynamic value;

  @override
  Widget build(BuildContext context) {
    final complex = value is Map || value is List;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_label(name), style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 5),
          SelectableText(complex ? const JsonEncoder.withIndent('  ').convert(value) : (value?.toString() ?? '—'), maxLines: complex ? null : 8),
        ]),
      ),
    );
  }
}

class _JsonDialog extends StatelessWidget {
  const _JsonDialog({required this.title, required this.value});
  final String title;
  final dynamic value;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(title),
    content: SizedBox(width: 620, child: SingleChildScrollView(child: SelectableText(const JsonEncoder.withIndent('  ').convert(value), style: const TextStyle(fontFamily: 'monospace')))),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.retry});
  final String message;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.error_outline, size: 42), const SizedBox(height: 10), Text(message, textAlign: TextAlign.center), const SizedBox(height: 12), OutlinedButton(onPressed: retry, child: const Text('Retry')),
  ])));
}

Future<dynamic> _request(WhatomateApi api, String method, String path, Map<String, dynamic> body) {
  switch (method.toUpperCase()) {
    case 'GET': return api.get(path, query: body);
    case 'PUT': return api.put(path, data: body);
    case 'PATCH': return api.patch(path, data: body);
    case 'DELETE': return api.delete(path, data: body);
    default: return api.post(path, data: body);
  }
}

List<Map<String, dynamic>> _extract(dynamic raw, List<String> keys) {
  dynamic value = raw;
  if (value is Map && value['data'] != null) value = value['data'];
  if (value is List) return value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  if (value is Map) {
    for (final key in keys) {
      final candidate = value[key];
      if (candidate is List) return candidate.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    if (value['items'] is List) return (value['items'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }
  return [];
}

const _readOnlyKeys = {
  'id', 'organization_id', 'created_at', 'updated_at', 'deleted_at', 'created_by', 'updated_by', 'created_by_id', 'updated_by_id',
  'user_count', 'member_count', 'usage_count', 'has_secret', 'is_owner', 'created_by_name', 'updated_by_name',
};
const _hiddenDetailKeys = {'deleted_at'};

bool _isComplex(dynamic value) => value is Map || value is List;
String _editorText(dynamic value) {
  if (value == null) return '';
  if (value is Map || value is List) return const JsonEncoder.withIndent('  ').convert(value);
  return value.toString();
}
TextInputType _keyboard(dynamic original, String key) {
  if (original is num) return TextInputType.number;
  if (key.contains('email')) return TextInputType.emailAddress;
  if (key.contains('url')) return TextInputType.url;
  if (key.contains('phone')) return TextInputType.phone;
  return TextInputType.text;
}
String _label(String key) => key.split('_').map((v) => v.isEmpty ? v : '${v[0].toUpperCase()}${v.substring(1)}').join(' ');
String _bestTitle(Map<String, dynamic> item) => (item['name'] ?? item['title'] ?? item['full_name'] ?? item['email'] ?? item['phone_number'] ?? item['event'] ?? item['id'] ?? 'Record').toString();
String _bestSubtitle(Map<String, dynamic> item) {
  for (final key in const ['description', 'status', 'email', 'phone_number', 'category', 'type', 'resource', 'created_at']) {
    final value = item[key];
    if (value != null && value.toString().isNotEmpty) return value.toString();
  }
  return item['id']?.toString() ?? '';
}
