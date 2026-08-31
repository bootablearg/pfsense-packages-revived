#!/bin/sh
#
# install.sh -- installer for the pfSense "Samba AD" package.
#
# Copyright (c) 2013-2016 Luiz Gustavo S. Costa <me@luizgustavo.pro.br>
# Copyright (c) 2026 pfsense-packages-revived contributors
# All rights reserved.
#
# Derived from the pf2ad project (BSD 2-Clause), branch 2.4.3-SAMBA4.
# See LICENSE for the full license text.
#
# Usage, from a clone:
#   ./install.sh check     Report what would happen. Changes nothing.
#   ./install.sh install   Install Samba, the package files and the GUI entry.
#   ./install.sh remove    Leave the domain, unregister and remove the files.
#   ./install.sh status    Show current state.
#
# Or straight from the network, without cloning:
#   fetch -q -o - https://raw.githubusercontent.com/bootablearg/pfsense-packages-revived/main/samba-ad/install.sh | sh -s check
#   fetch -q -o - https://raw.githubusercontent.com/bootablearg/pfsense-packages-revived/main/samba-ad/install.sh | sh -s install
#
# How this differs from the script it replaces:
#
#   * No hardcoded release. The original refused to run unless /etc/version
#     matched one exact string, which is why it broke the day the next release
#     shipped. This detects product, release and ABI at runtime.
#   * No download key and no vendor endpoint. Samba comes from the official
#     FreeBSD package repository; the package files come from this checkout.
#   * The extra repository is never written into the firewall's own pkg
#     configuration. It lives in a temporary REPOS_DIR that is used only for
#     the duration of the install, so an interrupted run cannot leave a
#     third-party repository enabled behind your back. The original wrote into
#     /usr/local/etc/pkg/repos and deleted it afterwards -- if it died in the
#     middle, the repository stayed active.
#   * If Samba cannot be found or installed, the script stops before touching
#     anything else rather than half-configuring the system.

set -u

# Where this script is running from.
#
# When piped straight from the network ("fetch -o - ... | sh -s install") there
# is no script directory at all, so this is left empty and the package files
# are fetched from SAMBA_AD_SRC_URL instead. Running from a clone uses the
# local files and needs no network access for them.
SCRIPT_DIR=""
case "$0" in
	*/*) SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)" ;;
esac

PKG_SRC_DIR=""
if [ -n "${SCRIPT_DIR}" ] && [ -d "${SCRIPT_DIR}/pkg" ]; then
	PKG_SRC_DIR="${SCRIPT_DIR}/pkg"
fi

# Samba package to install. Newest branch by default; override to pin, e.g.
#   SAMBA_PKG=samba423 ./install.sh install
SAMBA_PKG="${SAMBA_PKG:-}"

# Where package files are fetched from when they are not present locally.
# Override to install from your own fork or branch.
SAMBA_AD_SRC_URL="${SAMBA_AD_SRC_URL:-https://raw.githubusercontent.com/bootablearg/pfsense-packages-revived/main/samba-ad}"

# Official FreeBSD repository. ${ABI} is expanded by pkg itself, not by the
# shell, which is why it is written literally here.
SAMBA_AD_REPO_URL="${SAMBA_AD_REPO_URL:-pkg+https://pkg.freebsd.org/\${ABI}/latest}"

PKG_DEST="/usr/local/pkg"
WWW_DEST="/usr/local/www"
STAMP="/usr/local/etc/samba_ad.installed"
TMP_REPOS="/tmp/samba_ad_repos.$$"

FILES_PKG="samba_ad.inc samba_ad.xml"
FILES_WWW="diag_samba_ad.php"

# ---------------------------------------------------------------- helpers ---

log()  { echo "==> $*"; }
warn() { echo "WARNING: $*" >&2; }
err()  { echo "ERROR: $*" >&2; cleanup_repos; exit 1; }

cleanup_repos() {
	[ -d "${TMP_REPOS}" ] && rm -rf "${TMP_REPOS}"
	return 0
}

# Always clean up the temporary repository directory, however we exit.
trap cleanup_repos EXIT INT TERM

require_root() {
	if [ "$(id -u)" != "0" ]; then
		err "This script must be run as root."
	fi
}

# Product name, "pfSense" or "pfSense Plus".
#
# Asking PHP for $g['product_name'] is authoritative: it is the same value the
# GUI uses. The /etc/version pattern is only a fallback.
detect_product() {
	_p=""

	if [ -x /usr/local/bin/php ]; then
		_p=$(/usr/local/bin/php -r \
			'require_once("globals.inc"); echo $g["product_name"] ?? "";' \
			2>/dev/null | tr -d '\r\n')
	fi

	if [ -n "${_p}" ]; then
		echo "${_p}"
		return
	fi

	case "$(cat /etc/version 2>/dev/null)" in
		2.*)                    echo "pfSense" ;;
		[0-9][0-9].[0-9][0-9]*) echo "pfSense Plus" ;;
		*)                      echo "unknown" ;;
	esac
}

detect_version() { cat /etc/version 2>/dev/null || echo "unknown"; }
detect_abi()     { pkg config abi 2>/dev/null || echo "unknown"; }

samba_binaries_present() {
	[ -x /usr/local/sbin/winbindd ] && [ -x /usr/local/bin/net ]
}

installed_samba_pkg() {
	pkg info -q 2>/dev/null | grep -E '^samba[0-9]+-' | head -1
}

# Build a temporary pkg configuration that keeps the firewall's own
# repositories and adds the FreeBSD one alongside them.
prepare_repos() {
	mkdir -p "${TMP_REPOS}" || err "Could not create ${TMP_REPOS}"

	# Copy the existing repository definitions so pkg still prefers pfSense
	# packages where both repositories provide the same dependency.
	if [ -d /usr/local/etc/pkg/repos ]; then
		cp /usr/local/etc/pkg/repos/*.conf "${TMP_REPOS}/" 2>/dev/null || true
	fi

	printf 'FreeBSD-ports: { url: "%s", mirror_type: "srv", enabled: yes }\n' \
		"${SAMBA_AD_REPO_URL}" > "${TMP_REPOS}/samba_ad_ports.conf"
}

# pkg wrapper bound to the temporary configuration.
#
# IGNORE_OSVERSION is required: pfSense tracks a FreeBSD snapshot slightly
# behind the one the official packages are built against, so pkg refuses the
# repository by default even though the ABI matches. Verified working on
# pfSense CE 2.9.0 (userland 1600018) with packages built for 1600020.
tpkg() {
	IGNORE_OSVERSION=yes pkg -o REPOS_DIR="${TMP_REPOS}" "$@"
}

# Newest available samba4xx, or empty if none.
find_samba_pkg() {
	tpkg search -q '^samba[0-9]' 2>/dev/null \
		| sed 's/-[0-9].*$//' \
		| sort -Vr \
		| head -1
}

# ------------------------------------------------------------ file layout ---

install_one_file() {
	_name="$1"
	_dest="$2"

	if [ -n "${PKG_SRC_DIR}" ] && [ -f "${PKG_SRC_DIR}/${_name}" ]; then
		cp -f "${PKG_SRC_DIR}/${_name}" "${_dest}/${_name}"
	elif [ -n "${SAMBA_AD_SRC_URL}" ]; then
		fetch -q -o "${_dest}/${_name}" "${SAMBA_AD_SRC_URL}/pkg/${_name}" \
			|| err "Could not fetch ${_name} from ${SAMBA_AD_SRC_URL}/pkg/${_name}"
	else
		err "Cannot find ${_name}: no local copy and SAMBA_AD_SRC_URL is unset."
	fi

	chmod 0644 "${_dest}/${_name}"
}

install_files() {
	log "Installing package files"
	mkdir -p "${PKG_DEST}" "${WWW_DEST}"

	for _f in ${FILES_PKG}; do install_one_file "${_f}" "${PKG_DEST}"; done
	for _f in ${FILES_WWW}; do install_one_file "${_f}" "${WWW_DEST}"; done
}

remove_files() {
	log "Removing package files"
	for _f in ${FILES_PKG}; do rm -f "${PKG_DEST}/${_f}"; done
	for _f in ${FILES_WWW}; do rm -f "${WWW_DEST}/${_f}"; done
}

# --------------------------------------------------------- GUI registration ---
#
# The original inlined PHP that iterated $config['installedpackages'][...]
# without checking that those keys existed. On PHP 8 that iterates nothing and
# emits a warning, so registration silently did nothing on a clean system.

register_gui() {
	log "Registering menu entry and service"

	/usr/local/sbin/pfSsh.php <<'PHPEOF'
$menu = function_exists('config_get_path')
	? config_get_path('installedpackages/menu', [])
	: ($config['installedpackages']['menu'] ?? []);
if (!is_array($menu)) { $menu = []; }

$found = false;
foreach ($menu as $item) {
	if (isset($item['name']) && $item['name'] === 'Samba AD') { $found = true; break; }
}
if (!$found) {
	$menu[] = [
		'name'    => 'Samba AD',
		'section' => 'Services',
		'url'     => '/pkg_edit.php?xml=samba_ad.xml&id=0',
	];
}

$service = function_exists('config_get_path')
	? config_get_path('installedpackages/service', [])
	: ($config['installedpackages']['service'] ?? []);
if (!is_array($service)) { $service = []; }

$found = false;
foreach ($service as $item) {
	if (isset($item['name']) && $item['name'] === 'sambaad') { $found = true; break; }
}
if (!$found) {
	$service[] = [
		'name'        => 'sambaad',
		'rcfile'      => 'samba_ad.sh',
		'executable'  => 'winbindd',
		'description' => 'Samba AD domain membership (winbindd)',
	];
}

if (function_exists('config_set_path')) {
	config_set_path('installedpackages/menu', $menu);
	config_set_path('installedpackages/service', $service);
} else {
	$config['installedpackages']['menu'] = $menu;
	$config['installedpackages']['service'] = $service;
}

write_config('Samba AD: register package menu and service');
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

$menu = array_values(array_filter($menu, function ($item) {
	return !(isset($item['name']) && $item['name'] === 'Samba AD');
}));

$service = function_exists('config_get_path')
	? config_get_path('installedpackages/service', [])
	: ($config['installedpackages']['service'] ?? []);
if (!is_array($service)) { $service = []; }

$service = array_values(array_filter($service, function ($item) {
	return !(isset($item['name']) && $item['name'] === 'sambaad');
}));

if (function_exists('config_set_path')) {
	config_set_path('installedpackages/menu', $menu);
	config_set_path('installedpackages/service', $service);
} else {
	$config['installedpackages']['menu'] = $menu;
	$config['installedpackages']['service'] = $service;
}

write_config('Samba AD: unregister package');
exec;
exit
PHPEOF
}

run_install_hook() {
	log "Running package install hook"
	/usr/local/sbin/pfSsh.php <<'PHPEOF'
require_once('/usr/local/pkg/samba_ad.inc');
samba_ad_install();
exec;
exit
PHPEOF
}

# Leaves the domain, so the machine account does not linger in the directory.
run_deinstall_hook() {
	if [ -f "${PKG_DEST}/samba_ad.inc" ]; then
		log "Running package deinstall hook (leaves the domain)"
		/usr/local/sbin/pfSsh.php <<'PHPEOF'
require_once('/usr/local/pkg/samba_ad.inc');
samba_ad_deinstall();
exec;
exit
PHPEOF
	fi
}

# ------------------------------------------------------------- subcommands ---

do_check() {
	echo "Product : $(detect_product)"
	echo "Version : $(detect_version)"
	echo "ABI     : $(detect_abi)"
	echo "Kernel  : $(uname -r)"
	echo "PHP     : $(php -v 2>/dev/null | head -1)"

	if samba_binaries_present; then
		echo "Samba   : installed ($(installed_samba_pkg))"
	else
		prepare_repos
		log "Querying repositories (no changes are made)"
		tpkg update >/dev/null 2>&1 || warn "Could not refresh repository catalogues."

		_samba=$(find_samba_pkg)
		if [ -n "${_samba}" ]; then
			echo "Samba   : available as '${_samba}'"
			echo
			echo "Install plan:"
			tpkg install -n "${_samba}" 2>&1 | tail -5
		else
			echo "Samba   : NOT AVAILABLE for ABI $(detect_abi)"
			echo "          See docs/BUILD-samba-poudriere.md for the fallback path."
		fi
		cleanup_repos
	fi

	if [ -d /usr/local/libexec/squid ]; then
		echo "Squid   : installed (optional integration available)"
	else
		echo "Squid   : not installed (not required)"
	fi

	if [ -f "${STAMP}" ]; then
		echo "Package : installed ($(cat "${STAMP}"))"
	else
		echo "Package : not installed"
	fi
}

do_install() {
	require_root

	_product=$(detect_product)
	_version=$(detect_version)
	_abi=$(detect_abi)

	log "Detected ${_product} ${_version} (ABI ${_abi})"

	case "${_product}" in
		"pfSense"|"pfSense Plus") : ;;
		*) warn "Unrecognised product '${_product}'; continuing, but this is untested." ;;
	esac

	if samba_binaries_present; then
		log "Samba already installed ($(installed_samba_pkg)), skipping"
	else
		prepare_repos
		log "Refreshing repository catalogues"
		tpkg update >/dev/null 2>&1 || err "Could not refresh repository catalogues."

		_samba="${SAMBA_PKG}"
		if [ -z "${_samba}" ]; then
			_samba=$(find_samba_pkg)
		fi

		[ -n "${_samba}" ] || err "No samba package available for ABI ${_abi}. Nothing was changed."

		log "Installing ${_samba} (this pulls in Python and can need ~400 MiB)"
		tpkg install -y "${_samba}" || err "Samba installation failed. Nothing else was changed."

		cleanup_repos
	fi

	samba_binaries_present || err "Samba installed but winbindd is missing. Aborting."

	install_files
	register_gui
	run_install_hook

	date "+%Y-%m-%dT%H:%M:%S%z" > "${STAMP}"

	log "Done."
	echo
	echo "Next: open Services > Samba AD in the web GUI, fill in the domain"
	echo "details and enable the service to perform the domain join."
}

do_remove() {
	require_root

	run_deinstall_hook
	unregister_gui
	remove_files

	rm -f "${STAMP}"
	rm -f /usr/local/etc/rc.d/samba_ad.sh

	_samba=$(installed_samba_pkg)
	log "Package removed."
	if [ -n "${_samba}" ]; then
		log "Samba itself was left installed. Remove it with:"
		log "    pkg remove -y ${_samba}"
	fi
}

do_status() {
	if [ -f "${STAMP}" ]; then
		echo "Installed: $(cat "${STAMP}")"
	else
		echo "Not installed."
	fi

	if pgrep -x winbindd >/dev/null 2>&1; then
		echo "winbindd: running"
	else
		echo "winbindd: stopped"
	fi
}

usage() {
	echo "Usage: $0 {check|install|remove|status}"
	exit 64
}

case "${1:-}" in
	check)   do_check ;;
	install) do_install ;;
	remove)  do_remove ;;
	status)  do_status ;;
	*)       usage ;;
esac
