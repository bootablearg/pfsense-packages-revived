<?php

/*
 * samba_ad.priv.inc
 *
 * Privilege definition for the Samba AD package.
 *
 * Copyright (c) 2026 pfsense-packages-revived contributors
 * All rights reserved.
 *
 * Derived from the pf2ad project (BSD 2-Clause), branch 2.4.3-SAMBA4.
 * See LICENSE for the full license text.
 *
 * Without this file the package's pages exist but cannot be delegated: the
 * User Manager has no privilege to grant, so only administrators can reach
 * them. Every Netgate package ships one; so does this.
 */

global $priv_list;

$priv_list['page-services-sambaad'] = array();
$priv_list['page-services-sambaad']['name'] = "WebCfg - Services: Samba AD package";
$priv_list['page-services-sambaad']['descr'] = "Allow access to the Samba AD package GUI";

$priv_list['page-services-sambaad']['match'] = array();
$priv_list['page-services-sambaad']['match'][] = "pkg_edit.php?xml=samba_ad.xml*";
$priv_list['page-services-sambaad']['match'][] = "diag_samba_ad.php*";
?>
