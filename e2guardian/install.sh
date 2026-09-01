#!/bin/sh
#
# install.sh -- installer for the pfSense "E2guardian" web content filter package.
#
# Copyright (c) 2015-2017 Marcello Coutinho
# Copyright (c) 2026 pfsense-packages-revived contributors
#
# Licensed under the Apache License, Version 2.0. See LICENSE.
#
# Derived from the e2guardian package in
# https://github.com/marcelloc/Unofficial-pfSense-packages (pkg-e2guardian5),
# ported to pfSense 2.9 / PHP 8.5 and to e2guardian 5.3.x.
#
# Usage, from a clone:
#   ./install.sh check     Report what would happen. Changes nothing.
#   ./install.sh install   Install e2guardian, the package files and the GUI.
#   ./install.sh remove    Unregister and remove the package files.
#   ./install.sh status    Show current state.
#
# Or straight from the network:
#   fetch -q -o - https://raw.githubusercontent.com/bootablearg/pfsense-packages-revived/main/e2guardian/install.sh | sh -s check
#
# e2guardian filters by *content* -- it inspects the response body, phrases,
# MIME types -- and can apply different policies per group. That is what it
# adds over DNS-level filtering such as pfBlockerNG, which blocks by domain
# and cannot see inside a response.
#
# The binary comes from FreeBSD's official package repository: no private
# repository, no key. See ../docs/PATTERN.md for the method and its caveats.

set -u

SCRIPT_DIR=""
case "$0" in
	*/*) SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)" ;;
esac

PKG_SRC_DIR=""
WWW_SRC_DIR=""
if [ -n "${SCRIPT_DIR}" ] && [ -d "${SCRIPT_DIR}/pkg" ]; then
	PKG_SRC_DIR="${SCRIPT_DIR}/pkg"
	WWW_SRC_DIR="${SCRIPT_DIR}/www"
fi

SRC_URL="${SRC_URL:-https://raw.githubusercontent.com/bootablearg/pfsense-packages-revived/main/e2guardian}"
REPO_URL="${REPO_URL:-pkg+https://pkg.freebsd.org/\${ABI}/latest}"

E2G_PKG="${E2G_PKG:-e2guardian}"
PKG_DEST="/usr/local/pkg"
WWW_DEST="/usr/local/www"
E2G_ETC="/usr/local/etc/e2guardian"
STAMP="/usr/local/etc/e2guardian.installed"
TMP_REPOS="/tmp/e2g_repos.$$"

# Package files, mirroring the upstream layout.
FILES_PKG="e2guardian.inc e2guardian_antivirus.inc pkg_e2guardian.inc
e2guardian.xml e2guardian_config.xml e2guardian_groups.xml e2guardian_ips.xml
e2guardian_ldap.xml e2guardian_limits.xml e2guardian_log.xml
e2guardian_blacklist.xml e2guardian_sync.xml e2guardian_users.xml
e2guardian_site_acl.xml e2guardian_url_acl.xml e2guardian_phrase_acl.xml
e2guardian_content_acl.xml e2guardian_file_acl.xml e2guardian_header_acl.xml
e2guardian_search_acl.xml e2guardian_antivirus_acl.xml
e2guardian.conf.template e2guardianfx.conf.template e2guardian_rc.template
e2guardian_story.template e2guardian_ips_header.template
e2guardian_users_header.template e2guardian_users_footer.template
icapscan.conf.template"

FILES_WWW="e2guardian.php"

log()  { echo "==> $*"; }
warn() { echo "WARNING: $*" >&2; }
err()  { echo "ERROR: $*" >&2; cleanup_repos; exit 1; }

cleanup_repos() {
	[ -d "${TMP_REPOS}" ] && rm -rf "${TMP_REPOS}"
	return 0
}
trap cleanup_repos EXIT INT TERM

require_root() {
	[ "$(id -u)" = "0" ] || err "This script must be run as root."
}

detect_product() {
	_p=""
	if [ -x /usr/local/bin/php ]; then
		_p=$(/usr/local/bin/php -r \
			'require_once("globals.inc"); echo $g["product_name"] ?? "";' \
			2>/dev/null | tr -d '\r\n')
	fi
	[ -n "${_p}" ] && { echo "${_p}"; return; }

	case "$(cat /etc/version 2>/dev/null)" in
		2.*)                    echo "pfSense" ;;
		[0-9][0-9].[0-9][0-9]*) echo "pfSense Plus" ;;
		*)                      echo "unknown" ;;
	esac
}

e2g_installed() { [ -x /usr/local/sbin/e2guardian ]; }
e2g_version()   { /usr/local/sbin/e2guardian -v 2>/dev/null | head -1; }

# Temporary pkg configuration: the firewall's own repository files are never
# touched, so an interrupted run cannot leave a third-party repo enabled.
prepare_repos() {
	mkdir -p "${TMP_REPOS}" || err "Could not create ${TMP_REPOS}"
	if [ -d /usr/local/etc/pkg/repos ]; then
		cp /usr/local/etc/pkg/repos/*.conf "${TMP_REPOS}/" 2>/dev/null || true
	fi
	printf 'FreeBSD-ports: { url: "%s", mirror_type: "srv", enabled: yes }\n' \
		"${REPO_URL}" > "${TMP_REPOS}/e2g_ports.conf"
}

# pfSense tracks a FreeBSD snapshot behind the one the official packages are
# built against, so pkg refuses the repository without this.
tpkg() {
	IGNORE_OSVERSION=yes pkg -o REPOS_DIR="${TMP_REPOS}" "$@"
}

fetch_one() {
	_name="$1"; _srcdir="$2"; _dest="$3"; _urlpath="$4"

	if [ -n "${_srcdir}" ] && [ -f "${_srcdir}/${_name}" ]; then
		cp -f "${_srcdir}/${_name}" "${_dest}/${_name}"
	else
		fetch -q -o "${_dest}/${_name}" "${SRC_URL}/${_urlpath}/${_name}" \
			|| err "Could not fetch ${_name} from ${SRC_URL}/${_urlpath}"
	fi
	chmod 0644 "${_dest}/${_name}"
}

install_files() {
	log "Installing package files"
	mkdir -p "${PKG_DEST}" "${WWW_DEST}"

	for _f in ${FILES_PKG}; do fetch_one "${_f}" "${PKG_SRC_DIR}" "${PKG_DEST}" "pkg"; done
	for _f in ${FILES_WWW}; do fetch_one "${_f}" "${WWW_SRC_DIR}" "${WWW_DEST}" "www"; done
}

remove_files() {
	log "Removing package files"
	for _f in ${FILES_PKG}; do rm -f "${PKG_DEST}/${_f}"; done
	for _f in ${FILES_WWW}; do rm -f "${WWW_DEST}/${_f}"; done
}

register_gui() {
	log "Registering menu entry and service"

	/usr/local/sbin/pfSsh.php <<'PHPEOF'
$menu = function_exists('config_get_path')
	? config_get_path('installedpackages/menu', [])
	: ($config['installedpackages']['menu'] ?? []);
if (!is_array($menu)) { $menu = []; }

$found = false;
foreach ($menu as $item) {
	if (isset($item['name']) && $item['name'] === 'E2guardian Proxy') { $found = true; break; }
}
if (!$found) {
	$menu[] = [
		'name'    => 'E2guardian Proxy',
		'section' => 'Services',
		'url'     => '/pkg_edit.php?xml=e2guardian.xml&id=0',
	];
}

$service = function_exists('config_get_path')
	? config_get_path('installedpackages/service', [])
	: ($config['installedpackages']['service'] ?? []);
if (!is_array($service)) { $service = []; }

$found = false;
foreach ($service as $item) {
	if (isset($item['name']) && $item['name'] === 'e2guardian') { $found = true; break; }
}
if (!$found) {
	$service[] = [
		'name'        => 'e2guardian',
		'rcfile'      => 'e2guardian.sh',
		'executable'  => 'e2guardian',
		'description' => 'E2guardian web content filter',
	];
}

if (function_exists('config_set_path')) {
	config_set_path('installedpackages/menu', $menu);
	config_set_path('installedpackages/service', $service);
} else {
	$config['installedpackages']['menu'] = $menu;
	$config['installedpackages']['service'] = $service;
}

write_config('E2guardian: register package menu and service');
exec;
exit
PHPEOF
}

unregister_gui() {
	log "Unregistering menu entry and service"

	/usr/local/sbin/pfSsh.php <<'PHPEOF'
$menu = function_exists('config_get_path')
	? config_get_path('installedpackages/menu', [])
	: ($config['installedpackages']['menu'] ?? []);
if (!is_array($menu)) { $menu = []; }
$menu = array_values(array_filter($menu, function ($i) {
	return !(isset($i['name']) && $i['name'] === 'E2guardian Proxy');
}));

$service = function_exists('config_get_path')
	? config_get_path('installedpackages/service', [])
	: ($config['installedpackages']['service'] ?? []);
if (!is_array($service)) { $service = []; }
$service = array_values(array_filter($service, function ($i) {
	return !(isset($i['name']) && $i['name'] === 'e2guardian');
}));

if (function_exists('config_set_path')) {
	config_set_path('installedpackages/menu', $menu);
	config_set_path('installedpackages/service', $service);
} else {
	$config['installedpackages']['menu'] = $menu;
	$config['installedpackages']['service'] = $service;
}

write_config('E2guardian: unregister package');
exec;
exit
PHPEOF
}

# Generate the configuration through the package's own sync function -- the
# same call the GUI makes on save.
run_sync() {
	log "Generating e2guardian configuration"
	/usr/local/sbin/pfSsh.php <<'PHPEOF'
require_once('/usr/local/pkg/e2guardian.inc');
sync_package_e2guardian('no', true);
exec;
exit
PHPEOF
}

do_check() {
	echo "Product   : $(detect_product)"
	echo "Version   : $(cat /etc/version 2>/dev/null)"
	echo "ABI       : $(pkg config abi 2>/dev/null)"
	echo "PHP       : $(php -v 2>/dev/null | head -1)"

	if e2g_installed; then
		echo "e2guardian: installed ($(e2g_version))"
	else
		prepare_repos
		log "Querying repositories (nothing is changed)"
		tpkg update >/dev/null 2>&1 || warn "Could not refresh repository catalogues."

		_v=$(tpkg search -q "^${E2G_PKG}-" 2>/dev/null | head -1)
		if [ -n "${_v}" ]; then
			echo "e2guardian: available as '${_v}'"
			echo
			echo "Install plan:"
			tpkg install -n "${E2G_PKG}" 2>&1 | tail -4
		else
			echo "e2guardian: NOT AVAILABLE for this ABI"
			echo "            See ../docs/PATTERN.md for the poudriere fallback."
		fi
		cleanup_repos
	fi

	if [ -f "${STAMP}" ]; then
		echo "Package   : installed ($(cat "${STAMP}"))"
	else
		echo "Package   : not installed"
	fi
}

do_install() {
	require_root

	_product=$(detect_product)
	log "Detected ${_product} $(cat /etc/version 2>/dev/null) (ABI $(pkg config abi 2>/dev/null))"

	case "${_product}" in
		"pfSense"|"pfSense Plus") : ;;
		*) warn "Unrecognised product '${_product}'; continuing, but this is untested." ;;
	esac

	if e2g_installed; then
		log "e2guardian already installed ($(e2g_version)), skipping"
	else
		prepare_repos
		log "Refreshing repository catalogues"
		tpkg update >/dev/null 2>&1 || err "Could not refresh repository catalogues."

		log "Installing ${E2G_PKG}"
		tpkg install -y "${E2G_PKG}" || err "e2guardian installation failed. Nothing else was changed."
		cleanup_repos
	fi

	e2g_installed || err "e2guardian installed but the binary is missing. Aborting."

	install_files
	register_gui
	run_sync

	date "+%Y-%m-%dT%H:%M:%S%z" > "${STAMP}"

	log "Done."
	cat <<'EOT'

Next steps:

  1. Services > E2guardian Proxy -- review the settings and enable the service.

  2. Blacklists are NOT downloaded by this installer, because they are large
     and the download is slow. Fetch them from the package's Blacklist tab
     when you want them.

  3. e2guardian filters content; it does not replace DNS-level blocking.
     pfBlockerNG (official, supported) covers domain and IP blocking and the
     two complement each other.

  4. If you use it downstream of Squid with AD authentication, the samba-ad
     package in this repository provides the authentication side.

EOT
}

do_remove() {
	require_root

	if pgrep -x e2guardian >/dev/null 2>&1; then
		log "Stopping e2guardian"
		pkill -x e2guardian 2>/dev/null
		sleep 2
	fi

	unregister_gui
	remove_files
	rm -f "${STAMP}"
	rm -f /usr/local/etc/rc.d/e2guardian.sh

	log "Package removed."
	log "e2guardian itself and ${E2G_ETC} were left in place."
	log "Remove them with: pkg remove -y ${E2G_PKG}"
}

do_status() {
	if [ -f "${STAMP}" ]; then
		echo "Installed: $(cat "${STAMP}")"
	else
		echo "Not installed."
	fi

	e2g_installed && echo "binary: $(e2g_version)" || echo "binary: not installed"
	pgrep -x e2guardian >/dev/null 2>&1 && echo "e2guardian: running" || echo "e2guardian: stopped"
}

case "${1:-}" in
	check)   do_check ;;
	install) do_install ;;
	remove)  do_remove ;;
	status)  do_status ;;
	*)       echo "Usage: $0 {check|install|remove|status}"; exit 64 ;;
esac
