#!/bin/sh
#
# install.sh -- installer for the pfSense "Postfix Forwarder" package.
#
# Copyright (c) 2011-2021 Marcello Coutinho
# Copyright (c) 2026 pfsense-packages-revived contributors
#
# Licensed under the Apache License, Version 2.0. See LICENSE.
#
# Derived from the postfix package in
# https://github.com/marcelloc/Unofficial-pfSense-packages (pkg-postfix),
# ported to pfSense 2.9 / PHP 8.5.
#
# Postfix here acts as a mail gateway / forwarder in front of your real mail
# server: it accepts SMTP, applies antispam and access policies, and relays on.
# For a small office already running pfSense, that avoids standing up a separate
# mail gateway appliance.
#
# NOTE: this listens on SMTP. Do not install it on a firewall that already has
# something bound to port 25, and think about whether your border firewall is
# where you want mail processing to live.
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

SRC_URL="${SRC_URL:-https://raw.githubusercontent.com/bootablearg/pfsense-packages-revived/main/postfix}"
# ${ABI} must reach pkg literally -- pkg expands it, the shell must not.
# Nesting it inside ${VAR:-default} makes sh swallow the closing brace and
# yields ".../${ABI/latest}", a repository URL that never resolves. The bug
# only surfaces when the binary is not already installed.
REPO_URL="${REPO_URL:-}"
[ -n "${REPO_URL}" ] || REPO_URL='pkg+https://pkg.freebsd.org/${ABI}/latest'

BIN_PKG="${BIN_PKG:-postfix}"
PKG_DEST="/usr/local/pkg"
WWW_DEST="/usr/local/www"
BIN_ETC="/usr/local/etc/postfix"
STAMP="/usr/local/etc/postfix.installed"
TMP_REPOS="/tmp/postfix_repos.$$"

# Package files, mirroring the upstream layout.
FILES_PKG="postfix.inc postfix.xml postfix_acl.xml postfix_antispam.xml
postfix_dkim.inc postfix_dmarc.inc postfix_domains.xml postfix_postfwd.inc
postfix_postwhite.template postfix_recipients.xml postfix_sync.xml"

FILES_WWW=""

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

bin_installed() { [ -x /usr/local/sbin/master ] || [ -x /usr/local/bin/master ]; }
bin_version()   { pkg query '%n-%v' ${BIN_PKG} 2>/dev/null | head -1; }

# Temporary pkg configuration: the firewall's own repository files are never
# touched, so an interrupted run cannot leave a third-party repo enabled.
prepare_repos() {
	mkdir -p "${TMP_REPOS}" || err "Could not create ${TMP_REPOS}"
	if [ -d /usr/local/etc/pkg/repos ]; then
		cp /usr/local/etc/pkg/repos/*.conf "${TMP_REPOS}/" 2>/dev/null || true
	fi
	printf 'FreeBSD-ports: { url: "%s", mirror_type: "srv", enabled: yes }\n' \
		"${REPO_URL}" > "${TMP_REPOS}/postfix_ports.conf"
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
	if (isset($item['name']) && $item['name'] === 'Postfix Forwarder') { $found = true; break; }
}
if (!$found) {
	$menu[] = [
		'name'    => 'Postfix Forwarder',
		'section' => 'Services',
		'url'     => '/pkg_edit.php?xml=postfix.xml&id=0',
	];
}

$service = function_exists('config_get_path')
	? config_get_path('installedpackages/service', [])
	: ($config['installedpackages']['service'] ?? []);
if (!is_array($service)) { $service = []; }

$found = false;
foreach ($service as $item) {
	if (isset($item['name']) && $item['name'] === 'postfix') { $found = true; break; }
}
if (!$found) {
	$service[] = [
		'name'        => 'postfix',
		'rcfile'      => 'postfix.sh',
		'executable'  => 'postfix',
		'description' => 'Postfix Forwarder',
	];
}

if (function_exists('config_set_path')) {
	config_set_path('installedpackages/menu', $menu);
	config_set_path('installedpackages/service', $service);
} else {
	$config['installedpackages']['menu'] = $menu;
	$config['installedpackages']['service'] = $service;
}

write_config('Postfix Forwarder: register package menu and service');
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
	return !(isset($i['name']) && $i['name'] === 'Postfix Forwarder');
}));

$service = function_exists('config_get_path')
	? config_get_path('installedpackages/service', [])
	: ($config['installedpackages']['service'] ?? []);
if (!is_array($service)) { $service = []; }
$service = array_values(array_filter($service, function ($i) {
	return !(isset($i['name']) && $i['name'] === 'postfix');
}));

if (function_exists('config_set_path')) {
	config_set_path('installedpackages/menu', $menu);
	config_set_path('installedpackages/service', $service);
} else {
	$config['installedpackages']['menu'] = $menu;
	$config['installedpackages']['service'] = $service;
}

write_config('Postfix Forwarder: unregister package');
exec;
exit
PHPEOF
}

# Generate the configuration through the package's own sync function -- the
# same call the GUI makes on save.
run_sync() {
	log "Generating configuration"
	/usr/local/sbin/pfSsh.php <<'PHPEOF'
require_once('/usr/local/pkg/postfix.inc');
sync_package_postfix();
exec;
exit
PHPEOF
}

do_check() {
	echo "Product   : $(detect_product)"
	echo "Version   : $(cat /etc/version 2>/dev/null)"
	echo "ABI       : $(pkg config abi 2>/dev/null)"
	echo "PHP       : $(php -v 2>/dev/null | head -1)"

	if bin_installed; then
		echo "postfix: installed ($(bin_version))"
	else
		prepare_repos
		log "Querying repositories (nothing is changed)"
		tpkg update >/dev/null 2>&1 || warn "Could not refresh repository catalogues."

		_v=$(tpkg search -q "^${BIN_PKG}-" 2>/dev/null | head -1)
		if [ -n "${_v}" ]; then
			echo "postfix: available as '${_v}'"
			echo
			echo "Install plan:"
			tpkg install -n "${BIN_PKG}" 2>&1 | tail -4
		else
			echo "postfix: NOT AVAILABLE for this ABI"
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

	if bin_installed; then
		log "postfix already installed ($(bin_version)), skipping"
	else
		prepare_repos
		log "Refreshing repository catalogues"
		tpkg update >/dev/null 2>&1 || err "Could not refresh repository catalogues."

		log "Installing ${BIN_PKG}"
		tpkg install -y "${BIN_PKG}" || err "postfix installation failed. Nothing else was changed."
		cleanup_repos
	fi

	bin_installed || err "postfix installed but the binary is missing. Aborting."

	install_files
	register_gui
	run_sync

	date "+%Y-%m-%dT%H:%M:%S%z" > "${STAMP}"

	log "Done."
	cat <<'EOT'

Next steps:

  1. Services > Postfix Forwarder -- configure your domains, relay and policies,
     then enable the service.

  2. Postfix listens on SMTP. Make sure nothing else on this firewall is bound
     to port 25, and that your border rules only accept mail where you intend.

  3. To add antispam/antivirus filtering on top, see the mailscanner package in
     this repository.

EOT
}

do_remove() {
	require_root

	if pgrep -x master >/dev/null 2>&1; then
		log "Stopping postfix"
		pkill -x master 2>/dev/null
		sleep 2
	fi

	unregister_gui
	remove_files
	rm -f "${STAMP}"
	rm -f /usr/local/etc/rc.d/postfix.sh

	log "Package removed."
	log "postfix itself and ${BIN_ETC} were left in place."
	log "Remove them with: pkg remove -y ${BIN_PKG}"
}

do_status() {
	if [ -f "${STAMP}" ]; then
		echo "Installed: $(cat "${STAMP}")"
	else
		echo "Not installed."
	fi

	bin_installed && echo "binary: $(bin_version)" || echo "binary: not installed"
	pgrep -x master >/dev/null 2>&1 && echo "postfix: running" || echo "postfix: stopped"
}

case "${1:-}" in
	check)   do_check ;;
	install) do_install ;;
	remove)  do_remove ;;
	status)  do_status ;;
	*)       echo "Usage: $0 {check|install|remove|status}"; exit 64 ;;
esac
