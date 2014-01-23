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
// This part is responsible common used functions
//

function show_header($title)
{
    global $admintitle;
    
    echo '<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML  4.01//EN" "http://www.w3.org/TR/html4/strict.dtd">';
    echo '<html><head><title>'.$admintitle.' '.$title.'</title>';
    echo '<link rel="stylesheet" href="blueprint/screen.css" type="text/css" media="screen, projection"><link rel="stylesheet" href="blueprint/print.css" type="text/css" media="print"><!--[if IE]><link rel="stylesheet" href="blueprint/ie.css" type="text/css" media="screen, projection"><![endif]--><link rel="stylesheet" href="blueprint/plugins/buttons/screen.css" type="text/css" media="screen, projection">';
    echo '<link rel="stylesheet" type="text/css" href="css/layout.css">';
    echo '<link rel="stylesheet" type="text/css" href="css/style.css">';
    echo "<script type='text/javascript' src='https://ajax.googleapis.com/ajax/libs/jquery/1.4.3/jquery.min.js'></script>";
    echo "<script type='text/javascript' src='https://ajax.googleapis.com/ajax/libs/jqueryui/1.8.6/jquery-ui.min.js'></script>";
    echo "<script type='text/javascript' src='js/jquery.chromatable.js'></script>";
    echo "<script type='text/javascript' src='js/functions.js'></script>";
?>
<!--[if IE]><script language="javascript" type="text/javascript" src="js/excanvas.min.js"></script><![endif]-->
<script language="javascript" type="text/javascript" src="js/jquery.jqplot.min.js"></script>
<script language="javascript" type="text/javascript" src="js/jqplot.barRenderer.min.js"></script>
<script language="javascript" type="text/javascript" src="js/jqplot.categoryAxisRenderer.min.js"></script>
<script language="javascript" type="text/javascript" src="js/jqplot.dateAxisRenderer.min.js"></script>
<script type="text/javascript" src="js/jqplot.canvasTextRenderer.min.js"></script>
<script type="text/javascript" src="js/jqplot.canvasAxisTickRenderer.min.js"></script>
<script type="text/javascript" src="js/jqplot.highlighter.min.js"></script>
<script type="text/javascript" src="js/jqplot.pointLabels.min.js"></script>
<link rel="stylesheet" type="text/css" href="css/jquery.jqplot.css" />
<?php
    echo '</head><body><div id="container" class="container prepend-top append-bottom">';
    echo '<h1>'.$admintitle.'</h1>';
}

function end_with_result($result)
{
	return '<html><body>'.$result.'</body></html>'; 
}

function init_database()
{
    global $server, $loginsql, $passsql, $base;

    $GLOBALS['link'] = mysql_connect($server, $loginsql, $passsql) or die(end_with_result('No database connection'));
    mysql_select_db($base) or die(end_with_result('No database connection'));
}


function parse_parameters($allowed_args)
{
    foreach(array_keys($_GET) as $k) {
        $temp = ",$k,";
        if(strpos($allowed_args,$temp) !== false) { $GLOBALS[$k] = $_GET[$k]; }
    }
}

function parse_parameters_post($allowed_args)
{
    foreach(array_keys($_POST) as $k) {
        $temp = ",$k,";
        if(strpos($allowed_args,$temp) !== false) { $GLOBALS[$k] = $_POST[$k]; }
    }
}


function add_option($text, $value, $currentvalue)
{
    echo '<option value="'.$value.'"';
    if ($currentvalue == $value)
        echo " selected";
    echo '>'.$text.'</option>';
}

function create_link($text, $link, $button, $variables)
{    
    $result = "";
    $result .= '<a href="'.$link;
    if (strpos($variables,'?') !== false)
    {
        $result .= $variables;
    } else {
        $result .= '?';
        $vars = explode(',', $variables);
        
        $i = 0;
        foreach(array_keys($vars) as $k) {
            if (strpos($vars[$k], '=') === false)
            {
                if (isset($GLOBALS[$vars[$k]]) && $GLOBALS[$vars[$k]] != "") {
                    if ($i > 0) {
                        $result .= '&';
                    }
                    $result .= $vars[$k].'='.$GLOBALS[$vars[$k]];
                }
            } else {
                if ($i > 0) {
                    $result .= '&';
                }
                $result .= $vars[$k];
            }
            $i++;
        }
    }
    $result .= '"';
    
    if ($button)
        $result .= ' class="button"';
    $result .= '>'.$text.'</a>';
    
    return $result;
}

function show_search($text, $currenttype)
{
    global $bundleidentifier, $version;
    
    echo '<form name="search" action="crashes.php" method="get">';
    echo '<input type="hidden" name="bundleidentifier" value="'.$bundleidentifier.'"/>';
    if ($version != "")
        echo '<input type="hidden" name="version" value="'.$version.'"/>';
    echo '<input type="search" placeholder="Search this" name="search" size="45" maxlength="100"';
    if ($text != "" && $currenttype != "") echo ' value="'.$text.'"';
    echo '/>';
    echo '<select name="type">';
    add_option('User ID', SEARCH_TYPE_USERID, $currenttype);
    add_option('User Name', SEARCH_TYPE_USERNAME, $currenttype);
    add_option('User Email', SEARCH_TYPE_CONTACT, $currenttype);
    add_option('Crash ID', SEARCH_TYPE_ID, $currenttype);
    add_option('Crash Log', SEARCH_TYPE_CRASHLOG, $currenttype);
    add_option('Crash Description', SEARCH_TYPE_DESCRIPTION, $currenttype);
    echo '</select><button type="submit" class="button" style="float:right; margin-right: 300px; margin-top:2px">Search</button>';
    echo '</form>';
}

function currentPageURL()
{
    $pageURL = 'http';
    if (@$_SERVER["HTTPS"] == "on") {$pageURL .= "s";}
    $pageURL .= "://";
    if ($_SERVER["SERVER_PORT"] != "80") {
        $pageURL .= $_SERVER["SERVER_NAME"].":".$_SERVER["SERVER_PORT"].$_SERVER["REQUEST_URI"];
    } else {
        $pageURL .= $_SERVER["SERVER_NAME"].$_SERVER["REQUEST_URI"];
    }
    return $pageURL;
}

function create_issue($bundleidentifier, $issuelink)
{
    global $dbapptable, $createIssueTitle;
    
    $query = "SELECT issuetrackerurl FROM ".$dbapptable." WHERE bundleidentifier = '".$bundleidentifier."'";
    $result = mysql_query($query) or die(end_with_result('Error in SQL '.$query));

    $numrows = mysql_num_rows($result);
    if ($numrows > 0) {
        // get the status
        while ($row = mysql_fetch_row($result))
        {
            if ($row[0] != "")
            {
                $issuetrackerurl = $row[0];
                $issuetrackerurl = str_replace('%subject%', urlencode($createIssueTitle), $issuetrackerurl);
                $issuetrackerurl = str_replace('%description%', urlencode('Crash Log: '.$issuelink), $issuetrackerurl);
                return "<a href='".$issuetrackerurl."' target='_new' class='button'>New issue</a>";
            }
        }
    }
    
    return '';
}  

function stringEndsWith($haystack,$needle,$case=true) {
    if($case){return (strcmp(substr($haystack, strlen($haystack) - strlen($needle)),$needle)===0);}
    return (strcasecmp(substr($haystack, strlen($haystack) - strlen($needle)),$needle)===0);
}

function parseThread($regEx, $data) {
    $stackTrace = array();
    preg_match($regEx, $data, $matches);

    if (is_array($matches) && count($matches) >= 2) {
        $lines = explode("\n", $matches[1]);
        foreach ($lines as $line) {
            preg_match("/^(\d+)\s+(\S.*?)\s+(0x\w+)\s+(.*)\s*$/is", $line, $lineMatches);
            if (is_array($lineMatches) && count($lineMatches) >= 2) {
                $stackFrame["number"] = $lineMatches[1];
                $stackFrame["binary"] = $lineMatches[2];
                $stackFrame["address"] = $lineMatches[3];
                $stackFrame["description"] = $lineMatches[4];
                $stackTrace[] = $stackFrame;
            }
        }
    }
    
    return $stackTrace;
}

function utf8_urldecode($str) {
    return html_entity_decode(preg_replace("/%u([0-9a-f]{3,4})/i", "&#x\\1;", urldecode($str)), null, 'UTF-8');
}

function crashLogGroupArray($logdata) {
    $reason = "";
    $groupAddress = "";
    $location = "";
    $exceptionType = "";
    $binaryies = "";
    $jailbreak = 0;
    
    // get the app path
    $appPath = "";
    preg_match('/^Path:\s*(.*?)$/mis', $logdata, $matches);
    if (is_array($matches) && count($matches) >= 2) {
        $appPath = $matches[1];
        
        // remove app name
        $appPath = substr($appPath, 0, strrpos($appPath, "/"));
        
        // remove binary container (mac only)
        if (substr($appPath, strlen($appPath)-4) != ".app") {
            $appPath = substr($appPath, 0, strrpos($appPath, "/"));
        }
    }
    
    // get the exception type
    preg_match('/^Exception Type:\s*(.*?)$/mis', $logdata, $matches);
    if (is_array($matches) && count($matches) >= 2) {
        $exceptionType = $matches[1];        
    }
    
    // find the apps binaries (including frameworks) and address ranges
    $binaryImages = array();
    preg_match('/Binary Images:.*?\n(.*?)\z/mis', $logdata, $matches);
    if (is_array($matches) && count($matches) >= 2) {
        $lines = explode("\n", $matches[1]);
        foreach ($lines as $line) {
            // we limit this to report version 104
            $architectures = 'armv6|i386|x86_64|ppc|ppc64|armv4t|armv5|armv6|armv7|armv7s|arm64|arm-unknown';
            preg_match('/^\s*(\w+)\s*-\s*(\w+)\s*(\+)?(.+)\s+('.$architectures.')\s+\<?([0-9A-Fa-f]{32})?>?\s*(.*)\s*$/i', $line, $binaryImageMatches);
            if (is_array($binaryImageMatches) && count($binaryImageMatches) >= 2) {
                $image["loadAddress"] = $binaryImageMatches[1];
                $image["endAddress"] = $binaryImageMatches[2];
                $image["binary"] = $binaryImageMatches[4];
                $image["platform"] = $binaryImageMatches[5];
                $image["uuid"] = $binaryImageMatches[6];
                $image["path"] = $binaryImageMatches[7];
                
              	if (strpos($image["path"], "MobileSubstrate") !== false ||
                    strpos($image["path"], "CydiaSubstrate") !== false ||
                    strpos($image["binary"], "MobileSubstrate") !== false ||
                    strpos($image["binary"], "CydiaSubstrate") !== false)
                {
                    $jailbreak = 1;
                }
                
                if (($appPath != "" && strpos($image["path"], $appPath) !== false) || (count($binaryImages) == 0))  {
                    if (count($binaryImages) == 0) {
                        // this is the actual app binary
                        $image["type"] = 0;
                    } else {
                        // this is an app bundled framework
                        $image["type"] = 1;
                    } 
                } else {
                    $image["type"] = 2;                        
                }
                $binaryImages[] = $image;
            }
        }
    }
    
    // get the exception reason
    preg_match('/Application Specific Information:.*?\n(.*?)\n\n/mis', $logdata, $matches);
    if (is_array($matches) && count($matches) >= 2) {
        $reason = utf8_urldecode($matches[1]);
        $reason = str_replace("*** Terminating app due to uncaught exception ", "", $reason);
        $tempReason = str_replace("\n", "", $reason);
        preg_match('/^(objc\[[^\]]*\]\: garbage collection is OFF)$/mis', $tempReason, $matches);
        if (is_array($matches) && count($matches) >= 2) {
            $reason = "No reason found";
        }
        $reason = trim($reason);
    }
    
    // get the crashing strack trace
    $stackTrace = parseThread('/Application Specific Backtrace:.*?\n(.*?)\n\n/mis', $logdata);
    if (count($stackTrace) == 0) {
        $stackTrace = parseThread('/Last Exception Backtrace:.*?\n(.*?)\n\n/mis', $logdata);
    }
    if (count($stackTrace) == 0) {
        $stackTrace = parseThread('/Thread [0-9]+ Crashed:.*?\n(.*?)\n\n/mis', $logdata);
    }
    if (count($stackTrace) == 0) {
        $stackTrace = parseThread('/Thread [0-9]+ Crashed:\n(.*?)\n\n/mis', $logdata);
    }
    
    if (count($stackTrace) > 0) {
        $binariesArray = array();
        // if we have a stack trace, analyze it
        foreach ($stackTrace as $stackFrame) {
            $binariesArray[] = $stackFrame["binary"];
            
            $description = $stackFrame["description"];
            // if the stack trace contains a string from PLCrashReporter, then this is not the crash reason, so ignore it
            if (strpos($description, "PLCrash") === false && strpos($description, "uncaught_exception_handler") === false) {
                
                $stackFrameBinary = $stackFrame["binary"];
                if (substr($stackFrameBinary, strlen($stackFrameBinary) - 3) == "...") {
                    $stackFrameBinary = substr($stackFrameBinary, strlen($stackFrameBinary) - 3);
                }
                
                // get the matching binary image
                $binaryImage = array();
                foreach ($binaryImages as $aBinaryImage) {
                    if (substr($aBinaryImage["binary"], 0, strlen($stackFrameBinary)) == $stackFrameBinary) {
                        // we only care about app specific frames, incl. the frameworks the app provides
                        if ($aBinaryImage["type"] < 2) {
                            $binaryImage = $aBinaryImage;
                            break;
                        }
                    }
                }
                
                if (count($binaryImage) > 0) {
                    $location = $description;
                    // we use the normalized address for grouping
                    if ($stackFrame["address"] > $binaryImage["loadAddress"]) {
                        $groupAddress = dechex(hexdec($stackFrame["address"]) - hexdec($binaryImage["loadAddress"]));
                    } else {
                        $groupAddress = $stackFrame["address"];
                    }
                    // we only care about the top most entry
                    break;
                }                
            }                
        }
        $binariesArray = array_unique($binariesArray);
        sort($binariesArray, SORT_STRING | SORT_FLAG_CASE);
        $binaries = implode(",", $binariesArray);
    } else {
        // no crashing thread? weird. we simply group by reason only then
        
    }
    
    if (strlen($reason) > 0) {
        $resultArray["reason"] = $reason;
    } else {
        if (strlen($binaries) > 0) {
            $resultArray["reason"] = "No Reason found. Full stack trace includes ".$binaries.".";
        } else {
            
        }
    }
    $resultArray["groupAddress"] = $groupAddress;
    $resultArray["location"] = $location;
    $resultArray["exceptionType"] = $exceptionType;
    $resultArray["jailbreak"] = $jailbreak;
    
    return $resultArray;
}

function groupCrashReport($crash, $dblink, $notify) {
    global $dbversiontable, $dbgrouptable, $dbcrashtable, $notify_default_version;
    
    $bundleidentifier = $crash["bundleidentifier"];
    $version = $crash["version"];
    $logdata = $crash["logdata"];
    
    $groupingArray = crashLogGroupArray($logdata);
    $crashReason = $groupingArray["reason"];
    $crashLocation = $groupingArray["location"];
    $crashException = $groupingArray["exceptionType"];
  	$jailbreak = $groupingArray["jailbreak"];
    
    $crashPattern = "";
    
    if ($groupingArray["groupAddress"] != "") {
        $crashPattern = $groupingArray["groupAddress"];
    } else if ($crashLocation != "") {
        $crashPattern = $crashLocation;
    } else if ($crashReason != "") {
        $crashPattern = substr($crashReason, 0, 240);
    } else if ($crashException != "") {
        $crashPattern = $crashException;
    }
        
    // stores the group this crashlog is associated to, by default to none
    $log_groupid = 0;

    // check if the version is already added and the status of the version and notify status
    $query = "SELECT id, status, notify FROM ".$dbversiontable." WHERE bundleidentifier = '".$bundleidentifier."' and version = '".$version."'";
    $result = mysql_query($query);
    if (!$result) return FAILURE_SQL_CHECK_VERSION_EXISTS;
    
    $numrows = mysql_num_rows($result);
    if ($numrows == 0) {
        // version is not available, so add it with status VERSION_STATUS_AVAILABLE
        $query = "INSERT INTO ".$dbversiontable." (bundleidentifier, version, status, notify) values ('".$bundleidentifier."', '".$version."', ".VERSION_STATUS_UNKNOWN.", ".$notify_default_version.")";
        $result = mysql_query($query);
        if (!$result) return FAILURE_SQL_ADD_VERSION;
    } else {
        $row = mysql_fetch_row($result);
        $version_status = $row[1];
        $notify = $row[2];
        mysql_free_result($result);
    }
    
    // if the offset string is not empty, we try a grouping
    if (strlen($crashPattern) > 0) {
        // get all the known bug patterns for the current app version
        $query = "SELECT id, amount FROM ".$dbgrouptable." WHERE affected = '".$version."' and pattern = '".mysql_real_escape_string($crashPattern)."'";
        $result = mysql_query($query);
        if (!$result) return FAILURE_SQL_FIND_KNOWN_PATTERNS;

        $numrows = mysql_num_rows($result);
        
        if ($numrows == 1) {
            // assign this bug to the group
            $row = mysql_fetch_row($result);
            $log_groupid = $row[0];
            $amount = $row[1];

            mysql_free_result($result);

            // update the occurances of this pattern
            $query = "UPDATE ".$dbgrouptable." SET amount=amount+1, latesttimestamp = ".time().", location='".mysql_real_escape_string($crashLocation)."', exception='".mysql_real_escape_string($crashException)."', reason='".mysql_real_escape_string($crashReason)."' WHERE id=".$log_groupid;
            $result = mysql_query($query);
            if (!$result) return FAILURE_SQL_UPDATE_PATTERN_OCCURANCES;

            if ($notify_amount_group > 1 && $notify_amount_group == $amount && $notify >= NOTIFY_ACTIVATED && $version_status != VERSION_STATUS_DISCONTINUED) {
                // send push notification
                if ($push_activated) {
                    $prowl->push(array(
                        'application'=>$applicationname,
                        'event'=>'Critical Crash',
                        'description'=>'Version '.$version.' Pattern '.$crash_offset.' has a MORE than '.$notify_amount_group.' crashes!\n Sent at ' . date('H:i:s'),
                        'priority'=>0,
                    ),true);
                }
                
                // send boxcar notification
                if($boxcar_activated) {
                	$boxcar = new Boxcar($boxcar_uid, $boxcar_pwd);
                	print_r($boxcar->send($crash["appname"], 'Version '.$crash["version"].' Pattern '.$crash_offset.' has a MORE than '.$notify_amount_group.' crashes!\n Sent at ' . date('H:i:s')));
                }
                
                // send email notification
                if ($mail_activated) {
                    $subject = $applicationname.': Critical Crash';
                    
                    if ($crash_url != '')
                        $url = "Link: ".$crash_url."admin/crashes.php?bundleidentifier=".$bundleidentifier."&version=".$version."&groupid=".$log_groupid."\n\n";
                    else
                        $url = "\n";
                    $message = "Version ".$version." Pattern ".$crash_offset." has a MORE than ".$notify_amount_group." crashes!\n".$url."Sent at ".date('H:i:s');

                    mail($notify_emails, $subject, $message, 'From: '.$mail_from. "\r\n");
                }
            }

            mysql_free_result($result);
        } else if ($numrows == 0) {
            // create a new pattern for this bug and set amount of occurrances to 1
            $query = "INSERT INTO ".$dbgrouptable." (bundleidentifier, affected, pattern, location, exception, reason, amount, latesttimestamp) values ('".$bundleidentifier."', '".$version."', '".$crashPattern."', '".mysql_real_escape_string($crashLocation)."', '".mysql_real_escape_string($crashException)."', '".mysql_real_escape_string($crashReason)."', 1, ".time().")";
            $result = mysql_query($query);
            if (!$result) return FAILURE_SQL_ADD_PATTERN;

            $log_groupid = mysql_insert_id($dblink);

            if ($version_status != VERSION_STATUS_DISCONTINUED && $notify == NOTIFY_ACTIVATED) {
                // send push notification
                if ($push_activated) {
                    $prowl->push(array(
                        'application'=>$applicationname,
                        'event'=>'New Crash type',
                        'description'=>'Version '.$version.' has a new type of crash!\n Sent at ' . date('H:i:s'),
                        'priority'=>0,
                    ),true);
                }
                
                // send boxcar notification
                if($boxcar_activated) {
                	$boxcar = new Boxcar($boxcar_uid, $boxcar_pwd);
                	print_r($boxcar->send($crash["appname"], 'Version '.$crash["version"].' Pattern '.$crash_offset.' has a MORE than '.$notify_amount_group.' crashes!\n Sent at ' . date('H:i:s')));
                }
                
                // send email notification
                if ($mail_activated) {
                    $subject = $applicationname.': New Crash type';

                    if ($crash_url != '')
                        $url = "Link: ".$crash_url."admin/crashes.php?bundleidentifier=".$bundleidentifier."&version=".$version."&groupid=".$log_groupid."\n\n";
                    else
                        $url = "\n";
                    $message = "Version ".$version." has a new type of crash!\n".$url."Sent at ".date('H:i:s');

                    mail($notify_emails, $subject, $message, 'From: '.$mail_from. "\r\n");
                }
            }
        }
    }
    
    if (array_key_exists('id', $crash)) {
        // now insert the crashlog into the database
        $query = "UPDATE ".$dbcrashtable." SET groupid=".$log_groupid." WHERE id=".$crash["id"];
        $result = mysql_query($query);
        if (!$result) return FAILURE_SQL_ADD_CRASHLOG;
        
        // TODO: update latesttimestamp of group
    } else {        
        // now insert the crashlog into the database
      	$query = "INSERT INTO ".$dbcrashtable." (userid, username, contact, bundleidentifier, applicationname, systemversion, platform, senderversion, version, description, log, groupid, timestamp, jailbreak) values ('".$crash["userid"]."', '".$crash["username"]."', '".$crash["contact"]."', '".$bundleidentifier."', '".$crash["applicationname"]."', '".$crash["systemversion"]."', '".$crash["platform"]."', '".$crash["senderversion"]."', '".$version."', '".$crash["description"]."', '".mysql_real_escape_string($logdata)."', '".$log_groupid."', '".date("Y-m-d H:i:s")."', ".$jailbreak.")";
      	$result = mysql_query($query);
        if (!$result) return FAILURE_SQL_ADD_CRASHLOG;

      	$new_crashid = mysql_insert_id($dblink);

      	// if this crash log has to be manually symbolicated, add a todo entry
      	if ($symbolicate) {
          $query = "INSERT INTO ".$dbsymbolicatetable." (crashid, done) values (".$new_crashid.", 0)";
          $result = mysql_query($query);
          if (!$result) return FAILURE_SQL_ADD_SYMBOLICATE_TODO;
      	}
    }
        
    return "";
}
?>
