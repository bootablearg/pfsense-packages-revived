<?php
/*
 * samba_ad.inc
 *
 * Backend logic for the "Samba AD" pfSense package: joins the firewall to an
 * Active Directory domain and runs winbindd so that AD users and groups can be
 * resolved locally (and, optionally, used by Squid's ntlm_auth helper).
 *
 * Copyright (c) 2013-2016 Luiz Gustavo S. Costa <me@luizgustavo.pro.br>
 * Copyright (c) 2026 pfsense-samba-ad contributors
 * All rights reserved.
 *
 * Derived from the pf2ad project (BSD 2-Clause), branch 2.4.3-SAMBA4.
 * See LICENSE for the full license text.
 *
 * Target: pfSense CE 2.8/2.9 and pfSense Plus 25.x/26.x (PHP 8.2/8.3).
 */

require_once('config.inc');
require_once('globals.inc');
require_once('interfaces.inc');
require_once('pfsense-utils.inc');
require_once('service-utils.inc');
require_once('util.inc');

/* Filesystem layout. Kept as constants so the uninstaller and the diagnostics
 * page reference exactly the same paths as the writer functions. */
define('SAMBA_AD_SMBCONF',   '/usr/local/etc/smb4.conf');
define('SAMBA_AD_KRB5CONF',  '/etc/krb5.conf');
define('SAMBA_AD_KEYTAB',    '/etc/krb5.keytab');
define('SAMBA_AD_RCFILE',    '/usr/local/etc/rc.d/samba_ad.sh');
define('SAMBA_AD_PRIVDIR',   '/var/db/samba4/winbindd_privileged');
define('SAMBA_AD_LOGDIR',    '/var/log/samba4');
define('SAMBA_AD_RUNDIR',    '/var/run/samba4');
define('SAMBA_AD_NET',       '/usr/local/bin/net');
define('SAMBA_AD_NTLM_AUTH', '/usr/local/bin/ntlm_auth');
define('SAMBA_AD_WBINFO',    '/usr/local/bin/wbinfo');
define('SAMBA_AD_SQUID_HELPER', '/usr/local/libexec/squid/ntlm_auth');

/*
 * Read the package settings.
 *
 * pfSense 2.7 introduced config_get_path() and deprecated direct access to the
 * $config global. We prefer the modern API and fall back to the global only on
 * older releases, so the same file works across the supported range.
 */
function samba_ad_get_config() {
	if (function_exists('config_get_path')) {
		return config_get_path('installedpackages/sambaad/config/0', []);
	}

	global $config;
	return $config['installedpackages']['sambaad']['config'][0] ?? [];
}

/*
 * Resolve the selected interfaces to IP addresses for the smb.conf "interfaces"
 * directive.
 *
 * The original shelled out to ifconfig and parsed the output by field position,
 * which broke on interfaces carrying multiple addresses and could not handle
 * the multi-select the GUI already offered. get_interface_ip() is the supported
 * pfSense API and takes friendly interface names directly.
 */
function samba_ad_listen_addresses($iflist) {
	$addresses = array();

	foreach (explode(',', (string) $iflist) as $iface) {
		$iface = trim($iface);
		if ($iface === '') {
			continue;
		}

		$ip = get_interface_ip($iface);
		if (is_ipaddrv4($ip)) {
			$addresses[] = $ip;
		} else {
			log_error("Samba AD: interface '{$iface}' has no usable IPv4 address, skipping.");
		}
	}

	/* Always bind loopback: ntlm_auth and wbinfo reach winbindd through it. */
	$addresses[] = '127.0.0.1';

	return array_values(array_unique($addresses));
}

/*
 * Form validation. Called from samba_ad.xml before anything is written to disk.
 */
function samba_ad_validate_form($post, &$input_errors) {
	if (empty($post['enable'])) {
		return;
	}

	if (empty($post['realm'])) {
		$input_errors[] = gettext("The field 'Domain / Realm' is required.");
	} elseif (!is_domain($post['realm'])) {
		$input_errors[] = gettext("'Domain / Realm' must be a valid DNS domain name (for example: example.local).");
	}

	if (empty($post['workgroup'])) {
		$input_errors[] = gettext("The field 'Workgroup (NetBIOS name)' is required.");
	} elseif (!preg_match('/^[A-Za-z0-9._-]{1,15}$/', $post['workgroup'])) {
		$input_errors[] = gettext("'Workgroup' must be 1-15 characters: letters, digits, dot, dash or underscore.");
	}

	if (empty($post['username'])) {
		$input_errors[] = gettext("The field 'Join Username' is required.");
	}

	if (empty($post['password'])) {
		$input_errors[] = gettext("The field 'Join Password' is required.");
	}

	if (empty($post['interface'])) {
		$input_errors[] = gettext("At least one listen interface must be selected.");
	}

	/* idmap ranges must not overlap: an overlap silently breaks user mapping
	 * in ways that only show up much later, as random unresolvable users. */
	$def_low  = (int) ($post['idmap_default_low']  ?? 70001);
	$def_high = (int) ($post['idmap_default_high'] ?? 80000);
	$dom_low  = (int) ($post['idmap_domain_low']   ?? 10000);
	$dom_high = (int) ($post['idmap_domain_high']  ?? 69999);

	$ranges = array(
		array($def_low, $def_high, 'Default'),
		array($dom_low, $dom_high, 'Domain'),
	);

	foreach ($ranges as $range) {
		if ($range[0] >= $range[1]) {
			$input_errors[] = sprintf(gettext("The %s idmap range start must be lower than its end."), $range[2]);
		}
		if ($range[0] < 1000) {
			$input_errors[] = sprintf(gettext("The %s idmap range must start at 1000 or higher to avoid clashing with system accounts."), $range[2]);
		}
	}

	if ($dom_high >= $def_low && $dom_low <= $def_high) {
		$input_errors[] = gettext("The Default and Domain idmap ranges overlap. Give each backend its own range.");
	}
}

/*
 * Write /etc/krb5.conf.
 *
 * Only AES enctypes are configured. The original shipped RC4 and single-DES
 * profiles for Windows 2003; DES was removed from modern Kerberos and RC4 is
 * disabled by default on current domain controllers, so offering those choices
 * produced configurations that simply fail to authenticate.
 */
function samba_ad_write_krb5conf($settings) {
	$realm  = strtoupper($settings['realm']);
	$domain = strtolower($settings['realm']);

	$lines = array(
		'# Generated by the pfSense Samba AD package. Manual edits will be lost.',
		'',
		'[libdefaults]',
		"    default_realm = {$realm}",
		'    dns_lookup_realm = true',
		'    dns_lookup_kdc = true',
		'    ticket_lifetime = 24h',
		'    renew_lifetime = 7d',
		'    forwardable = true',
		'    default_tgs_enctypes = aes256-cts-hmac-sha1-96 aes128-cts-hmac-sha1-96',
		'    default_tkt_enctypes = aes256-cts-hmac-sha1-96 aes128-cts-hmac-sha1-96',
		'    permitted_enctypes   = aes256-cts-hmac-sha1-96 aes128-cts-hmac-sha1-96',
		'',
		'[domain_realm]',
		"    .{$domain} = {$realm}",
		"    {$domain} = {$realm}",
		'',
	);

	/*
	 * If a domain controller was given explicitly, pin it here.
	 *
	 * Kerberos normally finds the KDC through _kerberos._tcp SRV records. That
	 * fails whenever the firewall's resolver does not serve the AD zone, which
	 * is common: the domain name may resolve through a host override while the
	 * SRV records do not exist anywhere the firewall can see. Pinning the KDC
	 * makes the join work without changing the firewall's DNS configuration.
	 */
	if (!empty($settings['dc'])) {
		$dc = $settings['dc'];
		$lines = array_merge($lines, array(
			'[realms]',
			"    {$realm} = {",
			"        kdc = {$dc}",
			"        admin_server = {$dc}",
			'    }',
			'',
		));
	}

	$lines = array_merge($lines, array(
		'[logging]',
		'    default = FILE:/var/log/krb5libs.log',
		'',
	));

	/* Preserve whatever was there before we first took the file over. */
	if (file_exists(SAMBA_AD_KRB5CONF) && !file_exists(SAMBA_AD_KRB5CONF . '.before-samba-ad')) {
		@copy(SAMBA_AD_KRB5CONF, SAMBA_AD_KRB5CONF . '.before-samba-ad');
	}

	file_put_contents(SAMBA_AD_KRB5CONF, implode("\n", $lines));
	@chmod(SAMBA_AD_KRB5CONF, 0644);
}

/*
 * Installed Samba version as a float (for example 4.24), or 0.0 if it cannot
 * be determined. Used to emit version-appropriate smb.conf directives.
 */
function samba_ad_samba_version() {
	$out = array();
	$rc = 0;
	exec('/usr/local/sbin/smbd --version 2>/dev/null', $out, $rc);

	if ($rc !== 0 || empty($out[0])) {
		return 0.0;
	}

	if (preg_match('/(\d+)\.(\d+)/', $out[0], $m)) {
		return (float) ($m[1] . '.' . $m[2]);
	}

	return 0.0;
}

/*
 * Choose how the machine password is kept in sync with the keytab.
 *
 * Samba 4.24 deprecated "kerberos method" in favour of the more explicit
 * "sync machine password to keytab", and testparm emits a suggestion when the
 * old one is used. Both are emitted conditionally so the generated config is
 * clean on new Samba without breaking older branches, which do not know the
 * new parameter at all.
 */
function samba_ad_keytab_directive() {
	if (samba_ad_samba_version() >= 4.24) {
		return '    sync machine password to keytab = ' . SAMBA_AD_KEYTAB
			. ':sync_spns:sync_kvno:machine_password';
	}

	return '    kerberos method = secrets and keytab';
}

/*
 * Write /usr/local/etc/smb4.conf.
 *
 * idmap defaults to the "rid" backend rather than "ad". The "ad" backend needs
 * uidNumber/gidNumber attributes populated in the directory (RFC2307); most
 * domains do not have them, and winbind then fails to map any user at all.
 * "rid" derives IDs algorithmically and works against a stock Active Directory.
 */
function samba_ad_write_smbconf($settings) {
	$realm     = strtoupper($settings['realm']);
	$workgroup = strtoupper($settings['workgroup']);
	$idmap     = (($settings['idmap_backend'] ?? 'rid') === 'ad') ? 'ad' : 'rid';

	$def_low  = (int) ($settings['idmap_default_low']  ?? 70001);
	$def_high = (int) ($settings['idmap_default_high'] ?? 80000);
	$dom_low  = (int) ($settings['idmap_domain_low']   ?? 10000);
	$dom_high = (int) ($settings['idmap_domain_high']  ?? 69999);

	$addresses = samba_ad_listen_addresses($settings['interface'] ?? '');

	$lines = array(
		'# Generated by the pfSense Samba AD package. Manual edits will be lost.',
		'',
		'[global]',
		"    workgroup = {$workgroup}",
		"    realm = {$realm}",
		'    security = ADS',
		samba_ad_keytab_directive(),
		'',
		'    # Bind only where we were told to listen. Loopback is always included',
		'    # because ntlm_auth and wbinfo reach winbindd through it.',
		'    interfaces = ' . implode(' ', $addresses),
		'    bind interfaces only = yes',
		'    disable netbios = yes',
		'    dns proxy = no',
		'',
		'    # This box is a domain MEMBER, not a file server. Keeping the file',
		'    # sharing surface off stops smbd from exposing anything by accident.',
		'    server role = member server',
		'    load printers = no',
		'    printing = bsd',
		'    printcap name = /dev/null',
		'    disable spoolss = yes',
		'',
		'    winbind use default domain = yes',
		'    winbind refresh tickets = yes',
		'    winbind offline logon = no',
		'    # Enumeration is expensive on large domains and is not needed for auth.',
		'    winbind enum users = no',
		'    winbind enum groups = no',
		'',
		'    idmap config * : backend = tdb',
		"    idmap config * : range = {$def_low}-{$def_high}",
		"    idmap config {$workgroup} : backend = {$idmap}",
		"    idmap config {$workgroup} : range = {$dom_low}-{$dom_high}",
	);

	if ($idmap === 'ad') {
		/* Only meaningful for the ad backend; noise (or worse) otherwise. */
		$lines[] = "    idmap config {$workgroup} : schema_mode = rfc2307";
		$lines[] = '    winbind nss info = rfc2307';
	}

	/*
	 * Note: no "password server" is emitted, even when a controller is pinned.
	 * testparm rejects combining it with security=ADS -- it belongs to the NT4
	 * era, and in ADS mode Samba locates the controller through Kerberos and
	 * DNS instead. The controller is pinned in krb5.conf ([realms]) and passed
	 * to `net` with -S, which is the supported way to do this.
	 */

	$tail = array(
		'',
		'    template shell = /bin/sh',
		'    template homedir = /var/empty',
		'',
		'    # NTLMv2 only. NTLMv1 is disabled by default in current Samba and',
		'    # rejected outright by hardened domain controllers.',
		'    ntlm auth = ntlmv2-only',
		'    client ldap sasl wrapping = seal',
		'',
		'    log file = ' . SAMBA_AD_LOGDIR . '/log.%m',
		'    max log size = 5000',
		'    log level = ' . (int) ($settings['log_level'] ?? 1),
		'',
	);

	$lines = array_merge($lines, $tail);

	if (!empty($settings['custom_options'])) {
		$lines[] = '    # --- Custom options set in the GUI ---';
		foreach (preg_split('/\r?\n/', base64_decode($settings['custom_options'])) as $line) {
			$line = rtrim($line);
			if ($line !== '') {
				$lines[] = '    ' . ltrim($line);
			}
		}
		$lines[] = '';
	}

	file_put_contents(SAMBA_AD_SMBCONF, implode("\n", $lines));
	@chmod(SAMBA_AD_SMBCONF, 0644);
}

/*
 * Write the rc script used to start and stop the daemons.
 *
 * The original used `killall smbd` and friends, which kills every matching
 * process on the system regardless of origin, and detected "already running"
 * by grepping `ps axuw`. This uses pgrep/pkill with exact name matching.
 */
function samba_ad_write_rcfile($settings) {
	$want_smbd = !empty($settings['enable_smbd']);

	$start = array(
		'mkdir -p ' . SAMBA_AD_RUNDIR . ' ' . SAMBA_AD_LOGDIR,
		'/usr/local/sbin/winbindd -D -s ' . SAMBA_AD_SMBCONF,
	);

	$stop = array(
		'/bin/pkill -x winbindd 2>/dev/null',
	);

	if ($want_smbd) {
		$start[] = '/usr/local/sbin/smbd -D -s ' . SAMBA_AD_SMBCONF;
		$start[] = '/usr/local/sbin/nmbd -D -s ' . SAMBA_AD_SMBCONF;
		array_unshift($stop, '/bin/pkill -x nmbd 2>/dev/null');
		array_unshift($stop, '/bin/pkill -x smbd 2>/dev/null');
	}

	$indent = function ($line) {
		return '    ' . $line;
	};

	$script = array_merge(
		array(
			'#!/bin/sh',
			'#',
			'# Generated by the pfSense Samba AD package. Manual edits will be lost.',
			'',
			'samba_ad_start() {',
		),
		array_map($indent, $start),
		array(
			'}',
			'',
			'samba_ad_stop() {',
		),
		array_map($indent, $stop),
		array(
			'    # Let the daemons release their sockets before a restart.',
			'    sleep 1',
			'}',
			'',
			'case "$1" in',
			'    start)   samba_ad_start ;;',
			'    stop)    samba_ad_stop ;;',
			'    restart) samba_ad_stop; samba_ad_start ;;',
			'    status)  /bin/pgrep -x winbindd >/dev/null && echo "running" || echo "stopped" ;;',
			'    *)       echo "Usage: $0 {start|stop|restart|status}"; exit 64 ;;',
			'esac',
			'',
		)
	);

	file_put_contents(SAMBA_AD_RCFILE, implode("\n", $script));
	@chmod(SAMBA_AD_RCFILE, 0755);
}

/*
 * "-S <dc>" for `net`, or an empty string when no controller was pinned.
 *
 * Without this, `net` discovers the controller through DNS SRV records, which
 * is not always possible from a firewall whose resolver does not serve the AD
 * zone. Returned with a leading space so it can be interpolated directly.
 */
function samba_ad_server_arg($settings) {
	if (empty($settings['dc'])) {
		return '';
	}

	return ' -S ' . escapeshellarg($settings['dc']);
}

/*
 * Build a mode-0600 temporary credentials file for `net`.
 *
 * The original interpolated the password straight into a shell string, which
 * both leaked it to anyone able to run `ps` and allowed command injection
 * through a password containing shell metacharacters.
 */
function samba_ad_write_authfile($settings) {
	$authfile = tempnam('/tmp', 'sambaad_');
	if ($authfile === false) {
		return false;
	}

	@chmod($authfile, 0600);

	file_put_contents($authfile, implode("\n", array(
		'username = ' . $settings['username'],
		'password = ' . $settings['password'],
		'domain = '   . strtoupper($settings['workgroup']),
		'',
	)));

	return $authfile;
}

/*
 * Join the domain. Returns array(bool success, string output).
 */
function samba_ad_join_domain($settings) {
	$authfile = samba_ad_write_authfile($settings);
	if ($authfile === false) {
		log_error('Samba AD: could not create a temporary credentials file; join aborted.');
		return array(false, 'Could not create temporary credentials file.');
	}

	$cmd = sprintf(
		'%s ads join%s -s %s -A %s 2>&1',
		escapeshellarg(SAMBA_AD_NET),
		samba_ad_server_arg($settings),
		escapeshellarg(SAMBA_AD_SMBCONF),
		escapeshellarg($authfile)
	);

	$output = array();
	$rc = 0;
	exec($cmd, $output, $rc);

	@unlink($authfile);

	$text = implode("\n", $output);

	/* `net ads join` has been known to exit 0 on partial failures, so the
	 * output is checked as well as the exit status. */
	$joined = ($rc === 0 && stripos($text, 'Joined') !== false);

	if ($joined) {
		log_error('Samba AD: joined domain ' . strtoupper($settings['realm']) . '.');
	} else {
		/* Log only what `net` reported: the command line is never logged, so a
		 * future change cannot accidentally start leaking credentials. */
		log_error('Samba AD: domain join FAILED: ' . $text);
	}

	return array($joined, $text);
}

/*
 * Create or refresh the Kerberos keytab and hand it to the proxy group.
 *
 * The original only created the keytab when the file was missing, so rejoining
 * a different domain left a stale keytab behind.
 */
function samba_ad_create_keytab($settings) {
	$authfile = samba_ad_write_authfile($settings);
	if ($authfile === false) {
		return false;
	}

	$cmd = sprintf(
		'%s ads keytab create%s -s %s -A %s 2>&1',
		escapeshellarg(SAMBA_AD_NET),
		samba_ad_server_arg($settings),
		escapeshellarg(SAMBA_AD_SMBCONF),
		escapeshellarg($authfile)
	);

	$output = array();
	$rc = 0;
	exec($cmd, $output, $rc);

	@unlink($authfile);

	if (file_exists(SAMBA_AD_KEYTAB)) {
		/* Squid runs as the proxy user and has to be able to read the keytab. */
		@chgrp(SAMBA_AD_KEYTAB, 'proxy');
		@chmod(SAMBA_AD_KEYTAB, 0640);
	}

	return ($rc === 0);
}

/*
 * Ensure winbindd's privileged pipe directory exists with the ownership
 * ntlm_auth needs. Without it, authentication fails with a generic
 * "could not talk to winbind" that is painful to trace back to permissions.
 */
function samba_ad_prepare_privileged_dir() {
	safe_mkdir(SAMBA_AD_PRIVDIR, 0750);
	@chgrp(SAMBA_AD_PRIVDIR, 'proxy');
	@chmod(SAMBA_AD_PRIVDIR, 0750);
}

/*
 * True if winbindd is up. Exact-match pgrep rather than parsing `ps` output,
 * so an unrelated process merely mentioning winbindd in its arguments does not
 * produce a false positive.
 */
function samba_ad_is_running() {
	$out = array();
	$rc = 0;
	exec('/bin/pgrep -x winbindd', $out, $rc);
	return ($rc === 0);
}

function samba_ad_stop_service() {
	if (file_exists(SAMBA_AD_RCFILE)) {
		mwexec(escapeshellarg(SAMBA_AD_RCFILE) . ' stop');
	}
}

/*
 * Start the daemons and confirm they stayed up.
 *
 * mwexec() reports the exit status of the rc script, which says nothing about
 * whether winbindd survived starting: the script returns 0 as soon as it has
 * spawned it. Polling for the process turns a silent "the service is somehow
 * not running" into a log line naming the file to look at.
 */
function samba_ad_start_service() {
	if (!file_exists(SAMBA_AD_RCFILE)) {
		log_error('Samba AD: cannot start, ' . SAMBA_AD_RCFILE . ' is missing.');
		return false;
	}

	mwexec(escapeshellarg(SAMBA_AD_RCFILE) . ' start');

	for ($i = 0; $i < 5; $i++) {
		if (samba_ad_is_running()) {
			return true;
		}
		sleep(1);
	}

	log_error('Samba AD: winbindd did not stay running after start. '
		. 'See /var/log/samba4/log.winbindd for the reason.');

	return false;
}

/*
 * Main entry point, called by samba_ad.xml on every save.
 */
function samba_ad_sync() {
	$settings = samba_ad_get_config();

	if (empty($settings) || empty($settings['enable'])) {
		/* Disabled: stop the daemons but leave domain membership and the config
		 * files alone, so re-enabling later does not require another join. */
		samba_ad_stop_service();
		log_error('Samba AD: service disabled.');
		return;
	}

	samba_ad_prepare_privileged_dir();
	safe_mkdir(SAMBA_AD_LOGDIR, 0755);
	safe_mkdir(SAMBA_AD_RUNDIR, 0755);

	samba_ad_write_krb5conf($settings);
	samba_ad_write_smbconf($settings);
	samba_ad_write_rcfile($settings);

	/* Stop before joining: a running winbindd holds the previous domain state. */
	samba_ad_stop_service();

	$result = samba_ad_join_domain($settings);
	$joined = $result[0];

	if (!$joined) {
		/* Deliberately do not start the daemons after a failed join. A winbindd
		 * that cannot reach its domain produces confusing partial failures
		 * downstream; failing loudly here is easier to diagnose. */
		log_error('Samba AD: daemons not started because the domain join failed.');
		return;
	}

	samba_ad_create_keytab($settings);
	samba_ad_link_squid_helper();
	samba_ad_start_service();
}

/*
 * Expose ntlm_auth where Squid expects to find it.
 *
 * A symlink is used rather than the original's file copy: a copy goes stale
 * the moment Samba is updated, and a stale helper talking to a newer winbindd
 * fails in ways that look like a domain problem rather than a file problem.
 */
function samba_ad_link_squid_helper() {
	if (!is_dir('/usr/local/libexec/squid')) {
		return false;
	}
	if (!file_exists(SAMBA_AD_NTLM_AUTH)) {
		return false;
	}
	if (is_link(SAMBA_AD_SQUID_HELPER) || file_exists(SAMBA_AD_SQUID_HELPER)) {
		@unlink(SAMBA_AD_SQUID_HELPER);
	}

	return @symlink(SAMBA_AD_NTLM_AUTH, SAMBA_AD_SQUID_HELPER);
}

/*
 * Optional Squid integration status, surfaced on the Diagnostics tab.
 *
 * This package deliberately does NOT patch the Squid package. Squid is
 * deprecated by Netgate and its files change between releases, which made
 * patching the single most fragile part of the original design. Instead we
 * report whether the pieces Squid needs are in place, and the README documents
 * the handful of lines to paste into Squid's custom options.
 */
function samba_ad_squid_status() {
	return array(
		'ntlm_auth_present'   => file_exists(SAMBA_AD_NTLM_AUTH),
		'squid_installed'     => is_dir('/usr/local/libexec/squid'),
		'squid_helper_linked' => is_link(SAMBA_AD_SQUID_HELPER),
		'privileged_dir_ok'   => is_dir(SAMBA_AD_PRIVDIR),
		'keytab_present'      => file_exists(SAMBA_AD_KEYTAB),
		'winbindd_running'    => samba_ad_is_running(),
	);
}

function samba_ad_install() {
	samba_ad_prepare_privileged_dir();
	safe_mkdir(SAMBA_AD_LOGDIR, 0755);
	safe_mkdir(SAMBA_AD_RUNDIR, 0755);

	/* smb4.conf has to exist before anything calls `net`, even if empty. */
	if (!file_exists(SAMBA_AD_SMBCONF)) {
		touch(SAMBA_AD_SMBCONF);
	}

	samba_ad_link_squid_helper();
}

/*
 * Leave the domain and clean up.
 *
 * The original never implemented removal at all ("Not implemented yet"), which
 * left orphaned machine accounts in the directory.
 */
function samba_ad_deinstall() {
	$settings = samba_ad_get_config();

	/* Best effort: drop the machine account if we still hold credentials. */
	if (!empty($settings['username']) && !empty($settings['password'])) {
		$authfile = samba_ad_write_authfile($settings);
		if ($authfile !== false) {
			mwexec(sprintf(
				'%s ads leave -s %s -A %s',
				escapeshellarg(SAMBA_AD_NET),
				escapeshellarg(SAMBA_AD_SMBCONF),
				escapeshellarg($authfile)
			));
			@unlink($authfile);
		}
	} else {
		log_error('Samba AD: no stored credentials, machine account left in the '
			. 'directory. Run "net ads leave" manually to remove it.');
	}

	samba_ad_stop_service();

	@unlink(SAMBA_AD_RCFILE);
	@unlink(SAMBA_AD_SMBCONF);

	/* Restore whatever krb5.conf was in place before we took it over. */
	if (file_exists(SAMBA_AD_KRB5CONF . '.before-samba-ad')) {
		@rename(SAMBA_AD_KRB5CONF . '.before-samba-ad', SAMBA_AD_KRB5CONF);
	}

	if (is_link(SAMBA_AD_SQUID_HELPER)) {
		@unlink(SAMBA_AD_SQUID_HELPER);
	}

	log_error('Samba AD: package removed.');
}
