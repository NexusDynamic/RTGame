#!/usr/bin/env bash
# Installs a desktop entry and hicolor icons for the Linux build.
#
# On Wayland the window icon cannot be set by the application itself: the
# compositor matches the toplevel's app_id against a .desktop file of the same
# name and takes the icon from there. Without this, KWin/GNOME show a generic
# placeholder even though gtk_window_set_icon() succeeded.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CMAKE_FILE="$REPO_ROOT/linux/CMakeLists.txt"

# Derive these from CMake so they can never drift from what the binary reports.
APP_ID="$(sed -n 's/^set(APPLICATION_ID "\(.*\)")$/\1/p' "$CMAKE_FILE")"
BINARY_NAME="$(sed -n 's/^set(BINARY_NAME "\(.*\)")$/\1/p' "$CMAKE_FILE")"
[ -n "$APP_ID" ] && [ -n "$BINARY_NAME" ] || { echo "Could not parse APPLICATION_ID/BINARY_NAME from $CMAKE_FILE" >&2; exit 1; }

ICON_MASTER="$REPO_ROOT/assets/icon/RiseTogether-appicon.png"
APPS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
ICONS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor"
DESKTOP_FILE="$APPS_DIR/$APP_ID.desktop"
SIZES=(16 32 48 64 128 256 512)

# KDE keeps its own service cache (sycoca); update-desktop-database alone is not
# enough for Plasma to notice a new .desktop file.
refresh_caches() {
  gtk-update-icon-cache -f -t "$ICONS_DIR" 2>/dev/null || true
  update-desktop-database "$APPS_DIR" 2>/dev/null || true
  for sycoca in kbuildsycoca6 kbuildsycoca5; do
    command -v "$sycoca" >/dev/null && "$sycoca" --noincremental >/dev/null 2>&1 && break
  done
  return 0
}

if [ "${1:-}" = "--uninstall" ]; then
  rm -fv "$DESKTOP_FILE"
  for size in "${SIZES[@]}"; do
    rm -fv "$ICONS_DIR/${size}x${size}/apps/$APP_ID.png"
  done
  refresh_caches
  echo "Uninstalled $APP_ID."
  exit 0
fi

# Where the built binary lives. Override by passing a path to the bundle dir.
BUNDLE_DIR="${1:-}"
if [ -z "$BUNDLE_DIR" ]; then
  for build in release debug profile; do
    candidate="$REPO_ROOT/build/linux/x64/$build/bundle"
    if [ -x "$candidate/$BINARY_NAME" ]; then BUNDLE_DIR="$candidate"; break; fi
  done
fi
[ -n "$BUNDLE_DIR" ] && [ -x "$BUNDLE_DIR/$BINARY_NAME" ] || {
  echo "No built binary found. Run 'flutter build linux' first, or pass the bundle directory." >&2; exit 1; }

command -v magick >/dev/null || { echo "ImageMagick ('magick') is required to scale the icon." >&2; exit 1; }
for size in "${SIZES[@]}"; do
  install -d "$ICONS_DIR/${size}x${size}/apps"
  magick "$ICON_MASTER" -resize "${size}x${size}" -strip "$ICONS_DIR/${size}x${size}/apps/$APP_ID.png"
done

install -d "$APPS_DIR"
cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=RiseTogether
Comment=Networked joint action experiment platform
Exec=$BUNDLE_DIR/$BINARY_NAME
Icon=$APP_ID
Terminal=false
Categories=Education;
StartupWMClass=$APP_ID
EOF

refresh_caches

echo "Installed $DESKTOP_FILE"
echo "  app_id: $APP_ID"
echo "  exec:   $BUNDLE_DIR/$BINARY_NAME"
