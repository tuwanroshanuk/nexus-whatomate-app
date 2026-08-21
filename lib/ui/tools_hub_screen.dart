import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/data_repository.dart';
import '../core/session.dart';
import 'branding.dart';
import 'dashboard_screen.dart';
import 'management_catalog.dart';

class ToolsHubScreen extends StatefulWidget {
  const ToolsHubScreen({
    super.key,
    required this.repo,
    required this.session,
    required this.api,
    required this.openChats,
    required this.openContacts,
    required this.openDialer,
    required this.openCalls,
  });

  final DataRepository repo;
  final SessionController session;
  final WhatomateApi api;
  final VoidCallback openChats;
  final VoidCallback openContacts;
  final VoidCallback openDialer;
  final VoidCallback openCalls;

  @override
  State<ToolsHubScreen> createState() => _ToolsHubScreenState();
}

class _ToolsHubScreenState extends State<ToolsHubScreen> {
  String selectedGroup = 'Overview';

  static const groups = [
    'Overview',
    'Messaging',
    'Automation',
    'Calling',
    'Insights',
    'Manage',
    'System',
  ];
  static const modules = <_ToolDef>[
    _ToolDef(
      'Dashboard',
      '/analytics/dashboard',
      [],
      Icons.dashboard_outlined,
      'analytics',
      group: 'Overview',
      single: true,
    ),
    _ToolDef(
      'Campaigns',
      '/campaigns',
      ['campaigns'],
      Icons.campaign_outlined,
      'campaigns',
      group: 'Messaging',
    ),
    _ToolDef(
      'Templates',
      '/templates',
      ['templates'],
      Icons.description_outlined,
      'templates',
      group: 'Messaging',
    ),
    _ToolDef(
      'WhatsApp Flows',
      '/flows',
      ['flows'],
      Icons.account_tree_outlined,
      'flows.whatsapp',
      group: 'Messaging',
    ),
    _ToolDef(
      'Canned Responses',
      '/canned-responses',
      ['canned_responses'],
      Icons.quickreply_outlined,
      'canned_responses',
      group: 'Messaging',
    ),
    _ToolDef(
      'Chatbot',
      '/chatbot/settings',
      [],
      Icons.smart_toy_outlined,
      'settings.chatbot',
      group: 'Automation',
      single: true,
    ),
    _ToolDef(
      'Keywords',
      '/chatbot/keywords',
      ['keywords', 'rules'],
      Icons.key_outlined,
      'chatbot.keywords',
      group: 'Automation',
    ),
    _ToolDef(
      'Chatbot Flows',
      '/chatbot/flows',
      ['flows'],
      Icons.schema_outlined,
      'flows.chatbot',
      group: 'Automation',
    ),
    _ToolDef(
      'AI Contexts',
      '/chatbot/ai-contexts',
      ['ai_contexts', 'contexts'],
      Icons.psychology_outlined,
      'chatbot.ai',
      group: 'Automation',
    ),
    _ToolDef(
      'Agent Transfers',
      '/chatbot/transfers',
      ['transfers'],
      Icons.swap_horiz,
      'transfers',
      group: 'Automation',
    ),
    _ToolDef(
      'IVR Flows',
      '/ivr-flows',
      ['ivr_flows'],
      Icons.call_split_outlined,
      'ivr_flows',
      group: 'Calling',
    ),
    _ToolDef(
      'Call Transfers',
      '/call-transfers',
      ['call_transfers'],
      Icons.phone_forwarded_outlined,
      'call_transfers',
      group: 'Calling',
    ),
    _ToolDef(
      'Agent Analytics',
      '/analytics/agents',
      ['agents', 'analytics'],
      Icons.analytics_outlined,
      'analytics.agents',
      group: 'Insights',
    ),
    _ToolDef(
      'Meta Insights',
      '/analytics/meta',
      [],
      Icons.insights_outlined,
      'analytics',
      group: 'Insights',
      single: true,
    ),
    _ToolDef(
      'Accounts',
      '/accounts',
      ['accounts'],
      Icons.business_outlined,
      'accounts',
      group: 'Manage',
    ),
    _ToolDef(
      'Contacts',
      '/contacts',
      ['contacts'],
      Icons.contacts_outlined,
      'contacts',
      group: 'Manage',
    ),
    _ToolDef(
      'Catalogs',
      '/catalogs',
      ['catalogs'],
      Icons.storefront_outlined,
      'catalogs',
      group: 'Manage',
    ),
    _ToolDef(
      'Tags',
      '/tags',
      ['tags'],
      Icons.sell_outlined,
      'tags',
      group: 'Manage',
    ),
    _ToolDef(
      'Teams',
      '/teams',
      ['teams'],
      Icons.groups_outlined,
      'teams',
      group: 'Manage',
    ),
    _ToolDef(
      'Users',
      '/users',
      ['users'],
      Icons.people_outline,
      'users',
      group: 'Manage',
    ),
    _ToolDef(
      'Roles',
      '/roles',
      ['roles'],
      Icons.admin_panel_settings_outlined,
      'roles',
      group: 'Manage',
    ),
    _ToolDef(
      'API Keys',
      '/api-keys',
      ['api_keys'],
      Icons.vpn_key_outlined,
      'api_keys',
      group: 'System',
    ),
    _ToolDef(
      'Webhooks',
      '/webhooks',
      ['webhooks'],
      Icons.webhook_outlined,
      'webhooks',
      group: 'System',
    ),
    _ToolDef(
      'Custom Actions',
      '/custom-actions',
      ['custom_actions'],
      Icons.bolt_outlined,
      'custom_actions',
      group: 'System',
    ),
    _ToolDef(
      'Audit Logs',
      '/audit-logs',
      ['audit_logs', 'logs'],
      Icons.receipt_long_outlined,
      'audit_logs',
      group: 'System',
    ),
    _ToolDef(
      'SSO Settings',
      '/settings/sso',
      [],
      Icons.login_outlined,
      'settings.sso',
      group: 'System',
      single: true,
    ),
    _ToolDef(
      'TTS Settings',
      '/tts/settings',
      [],
      Icons.record_voice_over_outlined,
      'settings.general',
      group: 'System',
      single: true,
    ),
    _ToolDef(
      'Widgets',
      '/widgets',
      ['widgets'],
      Icons.widgets_outlined,
      'analytics',
      group: 'System',
    ),
    _ToolDef(
      'Organization',
      '/org/settings',
      [],
      Icons.settings_outlined,
      'settings.general',
      group: 'System',
      single: true,
    ),
  ];

  List<_ToolDef> get visible => modules
      .where(
        (m) =>
            m.permission.isEmpty || widget.session.hasPermission(m.permission),
      )
      .toList();

  void open(_ToolDef tool) {
    if (tool.title == 'Dashboard') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => DashboardScreen(repo: widget.repo)),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => buildManagementModuleScreen(
          repo: widget.repo,
          title: tool.title,
          path: tool.path,
          keys: tool.keys,
          icon: tool.icon,
          single: tool.single,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tools = visible.where((tool) => tool.group == selectedGroup).toList();
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 14, 8),
                child: Row(
                  children: [
                    const NexusWordmark(compact: true),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Sign out',
                      onPressed: widget.session.logout,
                      icon: const Icon(Icons.logout_rounded, size: 29),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 32, 0, 0),
                child: Text(
                  'Quick Start',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 250,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
                  scrollDirection: Axis.horizontal,
                  children: [
                    _ActionCard(
                      title: 'Chats',
                      description: 'View conversations and reply in real time',
                      action: 'View Chats',
                      icon: Icons.chat_bubble_outline_rounded,
                      color: nexusBlue,
                      foreground: Colors.white,
                      onTap: widget.openChats,
                    ),
                    _ActionCard(
                      title: 'Contacts',
                      description: 'Create and manage customer contacts',
                      action: 'View Contacts',
                      icon: Icons.contacts_outlined,
                      color: nexusPink,
                      foreground: Colors.black,
                      onTap: widget.openContacts,
                    ),
                    _ActionCard(
                      title: 'Dialer',
                      description: 'Start a WhatsApp voice call',
                      action: 'Open Dialer',
                      icon: Icons.dialpad_rounded,
                      color: const Color(0xffffdf75),
                      foreground: Colors.black,
                      onTap: widget.openDialer,
                    ),
                    _ActionCard(
                      title: 'Calls',
                      description: 'Incoming calls and complete call history',
                      action: 'View Calls',
                      icon: Icons.phone_in_talk_outlined,
                      color: Colors.black,
                      foreground: Colors.white,
                      onTap: widget.openCalls,
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 10),
                child: Text(
                  'Tools And More',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 48,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  scrollDirection: Axis.horizontal,
                  itemCount: groups.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 4),
                  itemBuilder: (_, i) {
                    final group = groups[i];
                    final selected = group == selectedGroup;
                    return TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.black,
                        backgroundColor: selected
                            ? const Color(0xffffdf75)
                            : Colors.transparent,
                      ),
                      onPressed: () => setState(() => selectedGroup = group),
                      child: Text(
                        group,
                        style: TextStyle(
                          fontWeight: selected
                              ? FontWeight.w800
                              : FontWeight.w500,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 210,
                  childAspectRatio: 1.28,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                delegate: SliverChildBuilderDelegate((context, i) {
                  final tool = tools[i];
                  return Card(
                    color: i.isEven
                        ? const Color(0xfff5f5f5)
                        : const Color(0xfffff7cf),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => open(tool),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(tool.icon, color: Colors.black, size: 27),
                            const Spacer(),
                            Text(
                              tool.title,
                              maxLines: 2,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Open',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }, childCount: tools.length),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.title,
    required this.description,
    required this.action,
    required this.icon,
    required this.color,
    required this.foreground,
    required this.onTap,
  });
  final String title, description, action;
  final IconData icon;
  final Color color, foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 14),
    child: SizedBox(
      width: 280,
      child: Card(
        margin: EdgeInsets.zero,
        color: color,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: foreground, size: 28),
                    const Spacer(),
                    Icon(Icons.arrow_outward_rounded, color: foreground),
                  ],
                ),
                const Spacer(),
                Text(
                  title,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  maxLines: 2,
                  style: TextStyle(
                    color: foreground.withValues(alpha: .82),
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  action,
                  style: TextStyle(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _ToolDef {
  const _ToolDef(
    this.title,
    this.path,
    this.keys,
    this.icon,
    this.permission, {
    required this.group,
    this.single = false,
  });
  final String title, path, permission, group;
  final List<String> keys;
  final IconData icon;
  final bool single;
}
