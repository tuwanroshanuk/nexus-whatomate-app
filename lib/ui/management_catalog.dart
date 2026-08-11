import 'package:flutter/material.dart';

import '../core/data_repository.dart';
import 'admin_module_screen.dart';
import 'dashboard_screen.dart';

Widget buildManagementModuleScreen({
  required DataRepository repo,
  required String title,
  required String path,
  required List<String> keys,
  required IconData icon,
  required bool single,
}) {
  if (title == 'Dashboard') return DashboardScreen(repo: repo);
  if (title == 'Chatbot') {
    return SettingsEditorScreen(api: repo.api, title: 'Chatbot settings', path: '/chatbot/settings');
  }
  if (title == 'Organization Settings') {
    return SettingsEditorScreen(api: repo.api, title: title, path: '/org/settings');
  }
  if (title == 'TTS Settings') {
    return SettingsEditorScreen(api: repo.api, title: title, path: '/tts/settings');
  }
  if (title == 'Profile') return _ProfileScreen(repo: repo);
  if (title == 'SSO Settings') return _SSOSettingsScreen(repo: repo);
  if (title == 'Agent Analytics') return _ServerDataScreen(repo: repo, title: title, path: path);
  if (single) return _ServerDataScreen(repo: repo, title: title, path: path);

  return AdminModuleScreen(
    repo: repo,
    module: _moduleFor(title, path, keys, icon),
  );
}

ApiModule _moduleFor(String title, String path, List<String> keys, IconData icon) {
  switch (title) {
    case 'Templates':
      return ApiModule(
        title: title,
        path: path,
        keys: keys,
        icon: icon,
        seed: const {
          'name': '',
          'language': 'en_US',
          'category': 'UTILITY',
          'body_content': '',
        },
        editableKeys: const ['name', 'language', 'category', 'body_content', 'header_type', 'header_content', 'footer_content', 'buttons'],
        actions: const [ModuleAction('Publish', '/{id}/publish', icon: Icons.cloud_upload_outlined)],
        globalActions: const [ModuleAction('Sync', '/sync', icon: Icons.sync)],
      );
    case 'WhatsApp Flows':
      return ApiModule(
        title: title,
        path: path,
        keys: keys,
        icon: icon,
        seed: const {'name': '', 'categories': <String>[], 'flow_json': <String, dynamic>{}},
        editableKeys: const ['name', 'categories', 'flow_json'],
        actions: const [
          ModuleAction('Save to Meta', '/{id}/save-to-meta', icon: Icons.cloud_sync_outlined),
          ModuleAction('Publish', '/{id}/publish', icon: Icons.publish_outlined),
          ModuleAction('Deprecate', '/{id}/deprecate', icon: Icons.archive_outlined),
          ModuleAction('Duplicate', '/{id}/duplicate', icon: Icons.copy_outlined),
        ],
        globalActions: const [ModuleAction('Sync', '/sync', icon: Icons.sync)],
      );
    case 'Campaigns':
      return ApiModule(
        title: title,
        path: path,
        keys: keys,
        icon: icon,
        seed: const {'name': '', 'template_name': '', 'whatsapp_account': '', 'scheduled_at': null},
        editableKeys: const ['name', 'template_name', 'whatsapp_account', 'scheduled_at', 'template_params', 'header_params'],
        actions: const [
          ModuleAction('Start', '/{id}/start', icon: Icons.play_arrow),
          ModuleAction('Pause', '/{id}/pause', icon: Icons.pause),
          ModuleAction('Cancel', '/{id}/cancel', icon: Icons.stop_circle_outlined),
          ModuleAction('Retry failed', '/{id}/retry-failed', icon: Icons.replay),
        ],
        related: const [
          RelatedCollection(
            label: 'Recipients',
            listPath: '/campaigns/{id}/recipients',
            keys: ['recipients'],
            deletePath: '/campaigns/{parent_id}/recipients/{id}',
            idField: 'id',
          ),
        ],
      );
    case 'Keywords':
      return ApiModule(
        title: title,
        path: path,
        keys: keys,
        icon: icon,
        seed: const {
          'keyword': '',
          'match_type': 'contains',
          'response_type': 'text',
          'response_content': '',
          'is_active': true,
        },
        editableKeys: const ['keyword', 'match_type', 'response_type', 'response_content', 'priority', 'is_active'],
      );
    case 'Chatbot Flows':
      return ApiModule(
        title: title,
        path: path,
        keys: keys,
        icon: icon,
        seed: const {'name': '', 'description': '', 'nodes': <dynamic>[], 'edges': <dynamic>[], 'is_active': true},
        editableKeys: const ['name', 'description', 'nodes', 'edges', 'is_active'],
      );
    case 'AI Contexts':
      return ApiModule(
        title: title,
        path: path,
        keys: keys,
        icon: icon,
        seed: const {'name': '', 'description': '', 'content': '', 'is_active': true},
        editableKeys: const ['name', 'description', 'content', 'instructions', 'is_active'],
      );
    case 'Agent Transfers':
      return ApiModule(
        title: title,
        path: path,
        keys: keys,
        icon: icon,
        canCreate: false,
        canUpdate: false,
        canDelete: false,
        readOnly: true,
      );
    case 'Accounts':
      return ApiModule(
        title: title,
        path: path,
        keys: keys,
        icon: icon,
        seed: const {'name': '', 'phone_number_id': '', 'business_account_id': '', 'access_token': ''},
        editableKeys: const ['name', 'phone_number_id', 'business_account_id', 'access_token', 'app_id', 'app_secret', 'webhook_verify_token', 'is_active'],
        actions: const [
          ModuleAction('Test connection', '/{id}/test', icon: Icons.network_check),
          ModuleAction('Subscribe app', '/{id}/subscribe', icon: Icons.notifications_active_outlined),
        ],
      );
    case 'Canned responses':
      return ApiModule(
        title: title,
        path: path,
        keys: keys,
        icon: icon,
        seed: const {'name': '', 'shortcut': '', 'content': '', 'category': '', 'is_active': true, 'buttons': <dynamic>[]},
        editableKeys: const ['name', 'shortcut', 'content', 'category', 'is_active', 'buttons'],
      );
    case 'Tags':
      return ApiModule(
        title: title,
        path: path,
        keys: keys,
        icon: icon,
        idField: 'name',
        seed: const {'name': '', 'color': '#0738F9'},
        editableKeys: const ['name', 'color'],
      );
    case 'Teams':
      return ApiModule(
        title: title,
        path: path,
        keys: keys,
        icon: icon,
        seed: const {'name': '', 'description': '', 'is_active': true},
        editableKeys: const ['name', 'description', 'is_active'],
        related: const [
          RelatedCollection(
            label: 'Members',
            listPath: '/teams/{id}/members',
            keys: ['members'],
            createPath: '/teams/{id}/members',
            deletePath: '/teams/{parent_id}/members/{user_id}',
            seed: {'user_id': ''},
            editableKeys: ['user_id'],
            idField: 'user_id',
          ),
        ],
      );
    case 'Users':
      return ApiModule(
        title: title,
        path: path,
        keys: keys,
        icon: icon,
        seed: const {'email': '', 'full_name': '', 'password': '', 'role_id': '', 'is_active': true},
        editableKeys: const ['email', 'full_name', 'password', 'role_id', 'is_active', 'is_available'],
      );
    case 'Roles':
      return ApiModule(
        title: title,
        path: path,
        keys: keys,
        icon: icon,
        seed: const {'name': '', 'description': '', 'permissions': <dynamic>[]},
        editableKeys: const ['name', 'description', 'permissions'],
      );
    case 'API Keys':
      return ApiModule(
        title: title,
        path: path,
        keys: keys,
        icon: icon,
        seed: const {'name': '', 'scopes': <String>[]},
        editableKeys: const ['name', 'scopes', 'expires_at', 'is_active'],
      );
    case 'Webhooks':
      return ApiModule(
        title: title,
        path: path,
        keys: keys,
        icon: icon,
        seed: const {'name': '', 'url': '', 'events': <String>[], 'secret': '', 'is_active': true},
        editableKeys: const ['name', 'url', 'events', 'secret', 'headers', 'is_active'],
        actions: const [ModuleAction('Send test', '/{id}/test', icon: Icons.send_outlined)],
      );
    case 'Custom Actions':
      return ApiModule(
        title: title,
        path: path,
        keys: keys,
        icon: icon,
        seed: const {'name': '', 'type': 'http', 'url': '', 'method': 'POST', 'is_active': true},
        editableKeys: const ['name', 'description', 'type', 'url', 'method', 'headers', 'body', 'script', 'icon', 'is_active'],
        actions: const [ModuleAction('Execute', '/{id}/execute', icon: Icons.play_arrow)],
      );
    case 'Audit Logs':
      return ApiModule(title: title, path: path, keys: keys, icon: icon, canCreate: false, canUpdate: false, canDelete: false, readOnly: true);
    case 'IVR Flows':
      return ApiModule(
        title: title,
        path: path,
        keys: keys,
        icon: icon,
        seed: const {'name': '', 'description': '', 'is_active': true, 'is_call_start': false, 'nodes': <dynamic>[], 'edges': <dynamic>[]},
        editableKeys: const ['name', 'description', 'is_active', 'is_call_start', 'nodes', 'edges'],
      );
    case 'Call Transfers':
      return ApiModule(title: title, path: path, keys: keys, icon: icon, canCreate: false, canUpdate: false, canDelete: false, readOnly: true);
    case 'Catalogs':
      return ApiModule(
        title: title,
        path: path,
        keys: keys,
        icon: icon,
        seed: const {'name': '', 'catalog_id': ''},
        editableKeys: const ['name', 'catalog_id'],
        canUpdate: false,
        globalActions: const [ModuleAction('Sync', '/sync', icon: Icons.sync)],
        related: const [
          RelatedCollection(
            label: 'Products',
            listPath: '/catalogs/{id}/products',
            keys: ['products'],
            createPath: '/catalogs/{id}/products',
            seed: {'name': '', 'retailer_id': '', 'price': 0, 'currency': 'USD'},
            editableKeys: ['name', 'retailer_id', 'description', 'price', 'currency', 'image_url', 'url', 'availability'],
            updatePath: '/products/{id}',
            deletePath: '/products/{id}',
          ),
        ],
      );
    case 'Widgets':
      return ApiModule(
        title: title,
        path: path,
        keys: keys,
        icon: icon,
        seed: const {'name': '', 'type': 'metric', 'data_source': '', 'config': <String, dynamic>{}},
        editableKeys: const ['name', 'description', 'type', 'data_source', 'config', 'position', 'size'],
      );
    default:
      return ApiModule(title: title, path: path, keys: keys, icon: icon, seed: const {'name': ''});
  }
}

class _ServerDataScreen extends StatefulWidget {
  const _ServerDataScreen({required this.repo, required this.title, required this.path});
  final DataRepository repo;
  final String title;
  final String path;
  @override
  State<_ServerDataScreen> createState() => _ServerDataScreenState();
}

class _ServerDataScreenState extends State<_ServerDataScreen> {
  dynamic data;
  String? error;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() { loading = true; error = null; });
    try {
      data = widget.repo.api.unwrap(await widget.repo.api.get(widget.path));
    } catch (e) {
      error = widget.repo.api.normalize(e).message;
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.title), actions: [IconButton(onPressed: load, icon: const Icon(Icons.refresh))]),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : error != null
                ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(error!)))
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (data is Map)
                        for (final entry in (data as Map).entries)
                          Card(child: ListTile(title: Text(entry.key.toString()), subtitle: SelectableText(entry.value?.toString() ?? '—')))
                      else
                        SelectableText(data?.toString() ?? 'No data'),
                    ],
                  ),
      );
}

class _ProfileScreen extends StatefulWidget {
  const _ProfileScreen({required this.repo});
  final DataRepository repo;
  @override
  State<_ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<_ProfileScreen> {
  Map<String, dynamic>? user;
  String? error;
  bool loading = true;

  @override
  void initState() { super.initState(); load(); }

  Future<void> load() async {
    setState(() { loading = true; error = null; });
    try {
      final raw = widget.repo.api.unwrap(await widget.repo.api.get('/me'));
      user = raw is Map ? Map<String, dynamic>.from(raw) : {};
    } catch (e) {
      error = widget.repo.api.normalize(e).message;
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> editProfile() async {
    if (user == null) return;
    final changed = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => RecordEditorScreen(
      api: widget.repo.api,
      title: 'Edit profile',
      path: '/me/settings',
      initial: user!,
      editableKeys: const ['full_name', 'email', 'language', 'timezone', 'notification_settings'],
      create: false,
    )));
    if (changed == true) load();
  }

  Future<void> changePassword() async {
    final current = TextEditingController();
    final next = TextEditingController();
    final confirm = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Change password'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: current, obscureText: true, decoration: const InputDecoration(labelText: 'Current password')),
        const SizedBox(height: 10),
        TextField(controller: next, obscureText: true, decoration: const InputDecoration(labelText: 'New password')),
        const SizedBox(height: 10),
        TextField(controller: confirm, obscureText: true, decoration: const InputDecoration(labelText: 'Confirm password')),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Change'))],
    ));
    if (ok != true) return;
    if (next.text != confirm.text) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Passwords do not match')));
      return;
    }
    try {
      await widget.repo.api.put('/me/password', data: {'current_password': current.text, 'new_password': next.text});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password changed')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.repo.api.normalize(e).message)));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Profile'), actions: [IconButton(onPressed: load, icon: const Icon(Icons.refresh))]),
    body: loading ? const Center(child: CircularProgressIndicator()) : error != null ? Center(child: Text(error!)) : ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(child: ListTile(leading: const CircleAvatar(child: Icon(Icons.person)), title: Text((user?['full_name'] ?? user?['email'] ?? 'User').toString()), subtitle: Text((user?['email'] ?? '').toString()))),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: editProfile, icon: const Icon(Icons.edit_outlined), label: const Text('Edit profile')),
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: changePassword, icon: const Icon(Icons.password_outlined), label: const Text('Change password')),
      ],
    ),
  );
}

class _SSOSettingsScreen extends StatefulWidget {
  const _SSOSettingsScreen({required this.repo});
  final DataRepository repo;
  @override
  State<_SSOSettingsScreen> createState() => _SSOSettingsScreenState();
}

class _SSOSettingsScreenState extends State<_SSOSettingsScreen> {
  List<Map<String, dynamic>> providers = [];
  bool loading = true;
  String? error;

  @override
  void initState() { super.initState(); load(); }

  Future<void> load() async {
    setState(() { loading = true; error = null; });
    try {
      final raw = widget.repo.api.unwrap(await widget.repo.api.get('/settings/sso'));
      dynamic value = raw;
      if (raw is Map) value = raw['providers'] ?? raw['settings'] ?? raw;
      if (value is List) {
        providers = value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      } else if (value is Map) {
        providers = value.entries.map((e) {
          final item = e.value is Map ? Map<String, dynamic>.from(e.value as Map) : <String, dynamic>{'value': e.value};
          item.putIfAbsent('provider', () => e.key.toString());
          return item;
        }).toList();
      }
    } catch (e) {
      error = widget.repo.api.normalize(e).message;
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> edit(Map<String, dynamic> provider) async {
    final id = (provider['provider'] ?? provider['name'] ?? provider['id'])?.toString();
    if (id == null || id.isEmpty) return;
    final changed = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => RecordEditorScreen(
      api: widget.repo.api,
      title: 'Edit $id SSO',
      path: '/settings/sso/${Uri.encodeComponent(id)}',
      initial: provider,
      editableKeys: const ['enabled', 'client_id', 'client_secret', 'issuer_url', 'authorization_url', 'token_url', 'user_info_url', 'scopes'],
      create: false,
    )));
    if (changed == true) load();
  }

  Future<void> remove(Map<String, dynamic> provider) async {
    final id = (provider['provider'] ?? provider['name'] ?? provider['id'])?.toString();
    if (id == null || id.isEmpty) return;
    try {
      await widget.repo.api.delete('/settings/sso/${Uri.encodeComponent(id)}');
      await load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.repo.api.normalize(e).message)));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('SSO Settings'), actions: [IconButton(onPressed: load, icon: const Icon(Icons.refresh))]),
    body: loading ? const Center(child: CircularProgressIndicator()) : error != null ? Center(child: Text(error!)) : ListView.separated(
      itemCount: providers.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final provider = providers[i];
        final name = (provider['provider'] ?? provider['name'] ?? 'Provider').toString();
        return ListTile(
          leading: const Icon(Icons.login_outlined),
          title: Text(name),
          subtitle: Text(provider['enabled'] == true ? 'Enabled' : 'Disabled'),
          onTap: () => edit(provider),
          trailing: IconButton(onPressed: () => remove(provider), icon: const Icon(Icons.delete_outline)),
        );
      },
    ),
  );
}
