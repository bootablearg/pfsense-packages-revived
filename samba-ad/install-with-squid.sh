#!/bin/sh
#
# install-with-squid.sh -- Samba AD domain membership *plus* the Squid proxy,
# wired together so Squid authenticates users against Active Directory with
# single sign-on.
#
# Copyright (c) 2013-2016 Luiz Gustavo S. Costa <me@luizgustavo.pro.br>
# Copyright (c) 2026 pfsense-packages-revived contributors
# All rights reserved.
#
# Derived from the pf2ad project (BSD 2-Clause), branch 2.4.3-SAMBA4.
# See LICENSE for the full license text.
#
# This is install.sh plus Squid. If you only want the firewall joined to the
# domain, use install.sh instead -- it does not touch Squid at all.
#
# Usage, from a clone:
#   ./install-with-squid.sh check     Report what would happen. Changes nothing.
#   ./install-with-squid.sh install   Install everything and wire up auth.
#   ./install-with-squid.sh remove    Undo the Squid changes and the AD package.
#   ./install-with-squid.sh status    Show current state.
#
# Or straight from the network:
#   fetch -q -o - https://raw.githubusercontent.com/bootablearg/pfsense-packages-revived/main/samba-ad/install-with-squid.sh | sh -s install
#
# What it adds on top of install.sh:
#
#   * Installs pfSense-pkg-squid if it is not already present.
#   * Symlinks Samba's ntlm_auth into Squid's helper directory.
#   * Adds an "Active Directory (Samba winbind SSO)" entry to Squid's
#     Authentication Method dropdown, so domain-joined browsers get single
#     sign-on instead of a username/password prompt.
#
# Adding that entry means editing two files belonging to the Squid package: the
# dropdown lives in squid_auth.xml and the directives for each method are
# produced by a switch in squid.inc. There is no supported hook for adding a
# method, so there is no way around it.
#
# The original pf2ad did the same thing with a unified diff guarded by a
# hardcoded MD5 of one exact Squid build: any update changed the MD5, the patch
# was skipped or misapplied, and the proxy quietly stopped authenticating.
# pkg/squid_ad_patch.php instead locates its anchors by content, is idempotent,
# marks what it inserted so it can be removed cleanly, keeps backups, and can
# report whether it is currently applied.
#
# IMPORTANT: updating or reinstalling the Squid package restores Squid's own
# files and removes the patch. Re-run this script afterwards. Run 'check' at any
# time to see whether the patch is still in place.

set -u

SCRIPT_DIR=""
case "$0" in
	*/*) SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)" ;;
esac

SAMBA_AD_SRC_URL="${SAMBA_AD_SRC_URL:-https://raw.githubusercontent.com/bootablearg/pfsense-packages-revived/main/samba-ad}"

SQUID_PKG="pfSense-pkg-squid"
SQUID_HELPER_DIR="/usr/local/libexec/squid"
SQUID_HELPER="${SQUID_HELPER_DIR}/ntlm_auth"
SAMBA_NTLM_AUTH="/usr/local/bin/ntlm_auth"

PATCHER_NAME="squid_ad_patch.php"
PATCHER_DEST="/usr/local/pkg/${PATCHER_NAME}"

log()  { echo "==> $*"; }
warn() { echo "WARNING: $*" >&2; }
err()  { echo "ERROR: $*" >&2; exit 1; }

require_root() {
	[ "$(id -u)" = "0" ] || err "This script must be run as root."
}

squid_installed() { pkg info -e "${SQUID_PKG}" 2>/dev/null; }
samba_ad_installed() { [ -f /usr/local/pkg/samba_ad.inc ]; }

# Run install.sh, from this directory if present, otherwise from the repository.
run_base_installer() {
	_action="$1"

	if [ -n "${SCRIPT_DIR}" ] && [ -f "${SCRIPT_DIR}/install.sh" ]; then
		sh "${SCRIPT_DIR}/install.sh" "${_action}"
	else
		log "Fetching install.sh from ${SAMBA_AD_SRC_URL}"
		fetch -q -o - "${SAMBA_AD_SRC_URL}/install.sh" | sh -s "${_action}" \
			|| err "The base installer failed. Nothing further was changed."
	fi
}

# Put the patcher on the firewall, so it can be re-run after a Squid update
# without needing this repository again.
install_patcher() {
	if [ -n "${SCRIPT_DIR}" ] && [ -f "${SCRIPT_DIR}/pkg/${PATCHER_NAME}" ]; then
		cp -f "${SCRIPT_DIR}/pkg/${PATCHER_NAME}" "${PATCHER_DEST}"
	else
		fetch -q -o "${PATCHER_DEST}" "${SAMBA_AD_SRC_URL}/pkg/${PATCHER_NAME}" \
			|| err "Could not fetch ${PATCHER_NAME}."
	fi

	chmod 0644 "${PATCHER_DEST}"
}

patcher_available() { [ -f "${PATCHER_DEST}" ]; }

install_squid() {
	if squid_installed; then
		log "Squid already installed, skipping"
		return 0
	fi

	log "Installing ${SQUID_PKG}"
	ASSUME_ALWAYS_YES=YES pkg install -y "${SQUID_PKG}" \
		|| err "Could not install ${SQUID_PKG}."
}

link_helper() {
	[ -d "${SQUID_HELPER_DIR}" ] || err "${SQUID_HELPER_DIR} missing: is Squid really installed?"
	[ -x "${SAMBA_NTLM_AUTH}" ]  || err "${SAMBA_NTLM_AUTH} missing: is Samba really installed?"

	# A symlink, not a copy: a copy goes stale the moment Samba is updated, and
	# a stale helper against a newer winbindd fails in ways that look like a
	# domain problem rather than a file problem.
	if [ -L "${SQUID_HELPER}" ] || [ -e "${SQUID_HELPER}" ]; then
		rm -f "${SQUID_HELPER}"
	fi

	ln -s "${SAMBA_NTLM_AUTH}" "${SQUID_HELPER}" \
		|| err "Could not link ntlm_auth into ${SQUID_HELPER_DIR}."

	log "Linked ntlm_auth into Squid's helper directory"
}

verify_helper() {
	if [ ! -e "${SQUID_HELPER}" ]; then
		warn "${SQUID_HELPER} is not present."
		return 1
	fi

	if ! pgrep -x winbindd >/dev/null 2>&1; then
		warn "winbindd is not running: join the domain from Services > Samba AD first."
		return 1
	fi

	return 0
}

do_check() {
	echo "=== Samba AD ==="
	run_base_installer check

	echo
	echo "=== Squid ==="
	if squid_installed; then
		echo "Squid      : installed ($(pkg query '%n-%v' "${SQUID_PKG}" 2>/dev/null))"
	else
		echo "Squid      : not installed (would be installed)"
	fi

	if [ -L "${SQUID_HELPER}" ]; then
		echo "ntlm_auth  : linked into Squid"
	else
		echo "ntlm_auth  : not linked (would be linked)"
	fi

	echo
	echo "=== Authentication Method patch ==="
	if patcher_available; then
		php "${PATCHER_DEST}" status || true
	elif [ -n "${SCRIPT_DIR}" ] && [ -f "${SCRIPT_DIR}/pkg/${PATCHER_NAME}" ]; then
		php "${SCRIPT_DIR}/pkg/${PATCHER_NAME}" status || true
	else
		echo "  patcher not installed yet (would be installed)"
	fi
}

do_install() {
	require_root

	log "Step 1/5: Samba AD"
	run_base_installer install

	samba_ad_installed || err "The Samba AD package did not install. Stopping before touching Squid."

	log "Step 2/5: Squid"
	install_squid

	log "Step 3/5: linking the authentication helper"
	link_helper

	log "Step 4/5: installing the Authentication Method patcher"
	install_patcher

	log "Step 5/5: adding Active Directory to the Authentication Method dropdown"
	if ! php "${PATCHER_DEST}" apply; then
		warn "The dropdown patch did not apply. Squid still works, but the"
		warn "Active Directory option will not appear. See the README for the"
		warn "manual custom-options method."
	fi

	verify_helper || true

	log "Done."
	cat <<'EOT'

Next steps, in this order:

  1. Services > Samba AD -- fill in the domain details and enable the service
     to join the domain. Nothing below works until "Join is OK".

  2. Services > Squid Proxy Server > General -- enable the proxy and set the
     interfaces and port as usual.

  3. Services > Squid Proxy Server > Authentication -- set

         Authentication Method = Active Directory (Samba winbind SSO)

     and save. Squid then writes the negotiate/NTLM/basic helper directives
     itself, and creates the "password" ACL its own access rules already use,
     so no access rule has to be edited by hand.

  4. For true single sign-on the browser must reach the proxy by a hostname
     covered by a Kerberos SPN, not by IP address. With an IP, clients fall
     back to NTLM or to a password prompt.

  5. After ANY Squid package update, re-run:

         php /usr/local/pkg/squid_ad_patch.php apply

     A Squid update restores Squid's own files and removes the patch. If the
     method is still set to Active Directory at that point, Squid emits no
     authentication directives at all. Check with:

         php /usr/local/pkg/squid_ad_patch.php status

EOT
}

do_remove() {
	require_root

	if patcher_available; then
		log "Reverting the Authentication Method patch"
		php "${PATCHER_DEST}" revert || warn "Could not revert the patch cleanly."
		rm -f "${PATCHER_DEST}"
	fi

	if [ -L "${SQUID_HELPER}" ]; then
		rm -f "${SQUID_HELPER}"
		log "Removed the ntlm_auth symlink"
	fi

	run_base_installer remove

	log "Squid itself was left installed and configured."
	log "Remove it from System > Package Manager if you no longer want it."
}

do_status() {
	run_base_installer status

	if squid_installed; then
		echo "squid: installed"
		pgrep -x squid >/dev/null 2>&1 && echo "squid: running" || echo "squid: stopped"
	else
		echo "squid: not installed"
	fi

	[ -L "${SQUID_HELPER}" ] && echo "ntlm_auth: linked" || echo "ntlm_auth: not linked"

	if patcher_available; then
		php "${PATCHER_DEST}" status || true
	fi
}

case "${1:-}" in
	check)   do_check ;;
	install) do_install ;;
	remove)  do_remove ;;
	status)  do_status ;;
	*)       echo "Usage: $0 {check|install|remove|status}"; exit 64 ;;
esac
