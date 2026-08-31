<?php
/*
 * diag_samba_ad.php
 *
 * Diagnostics page for the Samba AD package.
 *
 * Copyright (c) 2013-2016 Luiz Gustavo S. Costa <me@luizgustavo.pro.br>
 * Copyright (c) 2026 pfsense-samba-ad contributors
 * All rights reserved.
 *
 * Derived from the pf2ad project (BSD 2-Clause), branch 2.4.3-SAMBA4.
 * See LICENSE for the full license text.
 */

require_once('guiconfig.inc');
require_once('/usr/local/pkg/samba_ad.inc');

/*
 * Diagnostic actions.
 *
 * Every command below is a fixed string. Nothing from the request ever reaches
 * the shell: the request only selects which of these canned commands to run.
 * That is deliberate -- it makes command injection structurally impossible
 * rather than merely escaped-away.
 */
$actions = array(
	'testjoin' => array(
		'label' => gettext('Verify domain membership'),
		'help'  => gettext('Asks the domain controller whether this machine account is still valid.'),
		'cmd'   => '/usr/local/bin/net ads testjoin -s /usr/local/etc/smb4.conf 2>&1',
	),
	'wbinfo_ping' => array(
		'label' => gettext('Ping winbindd'),
		'help'  => gettext('Checks that the local winbindd process is answering on its socket.'),
		'cmd'   => '/usr/local/bin/wbinfo -p 2>&1',
	),
	'wbinfo_trust' => array(
		'label' => gettext('Check trust secret'),
		'help'  => gettext('Validates the shared secret between this machine and the domain.'),
		'cmd'   => '/usr/local/bin/wbinfo -t 2>&1',
	),
	'wbinfo_domain' => array(
		'label' => gettext('Show domain info'),
		'help'  => gettext('Displays the domain winbindd believes it belongs to.'),
		'cmd'   => '/usr/local/bin/wbinfo --domain-info=. 2>&1',
	),
	'keytab' => array(
		'label' => gettext('List Kerberos keytab'),
		'help'  => gettext('Shows the principals stored in /etc/krb5.keytab.'),
		'cmd'   => '/usr/bin/klist -k /etc/krb5.keytab 2>&1',
	),
	'smbconf' => array(
		'label' => gettext('Validate smb.conf'),
		'help'  => gettext('Runs testparm to check the generated configuration for errors.'),
		'cmd'   => '/usr/local/bin/testparm -s /usr/local/etc/smb4.conf 2>&1',
	),
);

$output = '';
$ran = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['action'])) {
	$key = $_POST['action'];

	if (isset($actions[$key])) {
		$ran = $actions[$key]['label'];
		$lines = array();
		$rc = 0;
		exec($actions[$key]['cmd'], $lines, $rc);
		$output = implode("\n", $lines);

		if ($output === '') {
			$output = sprintf(gettext('(no output; exit status %d)'), $rc);
		}
	} else {
		$output = gettext('Unknown action.');
	}
}

$status = samba_ad_squid_status();

$pgtitle = array(gettext('Services'), gettext('Samba AD'), gettext('Diagnostics'));
include('head.inc');

/* Tab bar mirroring the package XML so both pages feel like one screen. */
$tab_array = array();
$tab_array[] = array(gettext('Settings'), false, '/pkg_edit.php?xml=samba_ad.xml&id=0');
$tab_array[] = array(gettext('Diagnostics'), true, '/diag_samba_ad.php');
display_top_tabs($tab_array);

/* ---------------------------------------------------------------- status --- */
?>
<div class="panel panel-default">
	<div class="panel-heading"><h2 class="panel-title"><?= gettext('Status') ?></h2></div>
	<div class="panel-body table-responsive">
		<table class="table table-striped table-hover table-condensed">
			<tbody>
<?php
$rows = array(
	array(
		gettext('winbindd running'),
		$status['winbindd_running'],
		gettext('The daemon that answers all AD identity lookups.'),
	),
	array(
		gettext('Kerberos keytab present'),
		$status['keytab_present'],
		gettext('Required for Kerberos/Negotiate authentication.'),
	),
	array(
		gettext('winbindd privileged pipe'),
		$status['privileged_dir_ok'],
		gettext('Directory Squid&apos;s helper needs in order to talk to winbindd.'),
	),
	array(
		gettext('ntlm_auth helper present'),
		$status['ntlm_auth_present'],
		gettext('Shipped with Samba; used by Squid for NTLM and Negotiate.'),
	),
	array(
		gettext('Squid package installed'),
		$status['squid_installed'],
		gettext('Optional. This package works without Squid.'),
	),
	array(
		gettext('ntlm_auth linked into Squid'),
		$status['squid_helper_linked'],
		gettext('Only relevant when Squid is installed.'),
	),
);

foreach ($rows as $row) {
	$icon = $row[1]
		? '<i class="fa fa-check text-success"></i> ' . gettext('yes')
		: '<i class="fa fa-times text-danger"></i> ' . gettext('no');

	/* Squid rows are informational: this package does not require Squid, so a
	 * "no" there is not a fault condition. */
	if (!$row[1] && in_array($row[0], array(gettext('Squid package installed'), gettext('ntlm_auth linked into Squid')), true)) {
		$icon = '<i class="fa fa-minus text-muted"></i> ' . gettext('not in use');
	}

	echo '<tr><td><strong>' . htmlspecialchars($row[0]) . '</strong></td>';
	echo '<td>' . $icon . '</td>';
	echo '<td class="text-muted">' . $row[2] . '</td></tr>' . "\n";
}
?>
			</tbody>
		</table>
	</div>
</div>

<div class="panel panel-default">
	<div class="panel-heading"><h2 class="panel-title"><?= gettext('Tests') ?></h2></div>
	<div class="panel-body">
		<form method="post" action="/diag_samba_ad.php">
<?php foreach ($actions as $key => $action): ?>
			<button type="submit" name="action" value="<?= htmlspecialchars($key) ?>"
				class="btn btn-sm btn-primary" title="<?= htmlspecialchars($action['help']) ?>">
				<?= htmlspecialchars($action['label']) ?>
			</button>
<?php endforeach; ?>
		</form>
	</div>
</div>

<?php if ($output !== ''): ?>
<div class="panel panel-default">
	<div class="panel-heading">
		<h2 class="panel-title"><?= htmlspecialchars($ran) ?></h2>
	</div>
	<div class="panel-body">
		<pre><?= htmlspecialchars($output) ?></pre>
	</div>
</div>
<?php endif; ?>

<?php include('foot.inc'); ?>
