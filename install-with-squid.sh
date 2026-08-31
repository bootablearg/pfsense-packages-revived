#!/bin/sh
#
# install-with-squid.sh -- Samba AD domain membership *plus* the Squid proxy,
# wired together so Squid authenticates users against Active Directory.
#
# Copyright (c) 2013-2016 Luiz Gustavo S. Costa <me@luizgustavo.pro.br>
# Copyright (c) 2026 pfsense-samba-ad contributors
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
#   ./install-with-squid.sh remove    Remove the auth block and the AD package.
#   ./install-with-squid.sh status    Show current state.
#
# Or straight from the network:
#   fetch -q -o - https://raw.githubusercontent.com/bootablearg/pfsense-samba-ad/main/install-with-squid.sh | sh -s install
#
# What it adds on top of install.sh:
#
#   * Installs pfSense-pkg-squid if it is not already present.
#   * Symlinks Samba's ntlm_auth into Squid's helper directory.
#   * Writes the auth_param block into Squid's "Custom Options (Before Auth)",
#     between markers, so the block can be updated or removed later without
#     disturbing anything else you have put there.
#   * Regenerates squid.conf through Squid's own squid_resync().
#
# What it deliberately does NOT do: rewrite Squid's own package files. The
# original pf2ad patched squid.inc and squid_auth.xml with a diff guarded by a
# hardcoded MD5 of one exact build, which broke on every Squid update. Squid is
# also deprecated by Netgate, so anything that edits its internals is living on
# borrowed time. Configuration through the supported custom-options field keeps
# working across Squid updates.

set -u

SCRIPT_DIR=""
case "$0" in
	*/*) SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)" ;;
esac

SAMBA_AD_SRC_URL="${SAMBA_AD_SRC_URL:-https://raw.githubusercontent.com/bootablearg/pfsense-samba-ad/main}"

SQUID_PKG="pfSense-pkg-squid"
SQUID_HELPER_DIR="/usr/local/libexec/squid"
SQUID_HELPER="${SQUID_HELPER_DIR}/ntlm_auth"
SAMBA_NTLM_AUTH="/usr/local/bin/ntlm_auth"

# Markers delimiting our block inside Squid's custom options. Anything outside
# them is left untouched.
MARK_BEGIN="# BEGIN pfsense-samba-ad -- managed block, edits will be overwritten"
MARK_END="# END pfsense-samba-ad"

log()  { echo "==> $*"; }
warn() { echo "WARNING: $*" >&2; }
err()  { echo "ERROR: $*" >&2; exit 1; }

require_root() {
	[ "$(id -u)" = "0" ] || err "This script must be run as root."
}

squid_installed() {
	pkg info -e "${SQUID_PKG}" 2>/dev/null
}

samba_ad_installed() {
	[ -f /usr/local/pkg/samba_ad.inc ]
}

# Run install.sh, from the same directory if present, otherwise from the repo.
run_base_installer() {
	_action="$1"

	if [ -n "${SCRIPT_DIR}" ] && [ -x "${SCRIPT_DIR}/install.sh" ]; then
		"${SCRIPT_DIR}/install.sh" "${_action}"
	elif [ -n "${SCRIPT_DIR}" ] && [ -f "${SCRIPT_DIR}/install.sh" ]; then
		sh "${SCRIPT_DIR}/install.sh" "${_action}"
	else
		log "Fetching install.sh from ${SAMBA_AD_SRC_URL}"
		fetch -q -o - "${SAMBA_AD_SRC_URL}/install.sh" | sh -s "${_action}" \
			|| err "The base installer failed. Nothing further was changed."
	fi
}

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

# Write (or refresh) the managed auth block inside Squid's custom options.
write_auth_block() {
	log "Writing the authentication block into Squid's custom options"

	/usr/local/sbin/pfSsh.php <<'PHPEOF'
require_once('/usr/local/pkg/squid.inc');

$begin = '# BEGIN pfsense-samba-ad -- managed block, edits will be overwritten';
$end   = '# END pfsense-samba-ad';

$block = implode("\n", [
	$begin,
	'# Active Directory authentication via Samba winbind.',
	'#',
	'# Negotiate (Kerberos) is offered first and is transparent for',
	'# domain-joined clients. NTLM is a fallback for clients that cannot do',
	'# Kerberos; Microsoft has deprecated it and Samba disables NTLMv1, so',
	'# prefer Negotiate where you can. Basic is a last resort and sends',
	'# credentials in the clear unless the connection is TLS.',
	'auth_param negotiate program /usr/local/libexec/squid/ntlm_auth --helper-protocol=gss-spnego',
	'auth_param negotiate children 20 startup=0 idle=1',
	'auth_param negotiate keep_alive on',
	'',
	'auth_param ntlm program /usr/local/libexec/squid/ntlm_auth --helper-protocol=squid-2.5-ntlmssp',
	'auth_param ntlm children 20 startup=0 idle=1',
	'auth_param ntlm keep_alive on',
	'',
	'auth_param basic program /usr/local/libexec/squid/ntlm_auth --helper-protocol=squid-2.5-basic',
	'auth_param basic children 5 startup=0 idle=1',
	'auth_param basic realm Proxy',
	'auth_param basic credentialsttl 2 hours',
	'',
	'# Matches any successfully authenticated domain user. Reference this ACL',
	'# from your access rules to actually require authentication.',
	'acl domain_users proxy_auth REQUIRED',
	$end,
]);

$cfg = function_exists('config_get_path')
	? config_get_path('installedpackages/squid/config/0', [])
	: ($config['installedpackages']['squid']['config'][0] ?? []);
if (!is_array($cfg)) { $cfg = []; }

$current = '';
if (!empty($cfg['custom_options_squid3'])) {
	$current = base64_decode($cfg['custom_options_squid3']);
}

/* Strip any previous managed block so re-running replaces rather than stacks,
 * and anything the administrator added outside the markers is preserved. */
$pattern = '/' . preg_quote($begin, '/') . '.*?' . preg_quote($end, '/') . '\n?/s';
$cleaned = preg_replace($pattern, '', $current);
$cleaned = rtrim((string) $cleaned);

$new = ($cleaned === '') ? $block : ($cleaned . "\n\n" . $block);

$cfg['custom_options_squid3'] = base64_encode($new);

if (function_exists('config_set_path')) {
	config_set_path('installedpackages/squid/config/0', $cfg);
} else {
	$config['installedpackages']['squid']['config'][0] = $cfg;
}

write_config('Samba AD: add Squid AD authentication block');

/* Regenerate squid.conf through Squid's own resync, the same call its GUI
 * makes on save, so the file is built exactly as the package expects. */
if (function_exists('squid_resync')) {
	squid_resync();
}

exec;
exit
PHPEOF
}

remove_auth_block() {
	log "Removing the authentication block from Squid's custom options"

	/usr/local/sbin/pfSsh.php <<'PHPEOF'
require_once('/usr/local/pkg/squid.inc');

$begin = '# BEGIN pfsense-samba-ad -- managed block, edits will be overwritten';
$end   = '# END pfsense-samba-ad';

$cfg = function_exists('config_get_path')
	? config_get_path('installedpackages/squid/config/0', [])
	: ($config['installedpackages']['squid']['config'][0] ?? []);
if (!is_array($cfg) || empty($cfg['custom_options_squid3'])) {
	exec;
	exit;
}

$current = base64_decode($cfg['custom_options_squid3']);
$pattern = '/' . preg_quote($begin, '/') . '.*?' . preg_quote($end, '/') . '\n?/s';
$cleaned = rtrim((string) preg_replace($pattern, '', $current));

$cfg['custom_options_squid3'] = ($cleaned === '') ? '' : base64_encode($cleaned);

if (function_exists('config_set_path')) {
	config_set_path('installedpackages/squid/config/0', $cfg);
} else {
	$config['installedpackages']['squid']['config'][0] = $cfg;
}

write_config('Samba AD: remove Squid AD authentication block');

if (function_exists('squid_resync')) {
	squid_resync();
}

exec;
exit
PHPEOF
}

verify_auth() {
	log "Verifying the helper against the domain"

	if [ ! -x "${SQUID_HELPER}" ]; then
		warn "${SQUID_HELPER} is not present."
		return 1
	fi

	if ! pgrep -x winbindd >/dev/null 2>&1; then
		warn "winbindd is not running: join the domain from Services > Samba AD first."
		return 1
	fi

	# Does the helper actually talk to winbind? A wrong answer here is the
	# difference between "authentication is broken" and "the proxy is broken",
	# which is worth knowing before users start complaining.
	if "${SQUID_HELPER}" --diagnostics </dev/null >/dev/null 2>&1; then
		log "ntlm_auth responds"
	else
		log "ntlm_auth is present; full diagnostics need credentials, so this is not conclusive"
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

	if squid_installed; then
		_has=$(/usr/local/sbin/pfSsh.php <<'PHPEOF' 2>/dev/null | tail -1
$cfg = config_get_path('installedpackages/squid/config/0', []);
$c = !empty($cfg['custom_options_squid3']) ? base64_decode($cfg['custom_options_squid3']) : '';
echo (strpos($c, 'BEGIN pfsense-samba-ad') !== false) ? 'yes' : 'no';
exec;
exit
PHPEOF
)
		case "${_has}" in
			*yes*) echo "auth block : present" ;;
			*)     echo "auth block : absent (would be added)" ;;
		esac
	fi
}

do_install() {
	require_root

	log "Step 1/4: Samba AD"
	run_base_installer install

	samba_ad_installed || err "The Samba AD package did not install. Stopping before touching Squid."

	log "Step 2/4: Squid"
	install_squid

	log "Step 3/4: linking the authentication helper"
	link_helper

	log "Step 4/4: Squid authentication configuration"
	write_auth_block

	verify_auth || true

	log "Done."
	cat <<'EOT'

Next steps, in this order:

  1. Services > Samba AD -- fill in the domain details and enable the service
     to join the domain. Nothing below works until "Join is OK".

  2. Services > Squid Proxy Server -- enable the proxy and set your interfaces
     and port as usual.

  3. Decide how authentication is enforced. This script defined the ACL

         acl domain_users proxy_auth REQUIRED

     but did NOT change your access rules, because doing so silently could cut
     off every client on the network. Reference it from your own rule, for
     example in Custom Options (After Auth):

         http_access allow domain_users

     Note that an earlier "allow" rule wins: if your configuration already
     permits the client subnets unconditionally, authentication will never be
     requested. Check the generated /usr/local/etc/squid/squid.conf.

  4. Prefer Negotiate (Kerberos) over NTLM. Clients must reach the proxy by a
     hostname that has a matching SPN, not by IP address, or they will silently
     fall back to NTLM or Basic.

EOT
}

do_remove() {
	require_root

	if squid_installed; then
		remove_auth_block
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
}

case "${1:-}" in
	check)   do_check ;;
	install) do_install ;;
	remove)  do_remove ;;
	status)  do_status ;;
	*)       echo "Usage: $0 {check|install|remove|status}"; exit 64 ;;
esac
