import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/api_client.dart';
import '../core/calling.dart';
import '../core/data_repository.dart';
import '../core/realtime.dart';
import '../core/session.dart';

class WhatomateRoot extends StatefulWidget {
  const WhatomateRoot({
    super.key,
    required this.api,
    required this.session,
    required this.realtime,
    required this.calls,
  });
  final WhatomateApi api;
  final SessionController session;
  final RealtimeService realtime;
  final CallingService calls;

  @override
  State<WhatomateRoot> createState() => _WhatomateRootState();
}

class _WhatomateRootState extends State<WhatomateRoot> {
  @override
  void initState() {
    super.initState();
    widget.session.addListener(_sessionChanged);
  }

  Future<void> _sessionChanged() async {
    if (widget.session.authenticated && !widget.realtime.connected) {
      await widget.realtime.connect();
    } else if (!widget.session.authenticated && widget.realtime.connected) {
      await widget.realtime.disconnect();
    }
  }

  @override
  void dispose() {
    widget.session.removeListener(_sessionChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Whatomate',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff0738f9)),
        scaffoldBackgroundColor: Colors.white,
        inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff0738f9),
          brightness: Brightness.dark,
        ),
      ),
      home: AnimatedBuilder(
        animation: widget.session,
        builder: (context, _) {
          if (widget.session.booting) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          if (!widget.session.authenticated) {
            return LoginScreen(session: widget.session);
          }
          return MainShell(
            api: widget.api,
            session: widget.session,
            realtime: widget.realtime,
            calls: widget.calls,
          );
        },
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.session});
  final SessionController session;
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final server = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  bool obscure = true;

  @override
  void initState() {
    super.initState();
    widget.session.api.savedServer.then((value) {
      if (mounted && value != null) setState(() => server.text = value);
    });
  }

  @override
  void dispose() {
    server.dispose(); email.dispose(); password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    try {
      await widget.session.login(server.text, email.text, password.text);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.session.error ?? 'Login failed')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Icon(Icons.forum_outlined, size: 54),
                const SizedBox(height: 18),
                Text('Whatomate', textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                const Text('Connect to your Whatomate server', textAlign: TextAlign.center),
                const SizedBox(height: 30),
                TextField(controller: server, keyboardType: TextInputType.url,
                  decoration: const InputDecoration(labelText: 'Server URL', hintText: 'https://whatomate.example.com')),
                const SizedBox(height: 12),
                TextField(controller: email, keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email')),
                const SizedBox(height: 12),
                TextField(controller: password, obscureText: obscure,
                  onSubmitted: (_) => submit(),
                  decoration: InputDecoration(labelText: 'Password', suffixIcon: IconButton(
                    icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => obscure = !obscure),
                  ))),
                const SizedBox(height: 18),
                FilledButton.icon(onPressed: widget.session.busy ? null : submit,
                  icon: widget.session.busy ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.login),
                  label: const Text('Sign in')),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.api, required this.session, required this.realtime, required this.calls});
  final WhatomateApi api;
  final SessionController session;
  final RealtimeService realtime;
  final CallingService calls;
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int index = 0;
  late final DataRepository repo = DataRepository(widget.api);

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      ConversationsScreen(repo: repo, realtime: widget.realtime, calls: widget.calls),
      ContactsScreen(repo: repo, calls: widget.calls),
      DialerScreen(repo: repo, calls: widget.calls),
      CallsScreen(repo: repo, calls: widget.calls, realtime: widget.realtime),
      MoreScreen(repo: repo, session: widget.session, api: widget.api),
    ];
    return AnimatedBuilder(
      animation: Listenable.merge([widget.calls, widget.realtime]),
      builder: (context, _) => Scaffold(
        body: Stack(children: [
          IndexedStack(index: index, children: pages),
          if (widget.calls.state.active)
            Positioned(left: 10, right: 10, bottom: 8,
              child: ActiveCallBar(calls: widget.calls)),
        ]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (value) => setState(() => index = value),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: 'Chats'),
            NavigationDestination(icon: Icon(Icons.contacts_outlined), selectedIcon: Icon(Icons.contacts), label: 'Contacts'),
            NavigationDestination(icon: Icon(Icons.dialpad_outlined), selectedIcon: Icon(Icons.dialpad), label: 'Dialer'),
            NavigationDestination(icon: Icon(Icons.phone_outlined), selectedIcon: Icon(Icons.phone), label: 'Calls'),
            NavigationDestination(icon: Icon(Icons.grid_view_outlined), selectedIcon: Icon(Icons.grid_view), label: 'More'),
          ],
        ),
      ),
    );
  }
}

class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key, required this.repo, required this.realtime, required this.calls});
  final DataRepository repo; final RealtimeService realtime; final CallingService calls;
  @override State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  final search = TextEditingController();
  List<Map<String, dynamic>> contacts = [];
  bool loading = true;
  Timer? debounce;
  StreamSubscription<RealtimeEvent>? ws;

  @override void initState() { super.initState(); load(); ws = widget.realtime.events.listen((e) {
    if (e.type == 'new_message' || e.type.startsWith('agent_transfer')) load(silent: true);
  }); }
  @override void dispose() { search.dispose(); debounce?.cancel(); ws?.cancel(); super.dispose(); }

  Future<void> load({bool silent = false}) async {
    if (!silent) setState(() => loading = true);
    try { final result = await widget.repo.contacts(search: search.text); if (mounted) setState(() => contacts = result); }
    catch (e) { if (mounted) _snack(context, widget.repo.api.normalize(e).message); }
    finally { if (mounted) setState(() => loading = false); }
  }

  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Conversations'), actions: [IconButton(onPressed: load, icon: const Icon(Icons.refresh))]),
    body: Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 10), child: TextField(
        controller: search, decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search name or phone'),
        onChanged: (_) { debounce?.cancel(); debounce = Timer(const Duration(milliseconds: 350), load); },
      )),
      Expanded(child: loading ? const Center(child: CircularProgressIndicator()) : RefreshIndicator(
        onRefresh: load,
        child: contacts.isEmpty ? ListView(children: const [SizedBox(height: 180), Center(child: Text('No conversations'))]) : ListView.separated(
          itemCount: contacts.length, separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final c = contacts[i]; final unread = _int(c['unread_count']);
            return ListTile(
              leading: CircleAvatar(child: Text(_initial(c))),
              title: Text(_contactName(c), maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(c['phone_number']?.toString() ?? '', maxLines: 1),
              trailing: unread > 0 ? Badge(label: Text('$unread')) : const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(
                repo: widget.repo, realtime: widget.realtime, calls: widget.calls, contact: c))),
              onLongPress: () async {
                final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
                  title: const Text('Clear conversation?'),
                  content: Text('Clear messages with ${_contactName(c)}? The contact, call permissions, notes, tags and call history will be kept.'),
                  actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear'))],
                ));
                if (ok == true) {
                  try { await widget.repo.deleteConversation(c['id'].toString()); await load(silent: true); }
                  catch (e) { if (context.mounted) _snack(context, widget.repo.api.normalize(e).message); }
                }
              },
            );
          },
        ),
      )),
    ]),
  );
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.repo, required this.realtime, required this.calls, required this.contact});
  final DataRepository repo; final RealtimeService realtime; final CallingService calls; final Map<String, dynamic> contact;
  @override State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final input = TextEditingController(); final scroll = ScrollController();
  List<Map<String, dynamic>> messages = []; bool loading = true; bool sending = false;
  StreamSubscription<RealtimeEvent>? ws;
  Map<String, dynamic> callPermission = const {};
  bool permissionLoading = false;
  String get id => widget.contact['id'].toString();
  String? get account { final value = widget.contact['whatsapp_account']?.toString(); return value == null || value.isEmpty ? null : value; }
  bool get serviceWindowOpen {
    final explicit = widget.contact['service_window_open'];
    if (explicit is bool) return explicit;
    final last = DateTime.tryParse(widget.contact['last_inbound_at']?.toString() ?? '');
    if (last == null) return false;
    return DateTime.now().difference(last.toLocal()) < const Duration(hours: 24);
  }
  String get permissionLabel {
    final status = callPermission['status']?.toString() ?? '';
    if (status == 'accepted' || status == 'temporary' || status == 'permanent') return 'Active';
    if (status == 'pending') return 'Pending';
    if (status == 'declined') return 'Declined';
    return 'Not requested';
  }

  @override void initState() { super.initState(); widget.realtime.setCurrentContact(id); load(); ws = widget.realtime.events.listen(_event); }
  @override void dispose() { widget.realtime.setCurrentContact(null); ws?.cancel(); input.dispose(); scroll.dispose(); super.dispose(); }

  void _event(RealtimeEvent e) {
    if ((e.type == 'new_message' || e.type == 'status_update' || e.type == 'reaction_update') &&
        (e.payload['contact_id']?.toString() == id || e.payload['message']?['contact_id']?.toString() == id)) load(silent: true);
  }

  Future<void> load({bool silent = false}) async {
    if (!silent) setState(() => loading = true);
    try {
      final fresh = await widget.repo.contact(id);
      if (fresh != null) widget.contact.addAll(fresh);
      final data = await widget.repo.messages(id); messages = data;
      await _refreshCallPermission();
      await widget.repo.markRead(id).catchError((_) {});
      if (mounted) setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) => _bottom());
    } catch (e) { if (mounted) _snack(context, widget.repo.api.normalize(e).message); }
    finally { if (mounted) setState(() => loading = false); }
  }

  Future<void> send() async {
    final text = input.text.trim(); if (text.isEmpty || sending) return;
    if (!serviceWindowOpen) { _snack(context, '24-hour messaging window is closed. Send an approved template instead.'); await _showTemplates(); return; }
    setState(() => sending = true); input.clear();
    try { messages.add(await widget.repo.sendText(id, text, account: widget.contact['whatsapp_account']?.toString())); setState(() {}); _bottom(); }
    catch (e) { if (mounted) { input.text = text; _snack(context, widget.repo.api.normalize(e).message); } }
    finally { if (mounted) setState(() => sending = false); }
  }

  void _bottom() { if (scroll.hasClients) scroll.animateTo(scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 220), curve: Curves.easeOut); }

  Future<void> _refreshCallPermission() async {
    final a = account; if (a == null) { callPermission = const {}; return; }
    try { callPermission = await widget.calls.callPermission(id, a); } catch (_) { callPermission = const {}; }
  }

  Future<void> _requestCallPermission(String method) async {
    final a = account; if (a == null || permissionLoading) return;
    setState(() => permissionLoading = true);
    try {
      await widget.calls.requestPermission(id, a, method: method);
      callPermission = const {'status': 'pending'};
      if (mounted) { setState(() {}); _snack(context, method == 'template' ? 'Call request template sent' : 'Call permission request sent'); }
    } catch (e) { if (mounted) _snack(context, widget.repo.api.normalize(e).message); }
    finally { if (mounted) setState(() => permissionLoading = false); }
  }

  Future<void> _clearConversation() async {
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('Clear conversation?'),
      content: const Text('Messages will be cleared. Contact details, call permissions, tags, notes, assignments and call history will be kept.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear'))],
    ));
    if (ok != true) return;
    try { await widget.repo.deleteConversation(id); if (mounted) setState(() => messages = []); }
    catch (e) { if (mounted) _snack(context, widget.repo.api.normalize(e).message); }
  }

  Future<void> _showTemplates() async {
    final a = account;
    try {
      final all = await widget.repo.templates(account: a);
      final approved = all.where((t) {
        final status = t['status']?.toString().toUpperCase();
        return status == null || status.isEmpty || status == 'APPROVED';
      }).toList();
      if (!mounted) return;
      if (approved.isEmpty) { _snack(context, 'No approved templates are available'); return; }
      final selected = await showDialog<Map<String, dynamic>>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Send approved template'),
        content: SizedBox(width: 420, height: 420, child: ListView.separated(
          itemCount: approved.length, separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) { final t = approved[i]; return ListTile(title: Text((t['name'] ?? t['template_name'] ?? 'Template').toString()), subtitle: Text((t['category'] ?? t['language'] ?? '').toString()), onTap: () => Navigator.pop(ctx, t)); },
        )),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel'))],
      ));
      if (selected == null) return;
      final name = (selected['name'] ?? selected['template_name'])?.toString();
      if (name == null || name.isEmpty) throw ApiException('Template name is missing');
      await widget.repo.sendTemplate(id, name, account: a);
      if (mounted) { _snack(context, 'Template sent'); await load(silent: true); }
    } catch (e) { if (mounted) _snack(context, widget.repo.api.normalize(e).message); }
  }

  Future<void> call() async {
    final account = widget.contact['whatsapp_account']?.toString();
    if (account == null || account.isEmpty) { _snack(context, 'No WhatsApp account is associated with this contact'); return; }
    try {
      final permission = await widget.calls.callPermission(id, account);
      final status = permission['status']?.toString();
      if (status != 'accepted' && status != 'temporary' && status != 'permanent') {
        if (!mounted) return;
        final request = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
          title: const Text('Call permission required'),
          content: const Text('Send a WhatsApp call-permission request first?'),
          actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Send request'))],
        ));
        if (request == true) { await _requestCallPermission('interactive'); }
        return;
      }
      await widget.calls.makeOutgoingCall(contactId: id, contactName: _contactName(widget.contact), whatsappAccount: account, phone: widget.contact['phone_number']?.toString() ?? '');
    } catch (e) { if (mounted) _snack(context, widget.repo.api.normalize(e).message); }
  }

  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(_contactName(widget.contact), style: const TextStyle(fontSize: 17)), Text(widget.contact['phone_number']?.toString() ?? '', style: Theme.of(context).textTheme.bodySmall)]),
      actions: [
        IconButton(onPressed: call, icon: const Icon(Icons.phone_outlined)),
        PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'permission') _requestCallPermission('interactive');
            if (value == 'permission_template') _requestCallPermission('template');
            if (value == 'template') _showTemplates();
            if (value == 'clear') _clearConversation();
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'permission', child: Text('Request call permission')),
            PopupMenuItem(value: 'permission_template', child: Text('Send call request template')),
            PopupMenuItem(value: 'template', child: Text('Send WhatsApp template')),
            PopupMenuDivider(),
            PopupMenuItem(value: 'clear', child: Text('Clear conversation')),
          ],
        ),
        IconButton(onPressed: () => _showContactInfo(context, widget.repo, widget.contact), icon: const Icon(Icons.info_outline)),
      ]),
    body: Column(children: [
      Material(color: Theme.of(context).colorScheme.surfaceContainerLow, child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(children: [
          Icon(permissionLabel == 'Active' ? Icons.verified_user_outlined : Icons.shield_outlined, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text('Call permission: $permissionLabel', style: Theme.of(context).textTheme.bodySmall)),
          if (permissionLabel != 'Active') TextButton(onPressed: permissionLoading ? null : () => _requestCallPermission('interactive'), child: const Text('Request')),
        ]),
      )),
      if (!serviceWindowOpen) Material(color: Theme.of(context).colorScheme.errorContainer, child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(children: [
          const Icon(Icons.schedule, size: 18), const SizedBox(width: 8),
          const Expanded(child: Text('24-hour messaging window closed. Use an approved template.')),
          TextButton(onPressed: _showTemplates, child: const Text('Templates')),
        ]),
      )),
      Expanded(child: loading ? const Center(child: CircularProgressIndicator()) : ListView.builder(
        controller: scroll, padding: const EdgeInsets.all(12), itemCount: messages.length,
        itemBuilder: (_, i) => MessageBubble(message: messages[i]),
      )),
      SafeArea(top: false, child: Padding(padding: const EdgeInsets.fromLTRB(10, 6, 10, 10), child: Row(children: [
        Expanded(child: TextField(controller: input, enabled: serviceWindowOpen, minLines: 1, maxLines: 5, onSubmitted: (_) => send(), decoration: InputDecoration(hintText: serviceWindowOpen ? 'Message' : 'Use an approved template', isDense: true))),
        const SizedBox(width: 8),
        if (!serviceWindowOpen) IconButton.filled(onPressed: _showTemplates, icon: const Icon(Icons.description_outlined))
        else IconButton.filled(onPressed: sending ? null : send, icon: sending ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send)),
      ]))),
    ]),
  );
}

class MessageBubble extends StatelessWidget {
  const MessageBubble({super.key, required this.message}); final Map<String, dynamic> message;
  @override Widget build(BuildContext context) {
    final outgoing = message['direction']?.toString() == 'outgoing';
    final content = message['content'];
    String text = '';
    if (content is Map) text = (content['body'] ?? content['text'] ?? '').toString(); else text = content?.toString() ?? '';
    if (text.isEmpty) text = '[${message['message_type'] ?? 'message'}]';
    final time = _date(message['created_at']);
    return Align(alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft, child: Container(
      constraints: const BoxConstraints(maxWidth: 330), margin: const EdgeInsets.symmetric(vertical: 4), padding: const EdgeInsets.fromLTRB(12, 9, 10, 6),
      decoration: BoxDecoration(color: outgoing ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Align(alignment: Alignment.centerLeft, child: Text(text)), const SizedBox(height: 3), Row(mainAxisSize: MainAxisSize.min, children: [Text(time, style: Theme.of(context).textTheme.labelSmall), if (outgoing) ...[const SizedBox(width: 4), Icon(message['status'] == 'read' ? Icons.done_all : Icons.done, size: 14)]])]),
    ));
  }
}

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key, required this.repo, required this.calls}); final DataRepository repo; final CallingService calls;
  @override State<ContactsScreen> createState() => _ContactsScreenState();
}
class _ContactsScreenState extends State<ContactsScreen> {
  final search = TextEditingController(); List<Map<String,dynamic>> items=[]; bool loading=true; Timer? timer;
  @override void initState(){super.initState();load();}
  @override void dispose(){search.dispose();timer?.cancel();super.dispose();}
  Future<void> load() async {setState(()=>loading=true); try{items=await widget.repo.contacts(search: search.text);}catch(e){if(mounted)_snack(context,widget.repo.api.normalize(e).message);}finally{if(mounted)setState(()=>loading=false);}}
  Future<void> add() async {final phone=TextEditingController(), name=TextEditingController(); final ok=await showDialog<bool>(context:context,builder:(_)=>AlertDialog(title:const Text('New contact'),content:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:name,decoration:const InputDecoration(labelText:'Name')),const SizedBox(height:10),TextField(controller:phone,keyboardType:TextInputType.phone,decoration:const InputDecoration(labelText:'Phone number'))]),actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('Create'))]));if(ok==true){try{await widget.repo.createContact(phone.text,name:name.text);await load();}catch(e){if(mounted)_snack(context,widget.repo.api.normalize(e).message);}}}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Contacts'),actions:[IconButton(onPressed:add,icon:const Icon(Icons.person_add_alt_1)),IconButton(onPressed:load,icon:const Icon(Icons.refresh))]),body:Column(children:[Padding(padding:const EdgeInsets.all(12),child:TextField(controller:search,onChanged:(_){timer?.cancel();timer=Timer(const Duration(milliseconds:350),load);},decoration:const InputDecoration(prefixIcon:Icon(Icons.search),hintText:'Search contacts'))),Expanded(child:loading?const Center(child:CircularProgressIndicator()):ListView.separated(itemCount:items.length,separatorBuilder:(_,__)=>const Divider(height:1),itemBuilder:(context,i){final c=items[i];return ListTile(leading:CircleAvatar(child:Text(_initial(c))),title:Text(_contactName(c)),subtitle:Text(c['phone_number']?.toString()??''),onTap:()=>_showContactInfo(context,widget.repo,c));}))]));
}

class DialerScreen extends StatefulWidget {
  const DialerScreen({super.key, required this.repo, required this.calls}); final DataRepository repo; final CallingService calls;
  @override State<DialerScreen> createState()=>_DialerScreenState();
}
class _DialerScreenState extends State<DialerScreen>{
  String number=''; bool busy=false;
  final keys=const ['1','2','3','4','5','6','7','8','9','*','0','#'];
  Future<void> dial()async{if(number.isEmpty||busy)return;setState(()=>busy=true);try{final contacts=await widget.repo.contacts(search:number);Map<String,dynamic>? c;for(final item in contacts){final p=(item['phone_number']??'').toString().replaceAll(RegExp(r'\D'),'');if(p==number.replaceAll(RegExp(r'\D'),'')){c=item;break;}}c??=contacts.isNotEmpty?contacts.first:null;if(c==null){if(!mounted)return;final create=await showDialog<bool>(context:context,builder:(_)=>AlertDialog(title:const Text('Unknown number'),content:Text('Create $number as a Whatomate contact?'),actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('Create'))]));if(create!=true)return;c=await widget.repo.createContact(number);}final accounts=await widget.repo.accounts();final account=(c['whatsapp_account']??(accounts.isNotEmpty?accounts.first['name']:null))?.toString();if(account==null||account.isEmpty)throw ApiException('No WhatsApp account configured');final permission=await widget.calls.callPermission(c['id'].toString(),account);final status=permission['status']?.toString();if(status!='accepted'&&status!='temporary'&&status!='permanent'){await widget.calls.requestPermission(c['id'].toString(),account);if(mounted)_snack(context,'Call permission request sent. Call after the contact accepts.');return;}await widget.calls.makeOutgoingCall(contactId:c['id'].toString(),contactName:_contactName(c),whatsappAccount:account,phone:number);}catch(e){if(mounted)_snack(context,widget.repo.api.normalize(e).message);}finally{if(mounted)setState(()=>busy=false);}}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Dialer')),body:SafeArea(child:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:420),child:Column(children:[const Spacer(),Text(number.isEmpty?'Enter a number':number,style:Theme.of(context).textTheme.headlineMedium),const SizedBox(height:24),GridView.count(crossAxisCount:3,shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),mainAxisSpacing:8,crossAxisSpacing:8,padding:const EdgeInsets.symmetric(horizontal:38),children:keys.map((k)=>FilledButton.tonal(onPressed:()=>setState(()=>number+=k),style:FilledButton.styleFrom(shape:const CircleBorder()),child:Text(k,style:const TextStyle(fontSize:24)))).toList()),const SizedBox(height:18),Row(mainAxisAlignment:MainAxisAlignment.center,children:[IconButton(onPressed:number.isEmpty?null:()=>setState(()=>number=number.substring(0,number.length-1)),icon:const Icon(Icons.backspace_outlined)),const SizedBox(width:24),IconButton.filled(onPressed:busy?null:dial,icon:busy?const SizedBox.square(dimension:20,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.call),iconSize:30,padding:const EdgeInsets.all(18)),const SizedBox(width:60)]),const Spacer()]))) ));
}

class CallsScreen extends StatefulWidget {
  const CallsScreen({super.key, required this.repo, required this.calls, required this.realtime}); final DataRepository repo; final CallingService calls; final RealtimeService realtime;
  @override State<CallsScreen> createState()=>_CallsScreenState();
}
class _CallsScreenState extends State<CallsScreen>{
  List<Map<String,dynamic>> logs=[],waiting=[];bool loading=true;StreamSubscription<RealtimeEvent>? ws;
  @override void initState(){super.initState();load();ws=widget.realtime.events.listen((e){if(e.type.startsWith('call_')||e.type.startsWith('outgoing_call_'))load(silent:true);});}
  @override void dispose(){ws?.cancel();super.dispose();}
  Future<void> load({bool silent=false})async{if(!silent)setState(()=>loading=true);try{final r=await Future.wait([widget.repo.callLogs(),widget.repo.waitingCallTransfers()]);logs=r[0];waiting=r[1];}catch(e){if(mounted)_snack(context,widget.repo.api.normalize(e).message);}finally{if(mounted)setState(()=>loading=false);}}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Calls'),actions:[IconButton(tooltip:'Clear finished history',onPressed:_clearHistory,icon:const Icon(Icons.delete_sweep_outlined)),IconButton(onPressed:load,icon:const Icon(Icons.refresh))]),body:loading?const Center(child:CircularProgressIndicator()):RefreshIndicator(onRefresh:load,child:ListView(children:[if(waiting.isNotEmpty)...[const _SectionTitle('Incoming / waiting'),...waiting.map((t)=>ListTile(leading:const CircleAvatar(child:Icon(Icons.phone_in_talk)),title:Text((t['contact']?['profile_name']??t['caller_phone']??'Incoming call').toString()),subtitle:Text('Waiting • ${(t['caller_phone']??'').toString()}'),trailing:Wrap(spacing:6,children:[FilledButton(onPressed:()=>_accept(t),child:const Text('Answer')),FilledButton.tonal(onPressed:()=>_decline(t),child:const Text('Decline'))]))),const Divider()],const _SectionTitle('Call history'),if(logs.isEmpty)const Padding(padding:EdgeInsets.all(32),child:Center(child:Text('No call logs'))),...logs.map((log)=>ListTile(leading:Icon(_callIcon(log)),title:Text((log['contact']?['profile_name']??log['caller_phone']??'Unknown').toString()),subtitle:Text('${log['direction']??''} • ${log['status']??''} • ${_duration(_int(log['duration']))}'),trailing:Text(_date(log['started_at']??log['created_at'])),onTap:()=>_jsonDialog(context,'Call details',log)))])));
  Future<void> _accept(Map<String,dynamic> t)async{try{await widget.calls.acceptTransfer(t);}catch(e){if(mounted)_snack(context,widget.repo.api.normalize(e).message);}}
  Future<void> _decline(Map<String,dynamic> t)async{try{await widget.calls.declineTransfer(t);await load(silent:true);if(mounted)_snack(context,'Declined — routing to the next available agent');}catch(e){if(mounted)_snack(context,widget.repo.api.normalize(e).message);}}
  Future<void> _clearHistory()async{
    final ok=await showDialog<bool>(context:context,builder:(_)=>AlertDialog(title:const Text('Clear call history?'),content:const Text('Only finished, missed, rejected and failed calls will be cleared. Active calls are never deleted.'),actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('Clear'))]));
    if(ok!=true)return;try{final n=await widget.repo.clearCallHistory();await load(silent:true);if(mounted)_snack(context,'Cleared $n finished call record(s)');}catch(e){if(mounted)_snack(context,widget.repo.api.normalize(e).message);}
  }
}

class ActiveCallBar extends StatelessWidget {
  const ActiveCallBar({super.key, required this.calls}); final CallingService calls;
  @override Widget build(BuildContext context){final s=calls.state;return Material(elevation:8,borderRadius:BorderRadius.circular(18),color:Theme.of(context).colorScheme.inverseSurface,child:Padding(padding:const EdgeInsets.symmetric(horizontal:12,vertical:8),child:Row(children:[CircleAvatar(child:const Icon(Icons.phone_in_talk)),const SizedBox(width:10),Expanded(child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[Text(s.contactName.isEmpty?s.phone:s.contactName,style:TextStyle(color:Theme.of(context).colorScheme.onInverseSurface,fontWeight:FontWeight.w600)),Text('${s.status} • ${_duration(s.seconds)}',style:TextStyle(color:Theme.of(context).colorScheme.onInverseSurface.withValues(alpha:.75)))])),IconButton(onPressed:calls.toggleMute,icon:Icon(s.muted?Icons.mic_off:Icons.mic),color:Theme.of(context).colorScheme.onInverseSurface),IconButton(onPressed:()=>calls.setSpeaker(true),icon:const Icon(Icons.volume_up),color:Theme.of(context).colorScheme.onInverseSurface),IconButton.filled(style:IconButton.styleFrom(backgroundColor:Colors.red),onPressed:calls.hangup,icon:const Icon(Icons.call_end))])));}
}

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key, required this.repo, required this.session, required this.api}); final DataRepository repo; final SessionController session; final WhatomateApi api;
  static const modules=<ModuleDef>[
    ModuleDef('Dashboard','/analytics/dashboard',[],Icons.dashboard_outlined,'analytics',single:true),
    ModuleDef('Templates','/templates',['templates'],Icons.description_outlined,'templates'),
    ModuleDef('WhatsApp Flows','/flows',['flows'],Icons.account_tree_outlined,'flows.whatsapp'),
    ModuleDef('Campaigns','/campaigns',['campaigns'],Icons.campaign_outlined,'campaigns'),
    ModuleDef('Chatbot','/chatbot/settings',[],Icons.smart_toy_outlined,'settings.chatbot',single:true),
    ModuleDef('Keywords','/chatbot/keywords',['keywords','rules'],Icons.key_outlined,'chatbot.keywords'),
    ModuleDef('Chatbot Flows','/chatbot/flows',['flows'],Icons.schema_outlined,'flows.chatbot'),
    ModuleDef('AI Contexts','/chatbot/ai-contexts',['ai_contexts','contexts'],Icons.psychology_outlined,'chatbot.ai'),
    ModuleDef('Agent Transfers','/chatbot/transfers',['transfers'],Icons.swap_horiz,'transfers'),
    ModuleDef('Agent Analytics','/analytics/agents',['agents','analytics'],Icons.analytics_outlined,'analytics.agents'),
    ModuleDef('Meta Insights','/analytics/meta',[],Icons.insights_outlined,'analytics',single:true),
    ModuleDef('Accounts','/accounts',['accounts'],Icons.business_outlined,'accounts'),
    ModuleDef('Canned responses','/canned-responses',['canned_responses'],Icons.quickreply_outlined,'canned_responses'),
    ModuleDef('Tags','/tags',['tags'],Icons.sell_outlined,'tags'),
    ModuleDef('Teams','/teams',['teams'],Icons.groups_outlined,'teams'),
    ModuleDef('Users','/users',['users'],Icons.people_outline,'users'),
    ModuleDef('Roles','/roles',['roles'],Icons.admin_panel_settings_outlined,'roles'),
    ModuleDef('API Keys','/api-keys',['api_keys'],Icons.vpn_key_outlined,'api_keys'),
    ModuleDef('Webhooks','/webhooks',['webhooks'],Icons.webhook_outlined,'webhooks'),
    ModuleDef('Custom Actions','/custom-actions',['custom_actions'],Icons.bolt_outlined,'custom_actions'),
    ModuleDef('Audit Logs','/audit-logs',['audit_logs','logs'],Icons.receipt_long_outlined,'audit_logs'),
    ModuleDef('IVR Flows','/ivr-flows',['ivr_flows'],Icons.account_tree,'ivr_flows'),
    ModuleDef('Call Transfers','/call-transfers',['call_transfers'],Icons.phone_forwarded_outlined,'call_transfers'),
    ModuleDef('Catalogs','/catalogs',['catalogs'],Icons.storefront_outlined,'catalogs'),
    ModuleDef('Organization Settings','/org/settings',[],Icons.settings_outlined,'settings.general',single:true),
  ];
  @override Widget build(BuildContext context){final visible=modules.where((m)=>session.hasPermission(m.permission)||m.permission=='').toList();return Scaffold(appBar:AppBar(title:const Text('More'),actions:[PopupMenuButton<String>(onSelected:(v)async{if(v=='logout')await session.logout();},itemBuilder:(_)=>const [PopupMenuItem(value:'logout',child:Text('Sign out'))])]),body:ListView(padding:const EdgeInsets.all(12),children:[Card(child:ListTile(leading:const CircleAvatar(child:Icon(Icons.person)),title:Text(session.displayName),subtitle:Text(session.user?['email']?.toString()??''),trailing:Switch(value:session.user?['is_available']!=false,onChanged:session.setAvailability))),const SizedBox(height:8),GridView.builder(shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),gridDelegate:const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent:220,childAspectRatio:1.55,crossAxisSpacing:8,mainAxisSpacing:8),itemCount:visible.length,itemBuilder:(context,i){final m=visible[i];return Card(child:InkWell(onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>GenericModuleScreen(repo:repo,module:m))),child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Icon(m.icon),const Spacer(),Text(m.title,style:const TextStyle(fontWeight:FontWeight.w600))]))));})]));}
}

class ModuleDef {const ModuleDef(this.title,this.path,this.keys,this.icon,this.permission,{this.single=false});final String title,path,permission;final List<String> keys;final IconData icon;final bool single;}

class GenericModuleScreen extends StatefulWidget {const GenericModuleScreen({super.key,required this.repo,required this.module});final DataRepository repo;final ModuleDef module;@override State<GenericModuleScreen> createState()=>_GenericModuleScreenState();}
class _GenericModuleScreenState extends State<GenericModuleScreen>{dynamic data;bool loading=true;String? error;@override void initState(){super.initState();load();}Future<void> load()async{setState((){loading=true;error=null;});try{if(widget.module.single){data=widget.repo.api.unwrap(await widget.repo.api.get(widget.module.path));}else{data=await widget.repo.genericList(widget.module.path,widget.module.keys);} }catch(e){error=widget.repo.api.normalize(e).message;}finally{if(mounted)setState(()=>loading=false);}}@override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(widget.module.title),actions:[IconButton(onPressed:load,icon:const Icon(Icons.refresh))]),body:loading?const Center(child:CircularProgressIndicator()):error!=null?Center(child:Padding(padding:const EdgeInsets.all(24),child:Text(error!))):widget.module.single?SingleChildScrollView(padding:const EdgeInsets.all(16),child:JsonCard(value:data)):ListView.separated(itemCount:(data as List).length,separatorBuilder:(_,__)=>const Divider(height:1),itemBuilder:(context,i){final item=(data as List<Map<String,dynamic>>)[i];return ListTile(title:Text(_bestTitle(item)),subtitle:Text(_bestSubtitle(item),maxLines:2,overflow:TextOverflow.ellipsis),trailing:const Icon(Icons.chevron_right),onTap:()=>_jsonDialog(context,widget.module.title,item));}));}

class JsonCard extends StatelessWidget{const JsonCard({super.key,required this.value});final dynamic value;@override Widget build(BuildContext context)=>SelectableText(const JsonEncoder.withIndent('  ').convert(value),style:const TextStyle(fontFamily:'monospace'));}
class _SectionTitle extends StatelessWidget{const _SectionTitle(this.text);final String text;@override Widget build(BuildContext context)=>Padding(padding:const EdgeInsets.fromLTRB(16,18,16,8),child:Text(text,style:Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight:FontWeight.w700)));}

Future<void> _showContactInfo(BuildContext context,DataRepository repo,Map<String,dynamic> c)async{final notes=await repo.notes(c['id'].toString()).catchError((_)=><Map<String,dynamic>>[]);if(!context.mounted)return;await showModalBottomSheet(context:context,isScrollControlled:true,builder:(ctx)=>DraggableScrollableSheet(expand:false,initialChildSize:.7,maxChildSize:.95,builder:(_,controller)=>ListView(controller:controller,padding:const EdgeInsets.all(18),children:[CircleAvatar(radius:32,child:Text(_initial(c))),const SizedBox(height:10),Center(child:Text(_contactName(c),style:Theme.of(ctx).textTheme.titleLarge)),Center(child:Text(c['phone_number']?.toString()??'')),const Divider(height:32),Text('Account: ${c['whatsapp_account']??'-'}'),Text('Status: ${c['status']??'-'}'),Text('Tags: ${(c['tags'] is List?(c['tags'] as List).join(', '):'-')}'),const SizedBox(height:18),Text('Conversation notes',style:Theme.of(ctx).textTheme.titleMedium),...notes.map((n)=>ListTile(contentPadding:EdgeInsets.zero,title:Text((n['content']??n['body']??'').toString()),subtitle:Text(_date(n['created_at']))))])));}

void _jsonDialog(BuildContext context,String title,dynamic value)=>showDialog(context:context,builder:(_)=>AlertDialog(title:Text(title),content:SizedBox(width:520,child:SingleChildScrollView(child:JsonCard(value:value))),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Close'))]));
void _snack(BuildContext context,String message)=>ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(message)));
String _contactName(Map<String,dynamic> c)=>(c['profile_name']??c['name']??c['phone_number']??'Unknown').toString();
String _initial(Map<String,dynamic> c){final v=_contactName(c).trim();return v.isEmpty?'?':v[0].toUpperCase();}
int _int(dynamic v)=>v is int?v:int.tryParse(v?.toString()??'')??0;
String _date(dynamic raw){if(raw==null)return'';final d=DateTime.tryParse(raw.toString())?.toLocal();return d==null?'':DateFormat('MMM d, HH:mm').format(d);}
String _duration(int seconds){final m=seconds~/60,s=seconds%60;return m>0?'${m}m ${s}s':'${s}s';}
IconData _callIcon(Map<String,dynamic> log){final status=log['status']?.toString(),direction=log['direction']?.toString();if(status=='missed'||status=='failed')return Icons.phone_missed;if(direction=='incoming')return Icons.call_received;return Icons.call_made;}
String _bestTitle(Map<String,dynamic> item)=>(item['name']??item['title']??item['full_name']??item['email']??item['phone_number']??item['event']??item['id']??'Item').toString();
String _bestSubtitle(Map<String,dynamic> item){for(final k in const ['description','status','email','phone_number','type','resource','created_at']){final v=item[k];if(v!=null&&v.toString().isNotEmpty)return v.toString();}return item['id']?.toString()??'';}
