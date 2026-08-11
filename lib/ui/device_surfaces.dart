import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

import '../core/api_client.dart';
import '../core/calling.dart';
import '../core/data_repository.dart';

const _contactProperties = <ContactProperty>{
  ContactProperty.name,
  ContactProperty.phone,
};

class EnhancedContactsScreen extends StatefulWidget {
  const EnhancedContactsScreen({super.key, required this.repo, required this.calls});
  final DataRepository repo;
  final CallingService calls;

  @override
  State<EnhancedContactsScreen> createState() => _EnhancedContactsScreenState();
}

class _EnhancedContactsScreenState extends State<EnhancedContactsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController tabs = TabController(length: 2, vsync: this);
  final search = TextEditingController();
  List<Map<String, dynamic>> serverContacts = [];
  List<Contact> deviceContacts = [];
  bool loadingServer = true;
  bool loadingDevice = false;
  bool devicePermission = false;
  Timer? debounce;

  @override
  void initState() {
    super.initState();
    _loadServer();
    tabs.addListener(() {
      if (tabs.index == 1 && deviceContacts.isEmpty && !loadingDevice) {
        _loadDevice();
      }
    });
  }

  @override
  void dispose() {
    tabs.dispose();
    search.dispose();
    debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadServer() async {
    if (mounted) setState(() => loadingServer = true);
    try {
      serverContacts = await widget.repo.contacts(search: search.text.trim());
    } catch (e) {
      if (mounted) _snack(widget.repo.api.normalize(e).message);
    } finally {
      if (mounted) setState(() => loadingServer = false);
    }
  }

  Future<void> _loadDevice() async {
    setState(() => loadingDevice = true);
    try {
      final permission = await FlutterContacts.permissions.request(PermissionType.read);
      devicePermission = permission == PermissionStatus.granted;
      if (devicePermission) {
        deviceContacts = await FlutterContacts.getAll(properties: _contactProperties);
        deviceContacts.sort((a, b) =>
            (a.displayName ?? '').toLowerCase().compareTo((b.displayName ?? '').toLowerCase()));
      }
    } catch (e) {
      if (mounted) _snack('Unable to read device contacts: $e');
    } finally {
      if (mounted) setState(() => loadingDevice = false);
    }
  }

  List<Contact> get _filteredDevice {
    final q = search.text.trim().toLowerCase();
    if (q.isEmpty) return deviceContacts;
    return deviceContacts.where((c) {
      if ((c.displayName ?? '').toLowerCase().contains(q)) return true;
      return c.phones.any((p) => p.number.toLowerCase().contains(q));
    }).toList();
  }

  Future<void> _createServerContact() async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Whatomate contact'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
          const SizedBox(height: 10),
          TextField(
            controller: phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone number'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
        ],
      ),
    );
    if (ok != true || phone.text.trim().isEmpty) return;
    try {
      await widget.repo.createContact(phone.text.trim(), name: name.text.trim());
      await _loadServer();
    } catch (e) {
      if (mounted) _snack(widget.repo.api.normalize(e).message);
    }
  }

  Future<void> _import(Contact contact, String number) async {
    try {
      final displayName = (contact.displayName ?? '').trim();
      await widget.repo.createContact(number, name: displayName);
      if (mounted) _snack('${displayName.isEmpty ? number : displayName} imported');
      await _loadServer();
    } catch (e) {
      final normalized = widget.repo.api.normalize(e);
      if (mounted) _snack(normalized.message);
    }
  }

  Future<void> _callServerContact(Map<String, dynamic> contact) async {
    try {
      final accounts = await widget.repo.accounts();
      final account = (contact['whatsapp_account'] ??
              (accounts.isNotEmpty ? accounts.first['name'] : null))
          ?.toString();
      if (account == null || account.isEmpty) {
        throw ApiException('No WhatsApp account configured');
      }
      final id = contact['id']?.toString();
      if (id == null || id.isEmpty) throw ApiException('Contact ID is missing');
      final permission = await widget.calls.callPermission(id, account);
      final status = permission['status']?.toString();
      if (status != 'accepted' && status != 'temporary' && status != 'permanent') {
        await widget.calls.requestPermission(id, account);
        if (mounted) _snack('Call permission request sent');
        return;
      }
      await widget.calls.makeOutgoingCall(
        contactId: id,
        contactName: _serverName(contact),
        whatsappAccount: account,
        phone: contact['phone_number']?.toString() ?? '',
      );
    } catch (e) {
      if (mounted) _snack(widget.repo.api.normalize(e).message);
    }
  }

  Future<void> _deleteServerContact(Map<String, dynamic> contact) async {
    final name = _serverName(contact);
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Permanently delete contact?'),
      content: Text('$name and all related messages, notes, transfers, permissions and call history will be permanently removed. This cannot be undone.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(context, true), child: const Text('Delete permanently')),
      ],
    ));
    if (confirmed != true) return;
    try {
      await widget.repo.deleteContact(contact['id'].toString());
      await _loadServer();
      if (mounted) _snack('$name permanently deleted');
    } catch (e) {
      if (mounted) _snack(widget.repo.api.normalize(e).message);
    }
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contacts'),
        actions: [
          IconButton(
            onPressed: _createServerContact,
            tooltip: 'New contact',
            icon: const Icon(Icons.person_add_alt_1),
          ),
          IconButton(
            onPressed: tabs.index == 0 ? _loadServer : _loadDevice,
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: TabBar(
          controller: tabs,
          tabs: const [Tab(text: 'Whatomate'), Tab(text: 'Phone')],
        ),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: search,
            onChanged: (_) {
              debounce?.cancel();
              debounce = Timer(const Duration(milliseconds: 250), () {
                if (tabs.index == 0) {
                  _loadServer();
                } else if (mounted) {
                  setState(() {});
                }
              });
            },
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search name or phone',
            ),
          ),
        ),
        Expanded(
          child: TabBarView(controller: tabs, children: [
            loadingServer
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _loadServer,
                    child: ListView.separated(
                      itemCount: serverContacts.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final c = serverContacts[i];
                        return ListTile(
                          leading: CircleAvatar(child: Text(_initials(_serverName(c)))),
                          title: Text(_serverName(c)),
                          subtitle: Text(c['phone_number']?.toString() ?? ''),
                          trailing: IconButton(
                            onPressed: () => _callServerContact(c),
                            icon: const Icon(Icons.phone_outlined),
                          ),
                          onTap: () => _showServerContact(c),
                        );
                      },
                    ),
                  ),
            _deviceList(),
          ]),
        ),
      ]),
    );
  }

  Widget _deviceList() {
    if (loadingDevice) return const Center(child: CircularProgressIndicator());
    if (!devicePermission) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.contacts_outlined, size: 52),
            const SizedBox(height: 12),
            const Text(
              'Allow contact access to search and import people from this phone.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loadDevice,
              icon: const Icon(Icons.lock_open),
              label: const Text('Allow contacts'),
            ),
          ]),
        ),
      );
    }
    final items = _filteredDevice;
    return RefreshIndicator(
      onRefresh: _loadDevice,
      child: ListView.separated(
        itemCount: items.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final c = items[i];
          final displayName = (c.displayName ?? '').trim();
          final phoneNumber = c.phones.isNotEmpty ? c.phones.first.number : '';
          return ListTile(
            leading: CircleAvatar(child: Text(_initials(displayName))),
            title: Text(displayName.isEmpty ? phoneNumber : displayName),
            subtitle: Text(phoneNumber.isEmpty ? 'No phone number' : phoneNumber),
            trailing: phoneNumber.isEmpty
                ? null
                : FilledButton.tonalIcon(
                    onPressed: () => _import(c, phoneNumber),
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('Import'),
                  ),
          );
        },
      ),
    );
  }

  Future<void> _showServerContact(Map<String, dynamic> c) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircleAvatar(radius: 30, child: Text(_initials(_serverName(c)))),
            const SizedBox(height: 10),
            Text(_serverName(c), style: Theme.of(ctx).textTheme.titleLarge),
            Text(c['phone_number']?.toString() ?? ''),
            const SizedBox(height: 18),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              FilledButton.icon(
                onPressed: () { Navigator.pop(ctx); _callServerContact(c); },
                icon: const Icon(Icons.phone),
                label: const Text('Call'),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                onPressed: () { Navigator.pop(ctx); _deleteServerContact(c); },
                icon: const Icon(Icons.person_remove_outlined),
                label: const Text('Delete'),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

class EnhancedDialerScreen extends StatefulWidget {
  const EnhancedDialerScreen({super.key, required this.repo, required this.calls});
  final DataRepository repo;
  final CallingService calls;

  @override
  State<EnhancedDialerScreen> createState() => _EnhancedDialerScreenState();
}

class _EnhancedDialerScreenState extends State<EnhancedDialerScreen> {
  final number = TextEditingController();
  final keys = const ['1', '2', '3', '4', '5', '6', '7', '8', '9', '*', '0', '#'];
  List<Map<String, dynamic>> serverMatches = [];
  List<Contact> deviceContacts = [];
  bool busy = false;
  Timer? debounce;

  @override
  void initState() {
    super.initState();
    _loadDeviceSilently();
  }

  @override
  void dispose() {
    number.dispose();
    debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadDeviceSilently() async {
    try {
      final permission = await FlutterContacts.permissions.request(PermissionType.read);
      if (permission == PermissionStatus.granted) {
        deviceContacts = await FlutterContacts.getAll(properties: _contactProperties);
        if (mounted) setState(() {});
      }
    } catch (_) {}
  }

  void _changed() {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 220), () async {
      final q = number.text.trim();
      if (q.isEmpty) {
        if (mounted) setState(() => serverMatches = []);
        return;
      }
      try {
        final values = await widget.repo.contacts(search: q);
        if (mounted) setState(() => serverMatches = values.take(6).toList());
      } catch (_) {}
    });
    setState(() {});
  }

  List<Contact> get _deviceMatches {
    final q = number.text.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return deviceContacts
        .where((c) =>
            (c.displayName ?? '').toLowerCase().contains(q) ||
            c.phones.any((p) => p.number.toLowerCase().contains(q)))
        .take(5)
        .toList();
  }

  Future<void> _dial([Map<String, dynamic>? known]) async {
    final raw = number.text.trim();
    if (raw.isEmpty || busy) return;
    setState(() => busy = true);
    try {
      Map<String, dynamic>? contact = known;
      if (contact == null) {
        final contacts = await widget.repo.contacts(search: raw);
        final normalized = _digits(raw);
        for (final item in contacts) {
          if (_digits((item['phone_number'] ?? '').toString()) == normalized) {
            contact = item;
            break;
          }
        }
      }
      if (contact == null) {
        if (!mounted) return;
        final create = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Create Whatomate contact?'),
            content: Text(
              'No exact Whatomate contact matches $raw. Create it before requesting call permission?',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
            ],
          ),
        );
        if (create != true) return;
        contact = await widget.repo.createContact(raw);
      }
      final resolvedContact = contact;
      final accounts = await widget.repo.accounts();
      final account = (resolvedContact['whatsapp_account'] ??
              (accounts.isNotEmpty ? accounts.first['name'] : null))
          ?.toString();
      if (account == null || account.isEmpty) {
        throw ApiException('No WhatsApp account configured');
      }
      final id = resolvedContact['id']?.toString();
      if (id == null || id.isEmpty) throw ApiException('Contact ID is missing');
      final permission = await widget.calls.callPermission(id, account);
      final status = permission['status']?.toString();
      if (status != 'accepted' && status != 'temporary' && status != 'permanent') {
        await widget.calls.requestPermission(id, account);
        if (mounted) {
          _snack('Call permission request sent. Call after the contact accepts.');
        }
        return;
      }
      await widget.calls.makeOutgoingCall(
        contactId: id,
        contactName: _serverName(resolvedContact),
        whatsappAccount: account,
        phone: (resolvedContact['phone_number'] ?? raw).toString(),
      );
    } catch (e) {
      if (mounted) _snack(widget.repo.api.normalize(e).message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _selectDevice(Contact c) {
    if (c.phones.isEmpty) return;
    number.text = c.phones.first.number;
    _changed();
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    final device = _deviceMatches;
    return Scaffold(
      appBar: AppBar(title: const Text('Dialer')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(children: [
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: TextField(
                  controller: number,
                  keyboardType: TextInputType.phone,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                  onChanged: (_) => _changed(),
                  decoration: const InputDecoration(
                    hintText: 'Name or number',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              if (serverMatches.isNotEmpty || device.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 170),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final c in serverMatches)
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.cloud_outlined),
                          title: Text(_serverName(c)),
                          subtitle: Text(c['phone_number']?.toString() ?? ''),
                          onTap: () {
                            number.text = c['phone_number']?.toString() ?? '';
                            setState(() {});
                          },
                          trailing: IconButton(
                            onPressed: () => _dial(c),
                            icon: const Icon(Icons.call_outlined),
                          ),
                        ),
                      for (final c in device)
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.phone_android_outlined),
                          title: Text((c.displayName ?? '').isEmpty
                              ? (c.phones.isEmpty ? 'Phone contact' : c.phones.first.number)
                              : c.displayName!),
                          subtitle: Text(c.phones.isEmpty ? '' : c.phones.first.number),
                          onTap: () => _selectDevice(c),
                        ),
                    ],
                  ),
                ),
              const Spacer(),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                padding: const EdgeInsets.symmetric(horizontal: 54),
                children: keys
                    .map(
                      (key) => FilledButton.tonal(
                        onPressed: () {
                          number.text += key;
                          _changed();
                        },
                        style: FilledButton.styleFrom(shape: const CircleBorder()),
                        child: Text(key, style: const TextStyle(fontSize: 24)),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                IconButton(
                  onPressed: number.text.isEmpty
                      ? null
                      : () {
                          number.text = number.text.substring(0, number.text.length - 1);
                          _changed();
                        },
                  icon: const Icon(Icons.backspace_outlined),
                ),
                const SizedBox(width: 28),
                IconButton.filled(
                  onPressed: busy ? null : () => _dial(),
                  icon: busy
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.call),
                  iconSize: 30,
                  padding: const EdgeInsets.all(18),
                ),
                const SizedBox(width: 64),
              ]),
              const Spacer(),
            ]),
          ),
        ),
      ),
    );
  }
}

String _serverName(Map<String, dynamic> c) =>
    (c['profile_name'] ?? c['name'] ?? c['phone_number'] ?? 'Unknown').toString();

String _initials(String text) {
  final parts = text.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  return parts.take(2).map((p) => p[0].toUpperCase()).join();
}

String _digits(String text) => text.replaceAll(RegExp(r'\D'), '');
