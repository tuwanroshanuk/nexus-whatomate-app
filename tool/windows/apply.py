from pathlib import Path
import shutil


ROOT = Path(__file__).resolve().parents[2]
WINDOWS = ROOT / "windows"
RUNNER = WINDOWS / "runner"

if not RUNNER.exists():
    raise SystemExit("windows/runner is missing; run flutter create --platforms=windows first")

icon_source = Path(__file__).with_name("app_icon.ico")
icon_target = RUNNER / "resources" / "app_icon.ico"
icon_target.parent.mkdir(parents=True, exist_ok=True)
shutil.copy2(icon_source, icon_target)

main_cpp = RUNNER / "main.cpp"
if main_cpp.exists():
    text = main_cpp.read_text(encoding="utf-8")
    text = text.replace('L"whatomate_app"', 'L"Nexus One"')
    main_cpp.write_text(text, encoding="utf-8", newline="\n")

runner_rc = RUNNER / "Runner.rc"
if runner_rc.exists():
    text = runner_rc.read_text(encoding="utf-8")
    text = text.replace('VALUE "FileDescription", "whatomate_app"', 'VALUE "FileDescription", "Nexus One"')
    text = text.replace('VALUE "InternalName", "whatomate_app"', 'VALUE "InternalName", "Nexus One"')
    text = text.replace('VALUE "ProductName", "whatomate_app"', 'VALUE "ProductName", "Nexus One"')
    runner_rc.write_text(text, encoding="utf-8", newline="\n")

print("Applied Nexus One Windows branding overlay")
