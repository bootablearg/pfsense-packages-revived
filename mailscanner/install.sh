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
# repository, no key. See ../docs/PATTERN.md for the method and its caveats.#
# Packaging: this builds a real pfSense-pkg-* package and installs it from a
# temporary local repository, so it appears under System > Package Manager and
# the trash icon removes it -- files, menu entries, service and all. See
# ../docs/PACKAGING.md for why that indirection is necessary.#
# Packaging: this builds a real pfSense-pkg-* package and installs it from a
# temporary local repository, so it appears under System > Package Manager and
# the trash icon removes it -- files, menu entries, service and all. See
# ../docs/PACKAGING.md for why that indirection is necessary.#
# Packaging: this builds a real pfSense-pkg-* package and installs it from a
# temporary local repository, so it appears under System > Package Manager and
# the trash icon removes it -- files, menu entries, service and all. See
# ../docs/PACKAGING.md for why that indirection is necessary.#
# Packaging: this builds a real pfSense-pkg-* package and installs it from a
# temporary local repository, so it appears under System > Package Manager and
# the trash icon removes it -- files, menu entries, service and all. See
# ../docs/PACKAGING.md for why that indirection is necessary.#
# Packaging: this builds a real pfSense-pkg-* package and installs it from a
# temporary local repository, so it appears under System > Package Manager and
# the trash icon removes it -- files, menu entries, service and all. See
# ../docs/PACKAGING.md for why that indirection is necessary.#
# Packaging: this builds a real pfSense-pkg-* package and installs it from a
# temporary local repository, so it appears under System > Package Manager and
# the trash icon removes it -- files, menu entries, service and all. See
# ../docs/PACKAGING.md for why that indirection is necessary.#
# Packaging: this builds a real pfSense-pkg-* package and installs it from a
# temporary local repository, so it appears under System > Package Manager and
# the trash icon removes it -- files, menu entries, service and all. See
# ../docs/PACKAGING.md for why that indirection is necessary.#
# Packaging: this builds a real pfSense-pkg-* package and installs it from a
# temporary local repository, so it appears under System > Package Manager and
# the trash icon removes it -- files, menu entries, service and all. See
# ../docs/PACKAGING.md for why that indirection is necessary.#
# Packaging: this builds a real pfSense-pkg-* package and installs it from a
# temporary local repository, so it appears under System > Package Manager and
# the trash icon removes it -- files, menu entries, service and all. See
# ../docs/PACKAGING.md for why that indirection is necessary.#
# Packaging: this builds a real pfSense-pkg-* package and installs it from a
# temporary local repository, so it appears under System > Package Manager and
# the trash icon removes it -- files, menu entries, service and all. See
# ../docs/PACKAGING.md for why that indirection is necessary.#
# Packaging: this builds a real pfSense-pkg-* package and installs it from a
# temporary local repository, so it appears under System > Package Manager and
# the trash icon removes it -- files, menu entries, service and all. See
# ../docs/PACKAGING.md for why that indirection is necessary.#
# Packaging: this builds a real pfSense-pkg-* package and installs it from a
# temporary local repository, so it appears under System > Package Manager and
# the trash icon removes it -- files, menu entries, service and all. See
# ../docs/PACKAGING.md for why that indirection is necessary.#
# Packaging: this builds a real pfSense-pkg-* package and installs it from a
# temporary local repository, so it appears under System > Package Manager and
# the trash icon removes it -- files, menu entries, service and all. See
# ../docs/PACKAGING.md for why that indirection is necessary.

set -u

# ------------------------------------------------------------------ package --
# Everything specific to this package lives in this block. The rest of the
# script is identical across every package in the repository.

PKG_SHORT="MailScanner"			# -> pfSense-pkg-MailScanner
PKG_TITLE="MailScanner"			# name shown in the Package Manager
PKG_VERSION="1.1.0"
PKG_CATEGORY="mail"
PKG_LICENSE="APACHE20"
PKG_COMMENT="Mail filtering with SpamAssassin and ClamAV"
PKG_DESCR="Wraps SpamAssassin and ClamAV into a mail-filtering gateway; needs an MTA underneath, such as the postfix package."
PKG_CONFIGFILE="mailscanner.xml"
SRC_DIRNAME="mailscanner"

# FreeBSD packages this one needs. Installed first, from FreeBSD's official
# repository, then recorded as dependencies of our package so that removing
# ours takes them with it.
BIN_DEPS="MailScanner"

# "no" for a package that needs nothing beyond what pfSense already ships, so
# an empty BIN_DEPS is a fact rather than a failed lookup.
DEPS_REQUIRED="yes"

# Names this package used in earlier versions of this repository. Their stale
# config.xml entries are purged on install so the Package Manager does not end
# up listing the same package twice.
LEGACY_NAMES="mailscanner"

FILES_PKG="mailscanner.conf.template mailscanner.inc mailscanner.xml
	mailscanner_alerts.xml mailscanner_antispam.xml
	mailscanner_antivirus.xml mailscanner_attachments.xml
	mailscanner_content.xml mailscanner_report.xml mailscanner_sync.xml"
FILES_WWW="mailscanner_about.php shortcuts/pkg_mailscanner.inc"
FILES_PRIV="mailscanner.priv.inc"
FILES_BIN="sa-updater-custom-channels.sh sa-wrapper.pl"

# --------------------------------------------------------------- constants ---

PKG_FULL="pfSense-pkg-${PKG_SHORT}"
SRC_URL="${SRC_URL:-https://raw.githubusercontent.com/bootablearg/pfsense-packages-revived/main/${SRC_DIRNAME}}"

# ${ABI} must reach pkg literally -- pkg expands it, the shell must not.
# Nesting it inside ${VAR:-default} makes sh swallow the closing brace and
# yields ".../${ABI/latest}", a repository URL that never resolves. The bug
# only surfaces when the binary is not already installed, which is exactly the
# case this script exists for.
REPO_URL="${REPO_URL:-}"
[ -n "${REPO_URL}" ] || REPO_URL='pkg+https://pkg.freebsd.org/${ABI}/latest'

WORK="/tmp/${SRC_DIRNAME}_build.$$"
STAGE="${WORK}/stage"
REPO="${WORK}/repo"
REPOS_D="${WORK}/repos"
REPOS_L="${WORK}/repos_local"

SCRIPT_DIR=""
case "$0" in
	*/*) SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)" ;;
esac
SRC_LOCAL=""
if [ -n "${SCRIPT_DIR}" ] && [ -d "${SCRIPT_DIR}/pkg" ]; then
	SRC_LOCAL="${SCRIPT_DIR}"
fi

# ----------------------------------------------------------------- helpers ---

log()  { echo "==> $*"; }
warn() { echo "WARNING: $*" >&2; }
err()  { echo "ERROR: $*" >&2; cleanup; exit 1; }

cleanup() {
	[ -n "${WORK}" ] && [ -d "${WORK}" ] && rm -rf "${WORK}"
	return 0
}
trap cleanup EXIT INT TERM

require_root() {
	[ "$(id -u)" = "0" ] || err "This script must be run as root."
}

detect_product() {
	_p=""
	if [ -r /etc/platform ]; then
		_p="$(cat /etc/platform 2>/dev/null)"
	fi
	if [ -z "${_p}" ] && [ -r /etc/inc/globals.inc ]; then
		_p="$(grep -o "'product_name' *=> *'[^']*'" /etc/inc/globals.inc 2>/dev/null \
			| head -1 | sed "s/.*=> *'//;s/'$//")"
	fi
	[ -n "${_p}" ] && { echo "${_p}"; return; }

	case "$(cat /etc/version 2>/dev/null)" in
		2.*)                    echo "pfSense" ;;
		[0-9][0-9].[0-9][0-9]*) echo "pfSense Plus" ;;
		*)                      echo "unknown" ;;
	esac
}

# pfSense tracks a FreeBSD snapshot older than the one the official packages
# are built against, so pkg refuses the repository without IGNORE_OSVERSION.
# The firewall's own repository files are never modified: everything happens in
# a temporary REPOS_DIR, so an interrupted run cannot leave a foreign repo
# enabled on the box.
tpkg() {
	IGNORE_OSVERSION=yes pkg -o REPOS_DIR="${REPOS_D}" "$@"
}

prepare_repos() {
	mkdir -p "${REPOS_D}" || err "Could not create ${REPOS_D}"
	if [ -d /usr/local/etc/pkg/repos ]; then
		cp /usr/local/etc/pkg/repos/*.conf "${REPOS_D}/" 2>/dev/null || true
	fi
	# The file name matters. pkg reads this directory in alphabetical order
	# and the last definition of a repository wins -- and pfSense ships
	# /usr/local/etc/pkg/repos/FreeBSD.conf containing
	#     FreeBSD-ports: { enabled: no }
	# which we have just copied in. Anything sorting before "FreeBSD.conf"
	# gets silently overridden and the repository stays disabled, so this
	# has to sort after every file pfSense ships.
	printf 'FreeBSD-ports: { url: "%s", mirror_type: "srv", enabled: yes }\n' \
		"${REPO_URL}" > "${REPOS_D}/zz_ports.conf"

	# Fail loudly rather than reporting "no packages available" later, which
	# reads like the package does not exist for this ABI when in fact the
	# repository was never consulted.
	if ! tpkg -vv 2>/dev/null | awk '/^  FreeBSD-ports: \{/,/^  \}/' \
		| grep -q 'enabled *: *yes'; then
		err "The FreeBSD-ports repository is disabled in ${REPOS_D}. Another file there overrides it."
	fi
}

# The repository entry MUST be named "pfSense".
#
# pkg_mgr_installed.php lists a package only when `pkg query %R` returns the
# product name; anything else is skipped without a message. A package added
# with `pkg add` reports "unknown-repository" and is therefore invisible in
# System > Package Manager, however correct the rest of it is. Installing it
# from a local repository called "pfSense" is what makes it show up.
#
# It gets a REPOS_DIR of its own rather than joining the one used for the
# dependencies: that one holds a copy of the firewall's real pfSense repository
# definition, which carries the same name and silently wins. Nothing else is
# needed here -- by the time this runs the dependencies are already installed.
add_local_repo() {
	mkdir -p "${REPOS_L}"
	printf 'pfSense: { url: "file://%s", enabled: yes, mirror_type: "none" }\n' \
		"${REPO}" > "${REPOS_L}/local.conf"
}

lpkg() { pkg -o REPOS_DIR="${REPOS_L}" "$@"; }

pkg_present() { pkg info -e "$1" >/dev/null 2>&1; }

# Resolves BIN_DEPS to the concrete package names to install. Most packages
# have a fixed name and this just echoes it back; the override exists for
# packages whose upstream name carries a version, such as Samba.
resolve_bin_deps() { echo "${BIN_DEPS}"; }

fetch_one() {
	# fetch_one <relative path> <source subdir> <destination root>
	_rel="$1"; _sub="$2"; _root="$3"
	mkdir -p "${_root}/$(dirname "${_rel}")"
	if [ -n "${SRC_LOCAL}" ] && [ -f "${SRC_LOCAL}/${_sub}/${_rel}" ]; then
		cp -f "${SRC_LOCAL}/${_sub}/${_rel}" "${_root}/${_rel}"
	else
		fetch -q -o "${_root}/${_rel}" "${SRC_URL}/${_sub}/${_rel}" \
			|| err "Could not fetch ${_sub}/${_rel} from ${SRC_URL}"
	fi
}

# ------------------------------------------------------------ dependencies ---

deps_missing() {
	_m=""
	for _d in ${BIN_DEPS}; do
		pkg_present "${_d}" || _m="${_m} ${_d}"
	done
	echo "${_m}"
}

install_deps() {
	_missing="$(deps_missing)"
	[ -z "${_missing}" ] && { log "Dependencies already present:${BIN_DEPS:+ ${BIN_DEPS}}"; return 0; }

	log "Installing from the FreeBSD repository:${_missing}"
	# shellcheck disable=SC2086
	tpkg install -y ${_missing} || err "Installation of${_missing} failed. Nothing else was changed."

	# Mark only what we just installed as automatic, so that removing this
	# package takes it away again. Anything that was already on the box stays
	# explicitly installed -- it may be there for reasons of its own, and
	# silently making somebody else's package removable would be rude.
	for _d in ${_missing}; do
		pkg set -y -A 1 "${_d}" >/dev/null 2>&1 || true
	done
}

# ------------------------------------------------------------------ build ----

stage_files() {
	log "Staging package files"
	mkdir -p "${STAGE}/usr/local/pkg" "${STAGE}/usr/local/www" \
		"${STAGE}/usr/local/share/${PKG_FULL}" \
		"${STAGE}/usr/local/share/licenses/${PKG_FULL}-${PKG_VERSION}"

	for _f in ${FILES_PKG};  do fetch_one "${_f}" pkg  "${STAGE}/usr/local/pkg";  done
	for _f in ${FILES_WWW};  do fetch_one "${_f}" www  "${STAGE}/usr/local/www";  done
	for _f in ${FILES_PRIV}; do fetch_one "${_f}" priv "${STAGE}/etc/inc/priv";   done
	for _f in ${FILES_BIN};  do fetch_one "${_f}" bin  "${STAGE}/usr/local/bin";  done

	if [ -n "${SRC_LOCAL}" ] && [ -f "${SRC_LOCAL}/LICENSE" ]; then
		cp -f "${SRC_LOCAL}/LICENSE" \
			"${STAGE}/usr/local/share/licenses/${PKG_FULL}-${PKG_VERSION}/LICENSE"
	else
		fetch -q -o "${STAGE}/usr/local/share/licenses/${PKG_FULL}-${PKG_VERSION}/LICENSE" \
			"${SRC_URL}/LICENSE" || true
	fi

	find "${STAGE}" -type f -exec chmod 0644 {} +
	for _f in ${FILES_BIN}; do chmod 0755 "${STAGE}/usr/local/bin/${_f}"; done
}

# info.xml is what pfSense reads after installing the package: it maps the
# package to its GUI definition, and its contents become the config.xml entry.
write_info_xml() {
	cat > "${STAGE}/usr/local/share/${PKG_FULL}/info.xml" <<INFOEOF
<?xml version="1.0"?>
<pfsensepkgs>
	<package>
		<name>${PKG_TITLE}</name>
		<internal_name>${PKG_SHORT}</internal_name>
		<descr><![CDATA[${PKG_DESCR}]]></descr>
		<version>${PKG_VERSION}</version>
		<configurationfile>${PKG_CONFIGFILE}</configurationfile>
	</package>
</pfsensepkgs>
INFOEOF
}

# The dependency list is built from what is actually installed rather than
# hard-coded, so the manifest can never disagree with the box it is built on.
manifest_deps() {
	_out=""
	for _d in ${BIN_DEPS}; do
		_v="$(pkg query %v "${_d}" 2>/dev/null)"
		_o="$(pkg query %o "${_d}" 2>/dev/null)"
		[ -n "${_v}" ] && [ -n "${_o}" ] || continue
		_out="${_out}  ${_d}: { origin: \"${_o}\", version: \"${_v}\" }
"
	done
	[ -n "${_out}" ] && printf 'deps: {\n%s}\n' "${_out}"
}

# These two scripts are the whole reason the package integrates properly:
# pkg runs them, they hand control to /etc/rc.packages, and pfSense then
# registers or tears down the menu entries, services and config.xml entry.
# This is verbatim the mechanism Netgate's own packages use.
write_manifest() {
	{
		echo "name: ${PKG_FULL}"
		echo "version: \"${PKG_VERSION}\""
		echo "origin: ${PKG_CATEGORY}/${PKG_FULL}"
		echo "comment: \"${PKG_COMMENT}\""
		echo "desc: \"${PKG_DESCR}\""
		echo "maintainer: \"noreply@github.com\""
		echo "www: \"https://github.com/bootablearg/pfsense-packages-revived\""
		echo "prefix: /usr/local"
		echo "categories: [ ${PKG_CATEGORY} ]"
		case "${PKG_LICENSE}" in
			*,*) echo "licenselogic: multi" ;;
			*)   echo "licenselogic: single" ;;
		esac
		echo "licenses: [ ${PKG_LICENSE} ]"
		manifest_deps
		echo "scripts: {"
		echo "  install: \"#!/bin/sh\\nif [ \\\"\\\${2}\\\" != \\\"POST-INSTALL\\\" ]; then exit 0; fi\\n/usr/local/bin/php -f /etc/rc.packages ${PKG_FULL} \\\${2}\\n\""
		echo "  deinstall: \"#!/bin/sh\\n/usr/local/bin/php -f /etc/rc.packages ${PKG_FULL} \\\${2}\\n\""
		echo "}"
	} > "${WORK}/manifest"
}

write_plist() {
	( cd "${STAGE}" && find . -type f | sed 's|^\.||' ) | sort > "${WORK}/plist"
}

build_pkg() {
	log "Building ${PKG_FULL}-${PKG_VERSION}"
	mkdir -p "${REPO}"
	pkg create -M "${WORK}/manifest" -r "${STAGE}" -p "${WORK}/plist" -o "${REPO}" \
		>/dev/null 2>&1 || err "pkg create failed."

	# `pkg repo` needs a libc symbol the pfSense base system does not export;
	# pkg-static is linked against its own copy and works. Using the dynamic
	# pkg here fails with: Undefined symbol "fts_open@FBSD_1.9"
	pkg-static repo "${REPO}" >/dev/null 2>&1 || err "Could not build the local repository catalogue."
}

# ------------------------------------------------------------- config.xml ----

# Remove config.xml entries left by the pre-packaging versions of this
# installer. Menus and services are left alone: install_package_xml() skips
# duplicates, so it will reconcile them on its own.
purge_legacy() {
	[ -n "${LEGACY_NAMES}" ] || return 0
	_names=""
	for _n in ${LEGACY_NAMES}; do _names="${_names}'${_n}',"; done

	/usr/local/sbin/pfSsh.php >/dev/null 2>&1 <<LEGACYEOF
\$legacy = [${_names}];
\$pkgs = config_get_path('installedpackages/package', []);
if (!is_array(\$pkgs)) { \$pkgs = []; }
\$before = count(\$pkgs);
\$pkgs = array_values(array_filter(\$pkgs, function (\$p) use (\$legacy) {
	return !(isset(\$p['name']) && in_array(\$p['name'], \$legacy, true));
}));
if (count(\$pkgs) !== \$before) {
	config_set_path('installedpackages/package', \$pkgs);
	write_config('${PKG_TITLE}: remove superseded package registration');
}
exec
exit
LEGACYEOF
	return 0
}

# A package's services cannot be started from inside its own pkg install
# script. pkg makes itself the reaper of that script's process tree and kills
# everything still in it when the script returns -- daemonising does not help,
# because a reaper follows reparented children too. The daemon starts, reports
# itself healthy, and is SIGKILLed a second later with nothing in any log to
# say why.
#
# So the configuration sync is run once more here, after pkg has finished and
# let go. It is the same code path the GUI uses when the settings page is
# saved, and it is what actually brings the service up.
start_services() {
	php -r 'require_once("config.inc"); require_once("pkg-utils.inc");
	        $GLOBALS["pkg_interface"] = "console";
	        sync_package("'"${PKG_SHORT}"'");' >/dev/null 2>&1 || true
}

# ------------------------------------------------------------------ verbs ----

show_env() {
	echo "Product:      $(detect_product)"
	echo "Version:      $(cat /etc/version 2>/dev/null || echo unknown)"
	echo "ABI:          $(pkg config abi 2>/dev/null || echo unknown)"
	echo "PHP:          $(php -v 2>/dev/null | head -1 | awk '{print $2}')"
}

cmd_status() {
	show_env
	echo
	BIN_DEPS="$(resolve_bin_deps offline)"
	if pkg_present "${PKG_FULL}"; then
		echo "${PKG_FULL}: installed ($(pkg query %v "${PKG_FULL}"), repository $(pkg query %R "${PKG_FULL}"))"
	else
		echo "${PKG_FULL}: not installed"
	fi
	for _d in ${BIN_DEPS}; do
		if pkg_present "${_d}"; then
			echo "${_d}: $(pkg query %v "${_d}")"
		else
			echo "${_d}: not installed"
		fi
	done
}

cmd_check() {
	require_root
	show_env
	echo
	prepare_repos
	BIN_DEPS="$(resolve_bin_deps)"
	if [ "${DEPS_REQUIRED}" = "yes" ] && [ -z "${BIN_DEPS}" ]; then
		err "No suitable dependency package is available for ABI $(pkg config abi 2>/dev/null)."
	fi
	_missing="$(deps_missing)"
	if [ -z "${_missing}" ]; then
		echo "Dependencies: all present (${BIN_DEPS})"
	else
		echo "Would install from the FreeBSD repository:${_missing}"
		# shellcheck disable=SC2086
		tpkg install -n ${_missing} 2>&1 | tail -8
	fi
	echo
	echo "Would build and install ${PKG_FULL}-${PKG_VERSION}"
	echo "  package files: $(echo ${FILES_PKG} | wc -w | tr -d ' ')"
	echo "  GUI files:     $(echo ${FILES_WWW} | wc -w | tr -d ' ')"
	echo "  privileges:    $(echo ${FILES_PRIV} | wc -w | tr -d ' ')"
	echo "  helpers:       $(echo ${FILES_BIN} | wc -w | tr -d ' ')"
	echo
	echo "Nothing was changed."
}

cmd_install() {
	require_root
	[ -x /usr/local/sbin/pfSsh.php ] || err "This does not look like a pfSense system."

	prepare_repos
	BIN_DEPS="$(resolve_bin_deps)"
	if [ "${DEPS_REQUIRED}" = "yes" ] && [ -z "${BIN_DEPS}" ]; then
		err "No suitable dependency package is available for ABI $(pkg config abi 2>/dev/null)."
	fi
	install_deps

	stage_files
	write_info_xml
	write_manifest
	write_plist
	build_pkg

	purge_legacy

	log "Installing ${PKG_FULL}"
	add_local_repo
	# The install script inside the package calls /etc/rc.packages, which
	# registers the menu, the service and the config.xml entry.
	# -f, because the package is rebuilt from the current sources on every
	# run: without it pkg sees the same version number, decides there is
	# nothing to do, and silently keeps the old files. Only this package is
	# forced -- that needs -ff to reach dependencies.
	#
	# Forcing means pkg deinstalls the old copy first, so the package's own
	# deinstall hook runs even though this is a repair rather than a removal.
	# The marker lets a hook tell the two apart: samba-ad, for one, must not
	# leave the Active Directory domain just because somebody reinstalled it.
	_reinstall_flag="/tmp/.${PKG_FULL}.reinstall"
	if pkg_present "${PKG_FULL}"; then
		: > "${_reinstall_flag}"
	fi
	lpkg install -y -f "${PKG_FULL}" 2>&1 | tee "${WORK}/install.log"
	rm -f "${_reinstall_flag}"
	pkg_present "${PKG_FULL}" || err "${PKG_FULL} did not install."

	# pkg exits 0 even when a package's own POST-INSTALL script blows up, and
	# that script is what registers the GUI. Without this check the installer
	# would cheerfully report success on a package with no menu entry.
	if grep -q 'script failed' "${WORK}/install.log"; then
		warn "The package's POST-INSTALL script reported a failure."
	fi
	if ! php -r 'require_once("config.inc"); require_once("pkg-utils.inc"); exit(is_package_installed("'"${PKG_SHORT}"'") ? 0 : 1);' 2>/dev/null; then
		err "${PKG_FULL} installed but did not register with pfSense. See the output above."
	fi

	start_services

	echo
	log "Done."
	echo
	echo "  ${PKG_TITLE} is installed and listed under"
	echo "  System > Package Manager > Installed Packages,"
	echo "  where the trash icon removes it like any other package."
}

cmd_remove() {
	require_root
	if pkg_present "${PKG_FULL}"; then
		log "Removing ${PKG_FULL}"
		# pkg runs the deinstall script, which lets pfSense tear down the
		# menu, the service and the config.xml entry before the files go.
		pkg delete -y "${PKG_FULL}" || err "Removal failed."
		pkg autoremove -y >/dev/null 2>&1 || true
		log "Removed."
	else
		warn "${PKG_FULL} is not installed."
		purge_legacy
	fi
}

usage() {
	cat <<USAGEEOF
Usage: $0 {check|install|remove|status}

  check     Report what would happen. Changes nothing.
  install   Build and install ${PKG_FULL}.
  remove    Remove the package and anything it pulled in.
  status    Show the current state.
USAGEEOF
}

case "${1:-}" in
	check)   cmd_check ;;
	install) cmd_install ;;
	remove)  cmd_remove ;;
	status)  cmd_status ;;
	*)       usage; exit 1 ;;
esac
