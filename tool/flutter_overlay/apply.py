#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ROOT_DART = ROOT / "lib" / "ui" / "root.dart"
ADMIN_DART = ROOT / "lib" / "ui" / "admin_module_screen.dart"
CATALOG_DART = ROOT / "lib" / "ui" / "management_catalog.dart"

if not ROOT_DART.exists():
    raise SystemExit("lib/ui/root.dart is missing")

text = ROOT_DART.read_text(encoding="utf-8")

# Keep the hand-authored shell small while activating the richer feature
# surfaces already maintained in separate files. This patch is idempotent so
# local and CI builds behave the same way when it is run more than once.
import_anchor = "import '../core/session.dart';\n"
imports = (
    "import 'device_surfaces.dart';\n"
    "import 'enhanced_calls_screen.dart';\n"
    "import 'full_chat_screen.dart';\n"
    "import 'management_catalog.dart';\n"
)
if "import 'full_chat_screen.dart';" not in text:
    if import_anchor not in text:
        raise SystemExit("Could not locate root.dart import anchor")
    text = text.replace(import_anchor, import_anchor + imports, 1)
else:
    if "import 'device_surfaces.dart';" not in text:
        text = text.replace("import 'full_chat_screen.dart';\n", "import 'device_surfaces.dart';\nimport 'full_chat_screen.dart';\n", 1)
    if "import 'enhanced_calls_screen.dart';" not in text:
        text = text.replace("import 'full_chat_screen.dart';\n", "import 'enhanced_calls_screen.dart';\nimport 'full_chat_screen.dart';\n", 1)

old_chat = "onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(\n                repo: widget.repo, realtime: widget.realtime, calls: widget.calls, contact: c))),"
new_chat = "onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FullChatScreen(\n                repo: widget.repo, realtime: widget.realtime, calls: widget.calls, contact: c))),"
if old_chat in text:
    text = text.replace(old_chat, new_chat, 1)
elif "FullChatScreen(" not in text:
    raise SystemExit("Could not locate conversation chat route")

contacts_page = "      ContactsScreen(repo: repo, calls: widget.calls),\n"
if contacts_page in text:
    text = text.replace(contacts_page, "      EnhancedContactsScreen(repo: repo, calls: widget.calls),\n", 1)
elif "EnhancedContactsScreen(" not in text:
    raise SystemExit("Could not locate Contacts tab")

dialer_page = "      DialerScreen(repo: repo, calls: widget.calls),\n"
if dialer_page in text:
    text = text.replace(dialer_page, "      EnhancedDialerScreen(repo: repo, calls: widget.calls),\n", 1)
elif "EnhancedDialerScreen(" not in text:
    raise SystemExit("Could not locate Dialer tab")

calls_page = "      CallsScreen(repo: repo, calls: widget.calls, realtime: widget.realtime),\n"
if calls_page in text:
    text = text.replace(calls_page, "      EnhancedCallsScreen(repo: repo, calls: widget.calls, realtime: widget.realtime),\n", 1)
elif "EnhancedCallsScreen(" not in text:
    raise SystemExit("Could not locate Calls tab")

old_builder = "onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>GenericModuleScreen(repo:repo,module:m)))"
new_builder = "onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>buildManagementModuleScreen(repo:repo,title:m.title,path:m.path,keys:m.keys,icon:m.icon,single:m.single)))"
if old_builder in text:
    text = text.replace(old_builder, new_builder, 1)
elif "buildManagementModuleScreen(" not in text:
    raise SystemExit("Could not locate More module route")

# Expose server-backed surfaces that are part of the web/backend feature set
# but were not present in the original mobile More grid.
module_anchor = "    ModuleDef('Organization Settings','/org/settings',[],Icons.settings_outlined,'settings.general',single:true),\n"
extra_modules = (
    "    ModuleDef('Profile','/me',[],Icons.person_outline,'',single:true),\n"
    "    ModuleDef('SSO Settings','/settings/sso',[],Icons.login_outlined,'settings.sso',single:true),\n"
    "    ModuleDef('TTS Settings','/tts/settings',[],Icons.record_voice_over_outlined,'settings.general',single:true),\n"
    "    ModuleDef('Widgets','/widgets',['widgets'],Icons.widgets_outlined,'analytics'),\n"
)
if "ModuleDef('Profile'" not in text:
    if module_anchor not in text:
        raise SystemExit("Could not locate More module insertion anchor")
    text = text.replace(module_anchor, module_anchor + extra_modules, 1)

ROOT_DART.write_text(text, encoding="utf-8")

# Related resources often have their own `id`. Preserve the parent ID under a
# distinct token so /campaigns/{parent_id}/recipients/{id} and similar routes
# never accidentally substitute the child ID into the parent slot.
if ADMIN_DART.exists():
    admin = ADMIN_DART.read_text(encoding="utf-8")
    admin = admin.replace(
        "final values = {...widget.parent, ...?item};",
        "final values = {'parent_id': widget.parent['id'], ...widget.parent, ...?item};",
    )
    ADMIN_DART.write_text(admin, encoding="utf-8")

if CATALOG_DART.exists():
    catalog = CATALOG_DART.read_text(encoding="utf-8")
    catalog = catalog.replace(
        "if (title == 'SSO Settings') return _SSOSettingsScreen(repo: repo);\n  if (single)",
        "if (title == 'SSO Settings') return _SSOSettingsScreen(repo: repo);\n  if (title == 'Agent Analytics') return _ServerDataScreen(repo: repo, title: title, path: path);\n  if (single)",
    )
    catalog = catalog.replace(
        "deletePath: '/campaigns/{id}/recipients/{recipient_id}',\n            idField: 'recipient_id',",
        "deletePath: '/campaigns/{parent_id}/recipients/{id}',\n            idField: 'id',",
    )
    catalog = catalog.replace(
        "deletePath: '/teams/{id}/members/{user_id}',",
        "deletePath: '/teams/{parent_id}/members/{user_id}',",
    )
    catalog = catalog.replace(
        "editableKeys: ['name', 'retailer_id', 'description', 'price', 'currency', 'image_url', 'url', 'availability'],\n          ),",
        "editableKeys: ['name', 'retailer_id', 'description', 'price', 'currency', 'image_url', 'url', 'availability'],\n            updatePath: '/products/{id}',\n            deletePath: '/products/{id}',\n          ),",
    )
    catalog = catalog.replace(
        "editableKeys: const ['name', 'description', 'type', 'url', 'method', 'headers', 'body', 'script', 'icon', 'is_active'],\n      );",
        "editableKeys: const ['name', 'description', 'type', 'url', 'method', 'headers', 'body', 'script', 'icon', 'is_active'],\n        actions: const [ModuleAction('Execute', '/{id}/execute', icon: Icons.play_arrow)],\n      );",
        1,
    )
    CATALOG_DART.write_text(catalog, encoding="utf-8")

print("Applied Whatomate Flutter feature wiring overlay")
