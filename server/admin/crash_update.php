<?php

	/*
	* Author: Andreas Linde <mail@andreaslinde.de>
	*
	* Copyright (c) 2009-2011 Andreas Linde.
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
        $appcrashtext = "";
        
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
    	
        preg_match('%Application Specific Information:.*?\n(.*?)\n\n%is', $logdata, $appcrashinfo);
        if (is_array($appcrashinfo) && count($appcrashinfo) == 2) {
        	$appcrashtext = str_replace("\\", "", $appcrashinfo[1]);
            $appcrashtext = str_replace("'", "\'", $appcrashtext);
        }

        // if the offset string is not empty, we check if the description already contains that text, otherwise add it to the bottom
        if (strlen($crash_group) > 0) {
            // get all the known bug patterns for the current app version
            $query = "SELECT description FROM ".$dbgrouptable." WHERE id = ".$groupid;
            $result = mysql_query($query) or die(xml_for_result(FAILURE_SQL_FIND_KNOWN_PATTERNS));
    
            $numrows = mysql_num_rows($result);
            
            if ($numrows == 1) {
                // assign this bug to the group
                $row = mysql_fetch_row($result);
                $desc = $row[0];
    
                mysql_free_result($result);

				$desc = str_replace("'", "\'", $desc);
                if (strpos($desc, $crash_group) === false) {
                    if ($desc != "") $desc .= "\n\n";
                    $desc .= $crash_group;
                }
                
                if (strpos($desc, $appcrashtext) === false) {
                    if ($desc != "") $desc .= "\n\n";
                    $desc .= $appcrashtext;
                }

                
                // update the occurances of this pattern
                $query = "UPDATE ".$dbgrouptable." SET description = '".$desc."' WHERE id=".$groupid;
               	$result = mysql_query($query) or die(end_with_result('Error in SQL '.$query));
            }
        }
	}
} else {
	echo "error";
}

mysql_close($link);


?>