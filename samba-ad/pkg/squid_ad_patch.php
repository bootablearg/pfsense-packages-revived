<?php
/*
 * squid_ad_patch.php
 *
 * Adds an "Active Directory" option to the Squid package's Authentication
 * Method dropdown, so the proxy can authenticate against the domain through
 * Samba's winbind -- giving domain-joined browsers single sign-on instead of a
 * username/password prompt.
 *
 * Copyright (c) 2026 pfsense-packages-revived contributors
 * All rights reserved. BSD 2-Clause -- see LICENSE.
 *
 * Usage:  php squid_ad_patch.php {apply|revert|status}
 *
 * Why this touches the Squid package at all
 * -----------------------------------------
 * The Authentication Method dropdown is hardcoded in squid_auth.xml, and the
 * directives for each method are produced by a switch in squid.inc. There is
 * no supported hook to add a method, so those two files have to be edited.
 *
 * How this differs from the patch it replaces
 * -------------------------------------------
 * The original pf2ad shipped a unified diff guarded by a hardcoded MD5 of one
 * exact Squid build. Any Squid update changed the MD5, the patch was skipped
 * or applied to the wrong offsets, and the result was a proxy that silently
 * stopped authenticating. This instead:
 *
 *   - locates its anchors by content, not by line number;
 *   - is idempotent: applying twice changes nothing the second time;
 *   - marks what it inserted, so it can be removed again cleanly;
 *   - keeps a backup of each original file;
 *   - can report whether the patch is currently in place.
 *
 * The insertion is deliberately minimal -- one dropdown option and one switch
 * case -- because the Squid package already treats 'ntlm' as a valid method
 * everywhere else (see the (local|ldap|radius|ntlm) checks in squid.inc,
 * squid_auth.xml and squid_js.inc). The value must therefore stay 'ntlm'.
 *
 * IMPORTANT: reinstalling or updating the Squid package restores its own
 * files and silently removes this patch. If that happens while the method is
 * still set to Active Directory, Squid will not emit any auth_param lines.
 * Re-run this script after any Squid update, and check `status` if
 * authentication ever stops being requested.
 */

define('SQUID_AUTH_XML', '/usr/local/pkg/squid_auth.xml');
define('SQUID_INC',      '/usr/local/pkg/squid.inc');
define('BACKUP_SUFFIX',  '.pfsense-samba-ad.bak');

define('MARK_BEGIN', 'pfsense-samba-ad:begin');
define('MARK_END',   'pfsense-samba-ad:end');

/* The dropdown entry. The value has to be 'ntlm': the Squid package already
 * recognises that string in its own validation checks. */
function ad_xml_block() {
	return
		"\t\t\t\t<!-- " . MARK_BEGIN . " -->\n" .
		"\t\t\t\t<option><name>Active Directory (Samba winbind SSO)</name><value>ntlm</value></option>\n" .
		"\t\t\t\t<!-- " . MARK_END . " -->";
}

/*
 * The switch case that emits the helper directives.
 *
 * Negotiate is listed first so browsers that can do Kerberos use it and never
 * prompt. NTLM follows for clients that cannot, and basic is the last resort.
 * $processes comes from the "Authentication processes" field, which the
 * package defines just above the switch; the common block after the switch
 * adds "auth_param basic children/realm/credentialsttl" and, importantly,
 * "acl password proxy_auth REQUIRED" -- which is what the package's own access
 * rules reference. That is why no access rule has to be edited by hand.
 */
function ad_inc_block() {
	$L = "SQUID_LOCALBASE . '/libexec/squid/ntlm_auth'";

	return
		"\t\t\t/* " . MARK_BEGIN . " */\n" .
		"\t\t\tcase 'ntlm':\n" .
		"\t\t\t\t\$conf .= 'auth_param negotiate program ' . {$L} . \" --helper-protocol=gss-spnego\\n\";\n" .
		"\t\t\t\t\$conf .= \"auth_param negotiate children {\$processes}\\n\";\n" .
		"\t\t\t\t\$conf .= \"auth_param negotiate keep_alive on\\n\";\n" .
		"\t\t\t\t\$conf .= 'auth_param ntlm program ' . {$L} . \" --helper-protocol=squid-2.5-ntlmssp\\n\";\n" .
		"\t\t\t\t\$conf .= \"auth_param ntlm children {\$processes}\\n\";\n" .
		"\t\t\t\t\$conf .= \"auth_param ntlm keep_alive on\\n\";\n" .
		"\t\t\t\t\$conf .= 'auth_param basic program ' . {$L} . \" --helper-protocol=squid-2.5-basic\\n\";\n" .
		"\t\t\t\tbreak;\n" .
		"\t\t\t/* " . MARK_END . " */";
}

function is_patched($file) {
	$c = @file_get_contents($file);
	return ($c !== false && strpos($c, MARK_BEGIN) !== false);
}

function backup_once($file) {
	$bak = $file . BACKUP_SUFFIX;
	if (!file_exists($bak)) {
		if (!@copy($file, $bak)) {
			return false;
		}
	}
	return true;
}

/* Remove a previously inserted block, whatever comment syntax wraps it. */
function strip_block($content) {
	$patterns = array(
		'/[ \t]*<!--\s*' . preg_quote(MARK_BEGIN, '/') . '\s*-->.*?<!--\s*' . preg_quote(MARK_END, '/') . '\s*-->\n?/s',
		'/[ \t]*\/\*\s*' . preg_quote(MARK_BEGIN, '/') . '\s*\*\/.*?\/\*\s*' . preg_quote(MARK_END, '/') . '\s*\*\/\n?/s',
	);

	return preg_replace($patterns, '', $content);
}

function apply_xml() {
	if (!file_exists(SQUID_AUTH_XML)) {
		return array(false, 'squid_auth.xml not found: is the Squid package installed?');
	}

	$content = file_get_contents(SQUID_AUTH_XML);

	if (strpos($content, MARK_BEGIN) !== false) {
		return array(true, 'already present');
	}

	/* Anchor on the last option of the auth_method dropdown. Matching by
	 * content rather than line number means the anchor survives edits
	 * elsewhere in the file. */
	$anchor = '/([ \t]*<option><name>Captive Portal<\/name><value>cp<\/value><\/option>)/';

	if (!preg_match($anchor, $content)) {
		return array(false, 'could not find the Authentication Method dropdown; Squid may have changed');
	}

	if (!backup_once(SQUID_AUTH_XML)) {
		return array(false, 'could not write a backup of squid_auth.xml');
	}

	$patched = preg_replace($anchor, "$1\n" . ad_xml_block(), $content, 1);

	if ($patched === null || $patched === $content) {
		return array(false, 'the dropdown edit produced no change');
	}

	if (file_put_contents(SQUID_AUTH_XML, $patched) === false) {
		return array(false, 'could not write squid_auth.xml');
	}

	return array(true, 'dropdown option added');
}

function apply_inc() {
	if (!file_exists(SQUID_INC)) {
		return array(false, 'squid.inc not found: is the Squid package installed?');
	}

	$content = file_get_contents(SQUID_INC);

	if (strpos($content, MARK_BEGIN) !== false) {
		return array(true, 'already present');
	}

	/* There is more than one "switch ($auth_method)" in squid.inc: one
	 * validates the form, the other builds the configuration. Only the second
	 * one, inside squid_resync_auth(), must be touched -- so find the function
	 * first and anchor within it. */
	$fn = strpos($content, 'function squid_resync_auth');
	if ($fn === false) {
		return array(false, 'squid_resync_auth() not found; Squid may have changed');
	}

	$needle = 'switch ($auth_method) {';
	$sw = strpos($content, $needle, $fn);
	if ($sw === false) {
		return array(false, 'the auth switch was not found inside squid_resync_auth()');
	}

	if (!backup_once(SQUID_INC)) {
		return array(false, 'could not write a backup of squid.inc');
	}

	$at = $sw + strlen($needle);
	$patched = substr($content, 0, $at) . "\n" . ad_inc_block() . substr($content, $at);

	if (file_put_contents(SQUID_INC, $patched) === false) {
		return array(false, 'could not write squid.inc');
	}

	return array(true, 'authentication case added');
}

function revert_file($file) {
	if (!file_exists($file)) {
		return array(true, 'not present');
	}

	$content = file_get_contents($file);

	if (strpos($content, MARK_BEGIN) === false) {
		return array(true, 'not patched');
	}

	$cleaned = strip_block($content);

	if (file_put_contents($file, $cleaned) === false) {
		return array(false, 'could not write ' . basename($file));
	}

	return array(true, 'reverted');
}

/* ------------------------------------------------------------------ main -- */

$action = $argv[1] ?? 'status';

switch ($action) {
	case 'apply':
		$ok = true;
		foreach (array('squid_auth.xml' => 'apply_xml', 'squid.inc' => 'apply_inc') as $name => $fn) {
			list($good, $msg) = $fn();
			echo sprintf("  %-16s %s\n", $name, $msg);
			$ok = $ok && $good;
		}

		if (!$ok) {
			echo "\nThe patch did not apply cleanly. Squid's own files may have changed.\n";
			echo "Nothing is broken: the Authentication Method dropdown simply will not\n";
			echo "offer Active Directory. Use the documented custom-options method instead.\n";
			exit(1);
		}

		echo "\nDone. Choose Services > Squid Proxy Server > Authentication >\n";
		echo "Authentication Method = 'Active Directory (Samba winbind SSO)' and save.\n";
		exit(0);

	case 'revert':
		foreach (array(SQUID_AUTH_XML, SQUID_INC) as $file) {
			list($good, $msg) = revert_file($file);
			echo sprintf("  %-16s %s\n", basename($file), $msg);
		}
		echo "\nIf the Authentication Method was set to Active Directory, change it to\n";
		echo "something else and save, or Squid will emit no authentication directives.\n";
		exit(0);

	case 'status':
	default:
		$x = is_patched(SQUID_AUTH_XML);
		$i = is_patched(SQUID_INC);

		echo '  squid_auth.xml   ' . ($x ? 'patched' : 'not patched') . "\n";
		echo '  squid.inc        ' . ($i ? 'patched' : 'not patched') . "\n";

		if ($x && $i) {
			echo "\nThe Active Directory option is available in the dropdown.\n";
			exit(0);
		}

		if ($x || $i) {
			echo "\nHALF PATCHED -- run 'apply' to repair. A Squid update usually causes\n";
			echo "this, and leaves authentication broken if the method is set to AD.\n";
			exit(2);
		}

		exit(1);
}
