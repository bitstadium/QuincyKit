<?php

	/*
	* Author: Andreas Linde <mail@andreaslinde.de>
	*
	* Copyright (c) 2009 Andreas Linde. All rights reserved.
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
// Update crash log data for a crash
//
// This script is used by the remote symbolicate process to update
// the database with the symbolicated crash log data for a given
// crash id
//

require_once('../config.php');


function parseSymbolicated($matches, $appString) {
    $result_source = "";
    //make sure $matches[1] exists
	if (is_array($matches) && count($matches) >= 2) {
		$result = explode("\n", $matches[1]);
		foreach ($result as $line) {
			// search for the first occurance of the application name
			if (strpos($line, $appString) !== false && strpos($line, "uncaught_exception_handler (PLCrashReporter.m:") === false) {
                // 1              WorldViewLive         0x00036e51        -[LiveUpdateReader databaseActions:] (LiveUpdateReader.m:62)
                // ([0-9]+) \s+   ([^\s]+)        \s+   ([^\s]+)    \s+   -\[ ([^\s]+)    \s+ ([^\s]+)     \] \s+ \( ([^\s]+) : ([^\s]+) \)
				preg_match('/([0-9]+)\s+([^\s]+)\s+([^\s]+)\s+-\[([^\s]+)\s+([^\s]+)\]\s+\(([^\s]+):([^\s]+)\)/', $line, $matches);
                if (count($matches) >= 8) {
                    $result_source .= "[".$matches[4]." ".$matches[5]."] (".$matches[6].":".$matches[7].")";
                } else {
                    preg_match('/([0-9]+)\s+([^\s]+)\s+([^\s]+)\s+([^\s]+)\s+\(([^\s]+):([^\s]+)\)/', $line, $matches);
                    print_r($matches);
                    if (count($matches) >= 6) {
                        $result_source .= $matches[4]." (".$matches[5].":".$matches[6].")";
                    }
                }
			}
		}
	}
    if ($result_source != "")
        echo $result_source;
	
	return $result_source;
}


$allowed_args = ',id,log,';

$link = mysql_connect($server, $loginsql, $passsql)
    or die('error');
mysql_select_db($base) or die('error');

foreach(array_keys($_POST) as $k) {
    $temp = ",$k,";
    if(strpos($allowed_args,$temp) !== false) { $$k = $_POST[$k]; }
}

if (!isset($id)) $id = "";
if (!isset($log)) $log = "";

echo  $id." ".$log."\n";

if ($id == "" || $log == "") {
	mysql_close($link);
	die('error');
}

$query = "UPDATE ".$dbcrashtable." SET log = '".mysql_real_escape_string($log)."' WHERE id = ".$id;
$result = mysql_query($query) or die('Error in SQL '.$dbcrashtable);

if ($result) {
	$query = "UPDATE ".$dbsymbolicatetable." SET done = 1 WHERE crashid = ".$id;
	$result = mysql_query($query) or die('Error in SQL '.$query);
	
	if ($result)
		echo "success";
	else
		echo "error";

    $applicationname = "";
    $groupid = 0;
    $bundleidentifier = "";
    $version = "";
    
    // get app name
    $query = "SELECT applicationname, groupid, bundleidentifier, version FROM ".$dbcrashtable." WHERE id = ".$id;
	$result = mysql_query($query) or die('Error in SQL '.$dbsymbolicatetable);
    
    $numrows = mysql_num_rows($result);
    if ($numrows > 0) {
    	$row = mysql_fetch_row($result);
   		$applicationname = $row[0];
   		$groupid = $row[1];
   		$bundleidentifier = $row[2];
   		$version = $row[3];
    }
    mysql_free_result($result);

	// get new grouping
    if ($applicationname != "" && $bundleidentifier != "" && $version != "") {
    	// this stores the offset which we need for grouping
        $crash_group = "";
        
        // extract the block which contains the data of the crashing thread
        preg_match('%Thread [0-9]+ Crashed:.*?\n(.*?)\n\n%is', $log, $matches);
        $crash_offset = parseSymbolicated($matches, $applicationname);	
        if ($crash_group == "") {
            $crash_group = parseSymbolicated($matches, $bundleidentifier);
        }
        if ($crash_group == "") {
            preg_match('%Thread [0-9]+ Crashed:\n(.*?)\n\n%is', $log, $matches);
            $crash_group = parseSymbolicated($matches, $applicationname);
        }
        if ($crash_group == "") {
            $crash_group = parseSymbolicated($matches, $bundleidentifier);
        }
    
    	// increase new group by 1
	
    	// stores the group this crashlog is associated to, by default to none
        $log_groupid = 0;
        
        // if the offset string is not empty, we try a grouping
        if (strlen($crash_group) > 0) {
            // reduce amount by 1 of old group
            if ($groupid > 0) {
                $query = "UPDATE ".$dbgrouptable." SET amount=amount-1 WHERE id=".$groupid;
                $result = mysql_query($query) or die(xml_for_result(FAILURE_SQL_UPDATE_PATTERN_OCCURANCES));
                
                $lastupdate = "";
                $query2 = "SELECT max(UNIX_TIMESTAMP(timestamp)) FROM ".$dbcrashtable." WHERE groupid = '".$groupid."'";
                $result2 = mysql_query($query2) or die(end_with_result('Error in SQL '.$query2));
                $numrows2 = mysql_num_rows($result2);
                if ($numrows2 > 0) {
                    $row2 = mysql_fetch_row($result2);
                    $lastupdate = $row2[0];
                }
                mysql_free_result($result2);
                
                if ($lastupdate != '') {
                    $query2 = "UPDATE ".$dbgrouptable." SET latesttimestamp = ".$lastupdate." WHERE id = ".$groupid;
                    $result2 = mysql_query($query2) or die(end_with_result('Error in SQL '.$query2));
                }
            }
            
            // get all the known bug patterns for the current app version
            $query = "SELECT id, fix, amount FROM ".$dbgrouptable." WHERE bundleidentifier = '".$bundleidentifier."' and affected = '".$version."' and pattern = '".mysql_real_escape_string($crash_group)."'";
            $result = mysql_query($query) or die(xml_for_result(FAILURE_SQL_FIND_KNOWN_PATTERNS));
    
            $numrows = mysql_num_rows($result);
            
            if ($numrows == 1)
            {
                // assign this bug to the group
                $row = mysql_fetch_row($result);
                $log_groupid = $row[0];
                $amount = $row[2];
    
                mysql_free_result($result);
    
                // update the occurances of this pattern
                $query = "UPDATE ".$dbgrouptable." SET amount=amount+1, latesttimestamp = ".time()." WHERE id=".$log_groupid;
                $result = mysql_query($query) or die(xml_for_result(FAILURE_SQL_UPDATE_PATTERN_OCCURANCES));
            } else if ($numrows == 0) {
                // create a new pattern for this bug and set amount of occurrances to 1
                $query = "INSERT INTO ".$dbgrouptable." (bundleidentifier, affected, pattern, amount, latesttimestamp) values ('".$bundleidentifier."', '".$version."', '".$crash_group."', 1, ".time().")";
                $result = mysql_query($query) or die(xml_for_result(FAILURE_SQL_ADD_PATTERN));
                
                $log_groupid = mysql_insert_id($link);
            }
            
            if ($log_groupid > 0) {
                $query = "UPDATE ".$dbcrashtable." SET groupid = ".$log_groupid." WHERE id = ".$id;
                $result = mysql_query($query) or die('Error in SQL '.$dbcrashtable);
            }
        }
	}
} else {
	echo "error";
}

mysql_close($link);


?>