#!/bin/sh
#
# install.sh -- installer for the pfSense "Sarg Reports" package.
#
# Copyright (c) 2007 Joao Henrique F. Freitas
# Copyright (c) 2012-2024 Marcello Coutinho
# Copyright (c) 2015 ESF, LLC
# Copyright (c) 2026 pfsense-packages-revived contributors
#
# Licensed under the BSD 2-Clause License. See LICENSE.
#
# Sarg (Squid Analysis Report Generator) turns Squid's access log into per-user reports. With the proxy
# authenticating against Active Directory (see ../samba-ad/), those reports are
# keyed by domain username rather than by IP -- which, on a DHCP network, is
# the difference between a report you can act on and one you cannot.
#
# Usage:
#   ./install.sh check | install | remove | status
#
# Or from the network:
#   fetch -q -o - https://raw.githubusercontent.com/bootablearg/pfsense-packages-revived/main/sarg/install.sh | sh -s check
#
# See ../docs/PATTERN.md for the method and its caveats.

set -u

SCRIPT_DIR=""
case "$0" in
	*/*) SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)" ;;
esac

PKG_SRC_DIR=""
[ -n "${SCRIPT_DIR}" ] && [ -d "${SCRIPT_DIR}/pkg" ] && PKG_SRC_DIR="${SCRIPT_DIR}/pkg"

SRC_URL="${SRC_URL:-https://raw.githubusercontent.com/bootablearg/pfsense-packages-revived/main/sarg}"
# ${ABI} must reach pkg literally -- pkg expands it, the shell must not.
# Nesting it inside ${VAR:-default} makes sh swallow the closing brace and
# yields ".../${ABI/latest}", a repository URL that never resolves. The bug
# only surfaces when the binary is not already installed.
REPO_URL="${REPO_URL:-}"
[ -n "${REPO_URL}" ] || REPO_URL='pkg+https://pkg.freebsd.org/${ABI}/latest'

BIN_PKG="sarg"
BIN="/usr/local/bin/sarg"
PKG_DEST="/usr/local/pkg"
STAMP="/usr/local/etc/sarg.installed"
TMP_REPOS="/tmp/sarg_repos.$$"

FILES_PKG="sarg.inc sarg.xml sarg_schedule.xml sarg_sync.xml sarg_users.xml sarg.template"

log()  { echo "==> $*"; }
warn() { echo "WARNING: $*" >&2; }
err()  { echo "ERROR: $*" >&2; cleanup; exit 1; }
cleanup() { [ -d "${TMP_REPOS}" ] && rm -rf "${TMP_REPOS}"; return 0; }
trap cleanup EXIT INT TERM

require_root() { [ "$(id -u)" = "0" ] || err "This script must be run as root."; }

detect_product() {
	_p=""
	if [ -x /usr/local/bin/php ]; then
		_p=$(/usr/local/bin/php -r 'require_once("globals.inc"); echo $g["product_name"] ?? "";' 2>/dev/null | tr -d '\r\n')
	fi
	[ -n "${_p}" ] && { echo "${_p}"; return; }
	case "$(cat /etc/version 2>/dev/null)" in
		2.*) echo "pfSense" ;;
		[0-9][0-9].[0-9][0-9]*) echo "pfSense Plus" ;;
		*) echo "unknown" ;;
	esac
}

bin_installed() { [ -x "${BIN}" ]; }

# Temporary pkg configuration: the firewall's own repository files are never
# modified, so an interrupted run leaves nothing behind.
prepare_repos() {
	mkdir -p "${TMP_REPOS}" || err "Could not create ${TMP_REPOS}"
	[ -d /usr/local/etc/pkg/repos ] && cp /usr/local/etc/pkg/repos/*.conf "${TMP_REPOS}/" 2>/dev/null
	printf 'FreeBSD-ports: { url: "%s", mirror_type: "srv", enabled: yes }\n' \
		"${REPO_URL}" > "${TMP_REPOS}/sarg_ports.conf"
}

# pfSense tracks a FreeBSD snapshot behind the official packages, so pkg
# refuses the repository without this.
tpkg() { IGNORE_OSVERSION=yes pkg -o REPOS_DIR="${TMP_REPOS}" "$@"; }

install_files() {
	log "Installing package files"
	mkdir -p "${PKG_DEST}"
	for _f in ${FILES_PKG}; do
		if [ -n "${PKG_SRC_DIR}" ] && [ -f "${PKG_SRC_DIR}/${_f}" ]; then
			cp -f "${PKG_SRC_DIR}/${_f}" "${PKG_DEST}/${_f}"
		else
			fetch -q -o "${PKG_DEST}/${_f}" "${SRC_URL}/pkg/${_f}" \
				|| err "Could not fetch ${_f} from ${SRC_URL}/pkg"
		fi
		chmod 0644 "${PKG_DEST}/${_f}"
	done
}

remove_files() {
	log "Removing package files"
	for _f in ${FILES_PKG}; do rm -f "${PKG_DEST}/${_f}"; done
}

register_gui() {
	log "Registering menu entry"
	/usr/local/sbin/pfSsh.php <<'PHPEOF'
$menu = function_exists('config_get_path')
	? config_get_path('installedpackages/menu', [])
	: ($config['installedpackages']['menu'] ?? []);
if (!is_array($menu)) { $menu = []; }

$found = false;
foreach ($menu as $item) {
	if (isset($item['name']) && $item['name'] === 'Sarg Reports') { $found = true; break; }
}
if (!$found) {
	$menu[] = [
		'name'    => 'Sarg Reports',
		'section' => 'Status',
		'url'     => '/pkg_edit.php?xml=sarg.xml&id=0',
	];
}

if (function_exists('config_set_path')) {
	config_set_path('installedpackages/menu', $menu);
} else {
	$config['installedpackages']['menu'] = $menu;
}
write_config('Sarg: register package menu');
exec;
exit
PHPEOF
}

unregister_gui() {
	log "Unregistering menu entry"
	/usr/local/sbin/pfSsh.php <<'PHPEOF'
$menu = function_exists('config_get_path')
	? config_get_path('installedpackages/menu', [])
	: ($config['installedpackages']['menu'] ?? []);
if (!is_array($menu)) { $menu = []; }
$menu = array_values(array_filter($menu, function ($i) {
	return !(isset($i['name']) && $i['name'] === 'Sarg Reports');
}));

if (function_exists('config_set_path')) {
	config_set_path('installedpackages/menu', $menu);
} else {
	$config['installedpackages']['menu'] = $menu;
}
write_config('Sarg: unregister package');
exec;
exit
PHPEOF
}

run_sync() {
	log "Generating configuration"
	/usr/local/sbin/pfSsh.php <<'PHPEOF'
require_once('/usr/local/pkg/sarg.inc');
sarg_package_install();
sync_package_sarg();
exec;
exit
PHPEOF
}

do_check() {
	echo "Product : $(detect_product)"
	echo "Version : $(cat /etc/version 2>/dev/null)"
	echo "ABI     : $(pkg config abi 2>/dev/null)"
	echo "PHP     : $(php -v 2>/dev/null | head -1)"

	if bin_installed; then
		echo "Binary  : installed ($(pkg query '%n-%v' ${BIN_PKG} 2>/dev/null))"
	else
		prepare_repos
		tpkg update >/dev/null 2>&1 || warn "Could not refresh repository catalogues."
		_v=$(tpkg search -q "^${BIN_PKG}-" 2>/dev/null | head -1)
		if [ -n "${_v}" ]; then
			echo "Binary  : available as '${_v}'"
			tpkg install -n "${BIN_PKG}" 2>&1 | tail -3
		else
			echo "Binary  : NOT AVAILABLE for this ABI"
		fi
		cleanup
	fi

	if [ -d /usr/local/libexec/squid ] || pkg info -e pfSense-pkg-squid 2>/dev/null; then
		echo "Squid   : installed (its access log is what gets analysed)"
	else
		echo "Squid   : NOT installed -- there will be no log to report on"
	fi

	[ -f "${STAMP}" ] && echo "Package : installed ($(cat "${STAMP}"))" || echo "Package : not installed"
}

do_install() {
	require_root
	log "Detected $(detect_product) $(cat /etc/version 2>/dev/null) (ABI $(pkg config abi 2>/dev/null))"

	if bin_installed; then
		log "sarg already installed, skipping"
	else
		prepare_repos
		tpkg update >/dev/null 2>&1 || err "Could not refresh repository catalogues."
		log "Installing ${BIN_PKG}"
		tpkg install -y "${BIN_PKG}" || err "Installation failed. Nothing else was changed."
		cleanup
	fi

	bin_installed || err "Package installed but ${BIN} is missing. Aborting."

	install_files
	register_gui
	run_sync
	date "+%Y-%m-%dT%H:%M:%S%z" > "${STAMP}"

	log "Done."
	cat <<'EOT'

Next: Status > Sarg Reports.

Reports are generated from Squid's access log by a cron job, so nothing appears
until Squid has logged some traffic and the job has run at least once.

For per-user reports rather than per-IP, Squid must be authenticating. The
samba-ad package in this repository provides Active Directory authentication.

EOT
}

do_remove() {
	require_root
	unregister_gui
	remove_files
	rm -f "${STAMP}"
	log "Package removed. The sarg binary and generated reports were left in place."
	log "Remove the binary with: pkg remove -y ${BIN_PKG}"
}

do_status() {
	[ -f "${STAMP}" ] && echo "Installed: $(cat "${STAMP}")" || echo "Not installed."
	bin_installed && echo "binary: $(pkg query '%n-%v' ${BIN_PKG} 2>/dev/null)" || echo "binary: not installed"
}

case "${1:-}" in
	check)   do_check ;;
	install) do_install ;;
	remove)  do_remove ;;
	status)  do_status ;;
	*)       echo "Usage: $0 {check|install|remove|status}"; exit 64 ;;
esac
