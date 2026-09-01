#!/bin/sh
#
# install.sh -- installer for the pfSense "Mailscanner" package.
#
# Copyright (c) 2011-2019 Marcello Coutinho
# Copyright (c) 2026 pfsense-packages-revived contributors
#
# Licensed under the Apache License, Version 2.0. See LICENSE.
#
# Derived from the mailscanner package in
# https://github.com/marcelloc/Unofficial-pfSense-packages (pkg-mailscanner),
# ported to pfSense 2.9 / PHP 8.5.
#
# MailScanner wraps SpamAssassin and ClamAV into a mail-filtering gateway. It
# needs an MTA underneath -- the postfix package in this repository provides it.
#
# NOTE: FreeBSD ships MailScanner 5.3.4 while upstream is at 5.5.x, and the
# project's development has slowed relative to newer filtering stacks. It also
# pulls in about 93 MiB. Weigh that before deploying it.
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

SRC_URL="${SRC_URL:-https://raw.githubusercontent.com/bootablearg/pfsense-packages-revived/main/mailscanner}"
# ${ABI} must reach pkg literally -- pkg expands it, the shell must not.
# Nesting it inside ${VAR:-default} makes sh swallow the closing brace and
# yields ".../${ABI/latest}", a repository URL that never resolves. The bug
# only surfaces when the binary is not already installed.
REPO_URL="${REPO_URL:-}"
[ -n "${REPO_URL}" ] || REPO_URL='pkg+https://pkg.freebsd.org/${ABI}/latest'

BIN_PKG="${BIN_PKG:-mailscanner}"
PKG_DEST="/usr/local/pkg"
WWW_DEST="/usr/local/www"
BIN_ETC="/usr/local/etc/mailscanner"
STAMP="/usr/local/etc/mailscanner.installed"
TMP_REPOS="/tmp/mailscanner_repos.$$"

# Package files, mirroring the upstream layout.
FILES_PKG="mailscanner.conf.template mailscanner.inc mailscanner.xml
mailscanner_alerts.xml mailscanner_antispam.xml mailscanner_antivirus.xml
mailscanner_attachments.xml mailscanner_content.xml mailscanner_report.xml
mailscanner_sync.xml"

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

bin_installed() { [ -x /usr/local/sbin/perl_mailscanner ] || [ -x /usr/local/bin/perl_mailscanner ]; }
bin_version()   { pkg query '%n-%v' ${BIN_PKG} 2>/dev/null | head -1; }

# Temporary pkg configuration: the firewall's own repository files are never
# touched, so an interrupted run cannot leave a third-party repo enabled.
prepare_repos() {
	mkdir -p "${TMP_REPOS}" || err "Could not create ${TMP_REPOS}"
	if [ -d /usr/local/etc/pkg/repos ]; then
		cp /usr/local/etc/pkg/repos/*.conf "${TMP_REPOS}/" 2>/dev/null || true
	fi
	printf 'FreeBSD-ports: { url: "%s", mirror_type: "srv", enabled: yes }\n' \
		"${REPO_URL}" > "${TMP_REPOS}/mailscanner_ports.conf"
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

# Register the package with pfSense's Package Manager.
#
# Without this entry the package works, but never appears under
# System > Package Manager > Installed Packages, so it cannot be uninstalled
# from the GUI -- only by running this script with "remove".
#
# pfSense's uninstall_package() checks whether a real pfSense-pkg-<name> exists;
# when it does not, as here, it falls back to delete_package_xml(), which reads
# the <menu>, <service> and deinstall command out of the package XML and undoes
# them. That is exactly the behaviour we want, so registering here is safe.
register_package() {
	log "Registering with the Package Manager"

	/usr/local/sbin/pfSsh.php <<PKGEOF
\$pkgs = function_exists('config_get_path')
	? config_get_path('installedpackages/package', [])
	: (\$config['installedpackages']['package'] ?? []);
if (!is_array(\$pkgs)) { \$pkgs = []; }

\$found = false;
foreach (\$pkgs as \$p) {
	if (isset(\$p['name']) && \$p['name'] === 'mailscanner') { \$found = true; break; }
}
if (!\$found) {
	\$pkgs[] = [
		'name'              => 'mailscanner',
		'descr'             => 'Mail filtering with SpamAssassin and ClamAV.',
		'website'           => 'https://github.com/bootablearg/pfsense-packages-revived',
		'version'           => '1.0.0',
		'configurationfile' => 'mailscanner.xml',
	];
}

if (function_exists('config_set_path')) {
	config_set_path('installedpackages/package', \$pkgs);
} else {
	\$config['installedpackages']['package'] = \$pkgs;
}
write_config('Mailscanner: register with Package Manager');
exec;
exit
PKGEOF
}

unregister_package() {
	log "Unregistering from the Package Manager"

	/usr/local/sbin/pfSsh.php <<PKGEOF
\$pkgs = function_exists('config_get_path')
	? config_get_path('installedpackages/package', [])
	: (\$config['installedpackages']['package'] ?? []);
if (!is_array(\$pkgs)) { \$pkgs = []; }

\$pkgs = array_values(array_filter(\$pkgs, function (\$p) {
	return !(isset(\$p['name']) && \$p['name'] === 'mailscanner');
}));

if (function_exists('config_set_path')) {
	config_set_path('installedpackages/package', \$pkgs);
} else {
	\$config['installedpackages']['package'] = \$pkgs;
}
write_config('Mailscanner: unregister from Package Manager');
exec;
exit
PKGEOF
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
	if (isset($item['name']) && $item['name'] === 'Mailscanner') { $found = true; break; }
}
if (!$found) {
	$menu[] = [
		'name'    => 'Mailscanner',
		'section' => 'Services',
		'url'     => '/pkg_edit.php?xml=mailscanner.xml&id=0',
	];
}

$service = function_exists('config_get_path')
	? config_get_path('installedpackages/service', [])
	: ($config['installedpackages']['service'] ?? []);
if (!is_array($service)) { $service = []; }

$found = false;
foreach ($service as $item) {
	if (isset($item['name']) && $item['name'] === 'mailscanner') { $found = true; break; }
}
if (!$found) {
	$service[] = [
		'name'        => 'mailscanner',
		'rcfile'      => 'mailscanner',
		'executable'  => 'mailscanner',
		'description' => 'Mailscanner',
	];
}

if (function_exists('config_set_path')) {
	config_set_path('installedpackages/menu', $menu);
	config_set_path('installedpackages/service', $service);
} else {
	$config['installedpackages']['menu'] = $menu;
	$config['installedpackages']['service'] = $service;
}

write_config('Mailscanner: register package menu and service');
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
	return !(isset($i['name']) && $i['name'] === 'Mailscanner');
}));

$service = function_exists('config_get_path')
	? config_get_path('installedpackages/service', [])
	: ($config['installedpackages']['service'] ?? []);
if (!is_array($service)) { $service = []; }
$service = array_values(array_filter($service, function ($i) {
	return !(isset($i['name']) && $i['name'] === 'mailscanner');
}));

if (function_exists('config_set_path')) {
	config_set_path('installedpackages/menu', $menu);
	config_set_path('installedpackages/service', $service);
} else {
	$config['installedpackages']['menu'] = $menu;
	$config['installedpackages']['service'] = $service;
}

write_config('Mailscanner: unregister package');
exec;
exit
PHPEOF
}

# Generate the configuration through the package's own sync function -- the
# same call the GUI makes on save.
run_sync() {
	log "Generating configuration"
	/usr/local/sbin/pfSsh.php <<'PHPEOF'
require_once('/usr/local/pkg/mailscanner.inc');
sync_package_mailscanner();
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
		echo "mailscanner: installed ($(bin_version))"
	else
		prepare_repos
		log "Querying repositories (nothing is changed)"
		tpkg update >/dev/null 2>&1 || warn "Could not refresh repository catalogues."

		_v=$(tpkg search -q "^${BIN_PKG}-" 2>/dev/null | head -1)
		if [ -n "${_v}" ]; then
			echo "mailscanner: available as '${_v}'"
			echo
			echo "Install plan:"
			tpkg install -n "${BIN_PKG}" 2>&1 | tail -4
		else
			echo "mailscanner: NOT AVAILABLE for this ABI"
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
		log "mailscanner already installed ($(bin_version)), skipping"
	else
		prepare_repos
		log "Refreshing repository catalogues"
		tpkg update >/dev/null 2>&1 || err "Could not refresh repository catalogues."

		log "Installing ${BIN_PKG}"
		tpkg install -y "${BIN_PKG}" || err "mailscanner installation failed. Nothing else was changed."
		cleanup_repos
	fi

	bin_installed || err "mailscanner installed but the binary is missing. Aborting."

	install_files
	register_gui
	register_package
	run_sync

	date "+%Y-%m-%dT%H:%M:%S%z" > "${STAMP}"

	log "Done."
	cat <<'EOT'

Next steps:

  1. Services > Mailscanner -- configure scanning, then enable the service.

  2. MailScanner needs an MTA underneath. The postfix package in this
     repository provides one; install and configure it first.

  3. Signature updates for SpamAssassin and ClamAV run on their own schedules;
     give them time before judging the filtering.

EOT
}

do_remove() {
	require_root

	if pgrep -x perl_mailscanner >/dev/null 2>&1; then
		log "Stopping mailscanner"
		pkill -x perl_mailscanner 2>/dev/null
		sleep 2
	fi

	unregister_gui
	unregister_package
	remove_files
	rm -f "${STAMP}"
	rm -f /usr/local/etc/rc.d/mailscanner

	log "Package removed."
	log "mailscanner itself and ${BIN_ETC} were left in place."
	log "Remove them with: pkg remove -y ${BIN_PKG}"
}

do_status() {
	if [ -f "${STAMP}" ]; then
		echo "Installed: $(cat "${STAMP}")"
	else
		echo "Not installed."
	fi

	bin_installed && echo "binary: $(bin_version)" || echo "binary: not installed"
	pgrep -x perl_mailscanner >/dev/null 2>&1 && echo "mailscanner: running" || echo "mailscanner: stopped"
}

case "${1:-}" in
	check)   do_check ;;
	install) do_install ;;
	remove)  do_remove ;;
	status)  do_status ;;
	*)       echo "Usage: $0 {check|install|remove|status}"; exit 64 ;;
esac
