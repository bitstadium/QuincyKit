<?php

	/*
	 * Author: Andreas Linde <mail@andreaslinde.de>
	 *
	 * Copyright (c) 2009-2014 Andreas Linde & Kent Sutherland.
	 * All rights reserved.
	 *
	 * Permission is hereby granted, free of charge, to any person
	 * obtaining a copy of this software and associated documentation
	 * files (the "Software"), to deal in the Software without
	 * restriction, including without limitation the rights to use,
	 * copy, modify, merge, publish, distribute, sublicense, and/or sell
	 * copies of the Software, and to permit persons to whom the
	 * Software is furnished to do so, subject to the following
	 * conditions:
	 *
	 * The above copyright notice and this permission notice shall be
	 * included in all copies or substantial portions of the Software.
	 *
	 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
	 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
	 * OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
	 * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
	 * HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
	 * WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
	 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
	 * OTHER DEALINGS IN THE SOFTWARE.
	 */

//
// Download a crash
//
// This script downloads a given crash to a local file
//

require_once('../config.php');
require_once('common.inc');

$allowed_args = ',bundleidentifier,version,groupid,';

$link = mysql_connect($server, $loginsql, $passsql)
    or die(end_with_result('No database connection'));
mysql_select_db($base) or die(end_with_result('No database connection'));

foreach(array_keys($_GET) as $k) {
    $temp = ",$k,";
    if(strpos($allowed_args,$temp) !== false) { $$k = $_GET[$k]; }
}

if (!isset($bundleidentifier)) $bundleidentifier = "";
if (!isset($version)) $version = "";
if (!isset($groupid)) $groupid = "0";

if ($bundleidentifier == "" || $version == "") die(end_with_result('Wrong parameters'));

$query1 = "SELECT id, applicationname FROM ".$dbcrashtable." WHERE groupid = '".$groupid."' and version = '".$version."' and bundleidentifier = '".$bundleidentifier."'";
$result1 = mysql_query($query1) or die(end_with_result('Error in SQL '.$query1));

$numrows1 = mysql_num_rows($result1);
if ($numrows1 > 0) {
    // get the status
    while ($row1 = mysql_fetch_row($result1)) {
        $crashid = $row1[0];
        $applicationname = $row1[1];
	    
	    // get the log data
        $logdata = "";

   	    $query = "SELECT log FROM ".$dbcrashtable." WHERE id = '".$crashid."' ORDER BY systemversion desc, timestamp desc LIMIT 1";
        $result = mysql_query($query) or die(end_with_result('Error in SQL '.$query));

        $numrows = mysql_num_rows($result);
        if ($numrows > 0) {
            // get the status
            $row = mysql_fetch_row($result);
            $logdata = $row[0];
	
            mysql_free_result($result);
        }
        
        $crash["bundleidentifier"] = $bundleidentifier;
        $crash["version"] = $version;
        $crash["logdata"] = $logdata;
        $crash["id"] = $crashid;
        $error = groupCrashReport($crash, $link, NOTIFY_OFF);
        if ($error != "") {
            die(end_with_result($error));
        }        
    }
	    
    mysql_free_result($result1);
}

mysql_close($link);
?>
<html>
<head>
    <META http-equiv="refresh" content="0;URL=groups.php?&bundleidentifier=<?php echo $bundleidentifier ?>&version=<?php echo $version ?>">
</head>
<body>
Redirecting...
</body>
</html>
