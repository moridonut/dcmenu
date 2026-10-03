#!/bin/bash
# dcmenu build script — needs only the Xcode Command Line Tools (swiftc).
#   xcode-select --install
set -euo pipefail

cd "$(dirname "$0")"
APP="build/Dcmenu.app"

echo "==> compiling"
mkdir -p "$APP/Contents/MacOS"
swiftc -O -o "$APP/Contents/MacOS/dcmenu" Sources/*.swift

echo "==> bundling helpers"
mkdir -p "$APP/Contents/Resources/bin"
cp bin/* "$APP/Contents/Resources/bin/"
chmod +x "$APP/Contents/Resources/bin/"*

echo "==> writing Info.plist"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>                <string>dcmenu</string>
  <key>CFBundleIdentifier</key>          <string>local.dcmenu</string>
  <key>CFBundleExecutable</key>          <string>dcmenu</string>
  <key>CFBundlePackageType</key>         <string>APPL</string>
  <key>CFBundleShortVersionString</key>  <string>0.1.0</string>
  <key>LSUIElement</key>                 <true/>
  <key>NSHighResolutionCapable</key>     <true/>
</dict>
</plist>
PLIST

echo "==> signing (ad-hoc)"
codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "   (codesign skipped)"

echo "==> done: $APP"
echo
echo "初回は ./install.sh で ~/bin と ~/.config/dcmenu にリンクを張ってください。"
