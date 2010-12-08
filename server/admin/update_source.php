<html>
<head></head>
<body>
<?php

	/*
	 * Author: Andreas Linde <mail@andreaslinde.de>
	 *
	 * Copyright (c) 2009 Andreas Linde & Kent Sutherland. All rights reserved.
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

function end_with_result($result) {
	return $result; 
}

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
                    if (count($matches) >= 7) {
                        $result_source .= $matches[4]." (".$matches[5].":".$matches[6].")";
                    }
                }
			}
		}
	}
	
	return $result_source;
}

$allowed_args = ',';

$link = mysql_connect($server, $loginsql, $passsql)
    or die(end_with_result('No database connection'));
mysql_select_db($base) or die(end_with_result('No database connection'));

foreach(array_keys($_GET) as $k) {
    $temp = ",$k,";
    if(strpos($allowed_args,$temp) !== false) { $$k = $_GET[$k]; }
}

// update jailbreak tag on all crashlogs
$query = "UPDATE ".$dbcrashtable." SET jailbreak=1 WHERE log like '%MobileSubstrate%'";
$result = mysql_query($query) or die(end_with_result('Error in SQL '.$query));

// go through all apps
$queryapps = "SELECT id, bundleidentifier, name FROM ".$dbapptable." ORDER BY bundleidentifier asc, symbolicate desc";
$resultapps = mysql_query($queryapps) or die(end_with_result('Error in SQL '.$queryapps));

$numrowsapps = mysql_num_rows($resultapps);
if ($numrowsapps > 0) {
	// get the status
	while ($rowapps = mysql_fetch_row($resultapps)) {
		$appid = $rowapps[0];
		$bundleidentifier = $rowapps[1];
		$appname = $rowapps[2];

        echo "<h1>".$appname."</h1>";

        // go through all versions
        $queryversions = "SELECT id, version FROM ".$dbversiontable." WHERE bundleidentifier = '".$bundleidentifier."' ORDER BY bundleidentifier asc, version desc, status desc";

        $resultversions = mysql_query($queryversions) or die(end_with_result('Error in SQL '.$queryversions));
        
        $numrowsversions = mysql_num_rows($resultversions);
        if ($numrowsversions > 0) {
            // get the status
            while ($rowversions = mysql_fetch_row($resultversions)) {
                $versionid = $rowversions[0];
                $versionname = $rowversions[1];

                echo "<h3>".$versionname."</h3>";

                // go through all crashes                
                $query0 = "SELECT id, log, applicationname FROM ".$dbcrashtable." WHERE bundleidentifier = '".$bundleidentifier."' and version = '".$versionname."'";
                $result0 = mysql_query($query0) or die(end_with_result('Error in SQL: '.$query0));
                
                $numrows0 = mysql_num_rows($result0);
                if ($numrows0 > 0) {
                    // get the status
                    while ($row0 = mysql_fetch_row($result0)) {
                        $crashid = $row0[0];
                        $logdata = $row0[1];
                		$applicationname = $row0[2];
                        $appcrashtext = "";
                        
                        // this stores the offset which we need for grouping
                        $source_location = "";

                        preg_match('%Application Specific Information:.*?\n(.*?)\n\n%is', $logdata, $appcrashinfo);
                    	if (is_array($appcrashinfo) && count($appcrashinfo) == 2) {
                            $appcrashtext = str_replace("\\", "", $appcrashinfo[1]);
                            $appcrashtext = str_replace("'", "\'", $appcrashtext);
                	    }

                        // extract the block which contains the data of the crashing thread
                        preg_match('%Thread [0-9]+ Crashed:  Dispatch queue: com.apple.main-thread\n(.*?)\n\n%is', $logdata, $matches);
                        $source_location = parseSymbolicated($matches, $applicationname);
                        if ($source_location == "") {
                            $source_location = parseSymbolicated($matches, $bundleidentifier);
                        }
                        if ($source_location == "") {
                            preg_match('%Thread [0-9]+ Crashed:\n(.*?)\n\n%is', $logdata, $matches);
                            $source_location = parseSymbolicated($matches, $applicationname);
                        }
                        if ($source_location == "") {
                            $source_location = parseSymbolicated($matches, $bundleidentifier);
                        }
                        
                        $log_groupid = 0;
                        // found something?
                        if (strlen($source_location) > 0) {
                            // reduce amount by 1 of old group
                            if ($groupid > 0) {
                                $query = "UPDATE ".$dbgrouptable." SET amount=amount-1 WHERE id=".$groupid;
                                $result = mysql_query($query) or die(end_with_result('Error in SQL '.$query));
                            }
                            
                            // get all the known bug patterns for the current app version
                            $query = "SELECT id, fix, amount, description FROM ".$dbgrouptable." WHERE bundleidentifier = '".$bundleidentifier."' and affected = '".$versionname."' and pattern = '".$source_location."'";
                            $result = mysql_query($query) or die(end_with_result('Error in SQL '.$query));
                    
                            $numrows = mysql_num_rows($result);
                            
                            if ($numrows == 1)
                            {
                                // assign this bug to the group
                                $row = mysql_fetch_row($result);
                                $log_groupid = $row[0];
                                $amount = $row[2];
                                $desc = $row[3];
                                
                                mysql_free_result($result);
                                
                                // update the occurances of this pattern
                                $query = "UPDATE ".$dbgrouptable." SET amount=amount+1 WHERE id=".$log_groupid;
                                $result = mysql_query($query) or die(end_with_result('Error in SQL '.$query));
                                
                                if ($desc != "" && $appcrashtext != "") {
                    				$desc = str_replace("'", "\'", $desc);
                                    if (strpos($desc, $appcrashtext) === false) {
                                        $appcrashtext = $desc."\n".$appcrashtext;
                                        $query = "UPDATE ".$dbgrouptable." SET description='".$appcrashtext."' WHERE id=".$log_groupid;                                        
                                        $result = mysql_query($query) or die(end_with_result('Error in SQL '.$query));
                                    }
                                }                       
                            } else if ($numrows == 0) {
                                // create a new pattern for this bug and set amount of occurrances to 1
                                $query = "INSERT INTO ".$dbgrouptable." (bundleidentifier, affected, pattern, amount, latesttimestamp, description) values ('".$bundleidentifier."', '".$versionname."', '".$source_location."', 1, ".time().", '".$appcrashtext."')";
                                $result = mysql_query($query) or die(end_with_result('Error in SQL '.$query));
                                
                                $log_groupid = mysql_insert_id($link);
                            } else {
                            }
                            
                            if ($log_groupid > 0) {
                                $query = "UPDATE ".$dbcrashtable." SET groupid = ".$log_groupid." WHERE id = ".$crashid;
                                $result = mysql_query($query) or die('Error in SQL '.$query);                                
                            }
                            
                            $lastupdate = "";
                            $query2 = "SELECT max(UNIX_TIMESTAMP(timestamp)) FROM ".$dbcrashtable." WHERE groupid = '".$log_groupid."'";
                            $result2 = mysql_query($query2) or die(end_with_result('Error in SQL '.$query2));
                            $numrows2 = mysql_num_rows($result2);
                            if ($numrows2 > 0) {
                                $row2 = mysql_fetch_row($result2);
                                $lastupdate = $row2[0];
                            }
                            mysql_free_result($result2);
                            
                            if ($lastupdate != '') {
                                $query2 = "UPDATE ".$dbgrouptable." SET latesttimestamp = ".$lastupdate." WHERE id = ".$log_groupid;
                                $result2 = mysql_query($query2) or die(end_with_result('Error in SQL '.$query2));
                            }
                        } else {
                            echo $crashid." NOTHING FOUND<br/>";
                        }
                    }
                }
                mysql_free_result($result0);
        
            }
            mysql_free_result($resultversions);        
        }
    }
    mysql_free_result($resultapps);
}

mysql_close($link);

?>
</body>
</html>
