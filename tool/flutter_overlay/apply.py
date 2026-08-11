#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ROOT_DART = ROOT / "lib" / "ui" / "root.dart"

if not ROOT_DART.exists():
    raise SystemExit("lib/ui/root.dart is missing")

text = ROOT_DART.read_text()

# Keep the hand-authored shell small while activating the richer feature
# surfaces already maintained in separate files. This patch is idempotent so
# local and CI builds behave the same way when it is run more than once.
import_anchor = "import '../core/session.dart';\n"
imports = (
    "import 'full_chat_screen.dart';\n"
    "import 'management_catalog.dart';\n"
)
if "import 'full_chat_screen.dart';" not in text:
    if import_anchor not in text:
        raise SystemExit("Could not locate root.dart import anchor")
    text = text.replace(import_anchor, import_anchor + imports, 1)

old_chat = "onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(\n                repo: widget.repo, realtime: widget.realtime, calls: widget.calls, contact: c))),"
new_chat = "onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FullChatScreen(\n                repo: widget.repo, realtime: widget.realtime, calls: widget.calls, contact: c))),"
if old_chat in text:
    text = text.replace(old_chat, new_chat, 1)
elif "FullChatScreen(" not in text:
    raise SystemExit("Could not locate conversation chat route")

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

ROOT_DART.write_text(text)
print("Applied Whatomate Flutter feature wiring overlay")
