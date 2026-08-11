import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/data_repository.dart';
import '../core/session.dart';
import 'branding.dart';
import 'dashboard_screen.dart';
import 'management_catalog.dart';

class ToolsHubScreen extends StatefulWidget {
  const ToolsHubScreen({super.key, required this.repo, required this.session, required this.api});
  final DataRepository repo;
  final SessionController session;
  final WhatomateApi api;

  @override
  State<ToolsHubScreen> createState() => _ToolsHubScreenState();
}

class _ToolsHubScreenState extends State<ToolsHubScreen> with SingleTickerProviderStateMixin {
  late final TabController tabs = TabController(length: 4, vsync: this);

  static const modules = <_ToolDef>[
    _ToolDef('Dashboard', '/analytics/dashboard', [], Icons.dashboard_outlined, 'analytics', group: 'Overview', single: true),
    _ToolDef('Campaigns', '/campaigns', ['campaigns'], Icons.campaign_outlined, 'campaigns', group: 'Messaging'),
    _ToolDef('Templates', '/templates', ['templates'], Icons.description_outlined, 'templates', group: 'Messaging'),
    _ToolDef('WhatsApp Flows', '/flows', ['flows'], Icons.account_tree_outlined, 'flows.whatsapp', group: 'Messaging'),
    _ToolDef('Canned Responses', '/canned-responses', ['canned_responses'], Icons.quickreply_outlined, 'canned_responses', group: 'Messaging'),
    _ToolDef('Chatbot', '/chatbot/settings', [], Icons.smart_toy_outlined, 'settings.chatbot', group: 'Automation', single: true),
    _ToolDef('Keywords', '/chatbot/keywords', ['keywords', 'rules'], Icons.key_outlined, 'chatbot.keywords', group: 'Automation'),
    _ToolDef('Chatbot Flows', '/chatbot/flows', ['flows'], Icons.schema_outlined, 'flows.chatbot', group: 'Automation'),
    _ToolDef('AI Contexts', '/chatbot/ai-contexts', ['ai_contexts', 'contexts'], Icons.psychology_outlined, 'chatbot.ai', group: 'Automation'),
    _ToolDef('Agent Transfers', '/chatbot/transfers', ['transfers'], Icons.swap_horiz, 'transfers', group: 'Automation'),
    _ToolDef('IVR Flows', '/ivr-flows', ['ivr_flows'], Icons.call_split_outlined, 'ivr_flows', group: 'Calling'),
    _ToolDef('Call Transfers', '/call-transfers', ['call_transfers'], Icons.phone_forwarded_outlined, 'call_transfers', group: 'Calling'),
    _ToolDef('Agent Analytics', '/analytics/agents', ['agents', 'analytics'], Icons.analytics_outlined, 'analytics.agents', group: 'Insights'),
    _ToolDef('Meta Insights', '/analytics/meta', [], Icons.insights_outlined, 'analytics', group: 'Insights', single: true),
    _ToolDef('Accounts', '/accounts', ['accounts'], Icons.business_outlined, 'accounts', group: 'Manage'),
    _ToolDef('Contacts', '/contacts', ['contacts'], Icons.contacts_outlined, 'contacts', group: 'Manage'),
    _ToolDef('Catalogs', '/catalogs', ['catalogs'], Icons.storefront_outlined, 'catalogs', group: 'Manage'),
    _ToolDef('Tags', '/tags', ['tags'], Icons.sell_outlined, 'tags', group: 'Manage'),
    _ToolDef('Teams', '/teams', ['teams'], Icons.groups_outlined, 'teams', group: 'Manage'),
    _ToolDef('Users', '/users', ['users'], Icons.people_outline, 'users', group: 'Manage'),
    _ToolDef('Roles', '/roles', ['roles'], Icons.admin_panel_settings_outlined, 'roles', group: 'Manage'),
    _ToolDef('API Keys', '/api-keys', ['api_keys'], Icons.vpn_key_outlined, 'api_keys', group: 'System'),
    _ToolDef('Webhooks', '/webhooks', ['webhooks'], Icons.webhook_outlined, 'webhooks', group: 'System'),
    _ToolDef('Custom Actions', '/custom-actions', ['custom_actions'], Icons.bolt_outlined, 'custom_actions', group: 'System'),
    _ToolDef('Audit Logs', '/audit-logs', ['audit_logs', 'logs'], Icons.receipt_long_outlined, 'audit_logs', group: 'System'),
    _ToolDef('SSO Settings', '/settings/sso', [], Icons.login_outlined, 'settings.sso', group: 'System', single: true),
    _ToolDef('TTS Settings', '/tts/settings', [], Icons.record_voice_over_outlined, 'settings.general', group: 'System', single: true),
    _ToolDef('Widgets', '/widgets', ['widgets'], Icons.widgets_outlined, 'analytics', group: 'System'),
    _ToolDef('Organization', '/org/settings', [], Icons.settings_outlined, 'settings.general', group: 'System', single: true),
  ];

  List<_ToolDef> get visible => modules.where((m) => m.permission.isEmpty || widget.session.hasPermission(m.permission)).toList();

  void open(_ToolDef tool) {
    if (tool.title == 'Dashboard') {
      Navigator.push(context, MaterialPageRoute(builder: (_) => DashboardScreen(repo: widget.repo)));
      return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => buildManagementModuleScreen(
      repo: widget.repo, title: tool.title, path: tool.path, keys: tool.keys, icon: tool.icon, single: tool.single,
    )));
  }

  @override
  void dispose() { tabs.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      toolbarHeight: 76,
      title: const NexusWordmark(compact: true),
      actions: [IconButton(tooltip: 'Sign out', onPressed: widget.session.logout, icon: const Icon(Icons.logout))],
      bottom: TabBar(
        controller: tabs,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        indicatorColor: nexusBlue,
        labelColor: Colors.black,
        unselectedLabelColor: Colors.black54,
        tabs: const [Tab(text: 'Quick Start'), Tab(text: 'Automation'), Tab(text: 'Manage'), Tab(text: 'System')],
      ),
    ),
    body: TabBarView(controller: tabs, children: [
      _quickStart(),
      _toolGrid(visible.where((m) => ['Automation', 'Calling', 'Messaging'].contains(m.group)).toList()),
      _toolGrid(visible.where((m) => ['Manage', 'Insights', 'Overview'].contains(m.group)).toList()),
      _toolGrid(visible.where((m) => m.group == 'System').toList()),
    ]),
  );

  Widget _quickStart() {
    final featured = visible.where((m) => const ['Dashboard', 'Campaigns', 'Contacts', 'Chatbot Flows', 'IVR Flows'].contains(m.title)).toList();
    const colors = [nexusBlue, nexusPink, Color(0xffffdf75), Color(0xffd6f5ff), Color(0xffd8ffc9)];
    return ListView(padding: const EdgeInsets.fromLTRB(20, 22, 20, 28), children: [
      Text('Quick Start', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 18),
      SizedBox(height: 214, child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: featured.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, i) {
          final tool = featured[i]; final dark = i == 0;
          return SizedBox(width: 265, child: Card(
            color: colors[i % colors.length],
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            child: InkWell(borderRadius: BorderRadius.circular(28), onTap: () => open(tool), child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(tool.icon, color: dark ? Colors.white : Colors.black, size: 30),
                const Spacer(),
                Text(tool.title, style: TextStyle(color: dark ? Colors.white : Colors.black, fontSize: 25, fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                Text('Open ${tool.title}', style: TextStyle(color: dark ? Colors.white : Colors.black87, fontSize: 16)),
              ]),
            )),
          ));
        },
      )),
      const SizedBox(height: 28),
      Text('Tools And More', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 12),
      _profileCard(),
      const SizedBox(height: 12),
      _toolGrid(visible.take(9).toList(), embedded: true),
    ]);
  }

  Widget _profileCard() => Card(child: ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
    leading: const CircleAvatar(backgroundColor: nexusPink, child: Icon(Icons.person_outline, color: Colors.black)),
    title: Text(widget.session.displayName),
    subtitle: Text(widget.session.user?['email']?.toString() ?? ''),
    trailing: Switch(value: widget.session.user?['is_available'] != false, onChanged: widget.session.setAvailability),
  ));

  Widget _toolGrid(List<_ToolDef> tools, {bool embedded = false}) => GridView.builder(
    padding: embedded ? EdgeInsets.zero : const EdgeInsets.all(18),
    shrinkWrap: embedded,
    physics: embedded ? const NeverScrollableScrollPhysics() : null,
    itemCount: tools.length,
    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 210, childAspectRatio: 1.32, crossAxisSpacing: 10, mainAxisSpacing: 10),
    itemBuilder: (context, i) { final tool = tools[i]; return Card(child: InkWell(
      borderRadius: BorderRadius.circular(24), onTap: () => open(tool),
      child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(tool.icon, color: nexusBlue), const Spacer(), Text(tool.title, maxLines: 2, style: const TextStyle(fontWeight: FontWeight.w600)),
      ])),
    )); },
  );
}

class _ToolDef {
  const _ToolDef(this.title, this.path, this.keys, this.icon, this.permission, {required this.group, this.single = false});
  final String title, path, permission, group;
  final List<String> keys;
  final IconData icon;
  final bool single;
}
