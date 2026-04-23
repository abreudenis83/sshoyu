#!/bin/bash
set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONTROL_FILE="${REPO_ROOT}/debian/control"
PKG_DIR="${REPO_ROOT}/pkg"

VERSION=$(grep '^Version:' "$CONTROL_FILE" | awk '{print $2}')

if [ -z "$VERSION" ]; then
    echo "Erro: não foi possível ler a versão de ${CONTROL_FILE}" >&2
    exit 1
fi

OUTPUT="${REPO_ROOT}/sshoyu-server_${VERSION}_all.deb"

# Sincroniza debian/ → pkg/DEBIAN/
cp "${REPO_ROOT}/debian/control"   "${PKG_DIR}/DEBIAN/control"
cp "${REPO_ROOT}/debian/templates" "${PKG_DIR}/DEBIAN/templates"
cp "${REPO_ROOT}/debian/config"    "${PKG_DIR}/DEBIAN/config"
cp "${REPO_ROOT}/debian/postinst"  "${PKG_DIR}/DEBIAN/postinst"
cp "${REPO_ROOT}/debian/prerm"     "${PKG_DIR}/DEBIAN/prerm"
cp "${REPO_ROOT}/debian/postrm"    "${PKG_DIR}/DEBIAN/postrm"

# Garante permissões corretas
chmod 755 "${PKG_DIR}/DEBIAN/config" \
          "${PKG_DIR}/DEBIAN/postinst" \
          "${PKG_DIR}/DEBIAN/prerm" \
          "${PKG_DIR}/DEBIAN/postrm"
chmod 644 "${PKG_DIR}/DEBIAN/control" \
          "${PKG_DIR}/DEBIAN/templates"
chmod 755 "${PKG_DIR}/usr/share/sshoyu/sshoyu_cli.sh" \
          "${PKG_DIR}/usr/share/sshoyu/ssh_client.sh" \
          "${PKG_DIR}/usr/share/sshoyu/sshoyu-monitor.sh" \
          "${PKG_DIR}/usr/share/sshoyu/sshoyu-admin.sh"
chmod 644 "${PKG_DIR}/usr/share/sshoyu/index.html"
chmod 644 "${PKG_DIR}/lib/systemd/system/sshoyu-monitor.service"
dpkg-deb --build "$PKG_DIR" "$OUTPUT"

echo ""
echo "Pacote gerado: ${OUTPUT}"
