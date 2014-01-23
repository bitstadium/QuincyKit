<?php

  /*
   * Author: Andreas Linde <mail@andreaslinde.de>
   *         Kenth Sutherland
   *
   * Copyright (c) 2014 Andreas Linde.
   * Copyright (c) 2009-2011 Andreas Linde & Kent Sutherland.
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
// This script will be invoked by the application to submit a crash log
//

require_once('config.php');
require_once('admin/common.inc');

if (!class_exists('XMLReader', false)) die(xml_for_result(FAILURE_PHP_XMLREADER_CLASS));

if ($push_activated || $boxcar_activated) {
	
  $curl_info = curl_version();	// Checks for cURL function and SSL version. Thanks Adrian Rollett!
  if(!function_exists('curl_exec') || empty($curl_info['ssl_version']))
    die(xml_for_result(FAILURE_PHP_CURL_LIB));

  if ($push_prowlids != "") {
    include('ProwlPHP.php');

    if (!class_exists('Prowl', false)) die(xml_for_result(FAILURE_PHP_PROWL_CLASS));

    $prowl = new Prowl($push_prowlids);
  } else {
    $push_activated = false;
  }

  if ($boxcar_uid != "" && $boxcar_pwd != ""){
    include('class.boxcar.php');
  } else {
    $boxcar_activated = false;
  }
	
} else {
	
  $push_activated = false;
  $boxcar_activated = false;
}

// Check for mail code injection
foreach($_REQUEST as $fields => $value) {
  if (preg_match('/TO:/i', $value) || preg_match('/CC:/i', $value) || preg_match('/CCO:/i', $value) || preg_match('/Content-Type:/i', $value)) {
    $mail_activated = false;
  }
}

function xml_for_result($result) {
  return '<?xml version="1.0" encoding="UTF-8"?><result>'.$result.'</result>'; 
}

function doPost($url, $postdata) {
  $url = parse_url($url);

  if (!isset($url['port'])) {
    if ($url['scheme'] == 'http') { $url['port']=80; }
    elseif ($url['scheme'] == 'https') { $url['port']=443; }
    elseif ($url['scheme'] == 'ssl') { $url['port']=443; }
  }
  $url['query']=isset($url['query'])?$url['query']:'';

  $url['protocol']=$url['scheme'].'://';

  $handle = fsockopen($url['protocol'].$url['host'], $url['port'], $errno, $errstr, 30);
  if (!$handle) {
    return 'error'; 
  } else {
    srand((double)microtime()*1000000);
    $boundary = "---------------------".substr(md5(rand(0,32000)),0,10);

    $data = "--$boundary\r\n";
    $data .="Content-Disposition: form-data; name=\"xml\"; filename=\"crash.xml\"\r\n";
    $data .= "Content-Type: text/xml\r\n\r\n";
    $data .= "".$postdata."\r\n";
    $data .="--$boundary--\r\n";

    $temp = "POST ".$url['path']." HTTP/1.1\r\n"; 
    $temp .= "Host: ".$url['host']."\r\n";
    $temp .= "User-Agent: PHP Script\r\n";
    $temp .= "Content-Type: multipart/form-data; boundary=$boundary\r\n";
    $temp .= "Content-length: " . strlen($data) . "\r\n\r\n";
    
    fwrite($handle, $temp.$data); 

    $response = '';

    while (!feof($handle)) 
      $response.=fgets($handle, 128); 

    $response=preg_split('/\r\n\r\n/',$response);

    $header=$response[0]; 
    $responsecontent=$response[1]; 

    if(!(strpos($header,"Transfer-Encoding: chunked")===false)) {
      $aux=preg_split('/\r\n/',$responsecontent);
      for($i=0;$i<count($aux);$i++) 
        if($i==0 || ($i%2==0)) 
          $aux[$i]=""; 
      $responsecontent=implode("",$aux); 
    } 

    fclose($handle);
    return chop($responsecontent); 
  }
}

$allowed_args = ',xmlstring,';

/* Verbindung aufbauen, auswählen einer Datenbank */
$link = mysql_connect($server, $loginsql, $passsql)
  or die(xml_for_result(FAILURE_DATABASE_NOT_AVAILABLE));
mysql_select_db($base) or die(xml_for_result(FAILURE_DATABASE_NOT_AVAILABLE));

foreach(array_keys($_POST) as $k) {
  $temp = ",$k,";
  if(strpos($allowed_args,$temp) !== false) { $$k = $_POST[$k]; }
}
if (!isset($xmlstring)) $xmlstring = "";

if ($xmlstring == "") die(xml_for_result(FAILURE_INVALID_POST_DATA));

// Fix parsing bug in pre 1.0 mac client and iOS client, fixed in latest commi
$xmlstring = str_replace("<description><![CDATA[", "<description>", $xmlstring);
$xmlstring = str_replace("]]></description>", "</description>", $xmlstring);
$xmlstring = str_replace("<description>", "<description><![CDATA[", $xmlstring);
$xmlstring = str_replace("</description>", "]]></description>", $xmlstring);

$reader = new XMLReader();

$reader->XML($xmlstring);

$crashIndex = -1;
$crashes = array();

function reading($reader, $tag) {
  $input = "";
  while ($reader->read()) {
    if ($reader->nodeType == XMLReader::TEXT ||
        $reader->nodeType == XMLReader::CDATA ||
        $reader->nodeType == XMLReader::WHITESPACE ||
        $reader->nodeType == XMLReader::SIGNIFICANT_WHITESPACE)
    {
      $input .= $reader->value;
    } else if ($reader->nodeType == XMLReader::END_ELEMENT
      && $reader->name == $tag)
    {
      break;
    }
  }
  return $input;
}

define('VALIDATE_NUM',          '0-9');
define('VALIDATE_ALPHA_LOWER',  'a-z');
define('VALIDATE_ALPHA_UPPER',  'A-Z');
define('VALIDATE_ALPHA',        VALIDATE_ALPHA_LOWER . VALIDATE_ALPHA_UPPER);
define('VALIDATE_SPACE',        '\s');
define('VALIDATE_PUNCTUATION',  VALIDATE_SPACE . '\.,;\:&"\'\?\!\(\)');


/**
 * Validate a string using the given format 'format'
 *
 * @param string $string  String to validate
 * @param array  $options Options array where:
 *                          'format' is the format of the string
 *                              Ex:VALIDATE_NUM . VALIDATE_ALPHA (see constants)
 *                          'min_length' minimum length
 *                          'max_length' maximum length
 *
 * @return boolean true if valid string, false if not
 *
 * @access public
 */
function ValidateString($string, $options) {
  $format     = null;
  $min_length = 0;
  $max_length = 0;

  if (is_array($options)) {
    extract($options);
  }

  if ($format && !preg_match("|^[$format]*\$|s", $string)) {
    return false;
  }

  if ($min_length && strlen($string) < $min_length) {
    return false;
  }

  if ($max_length && strlen($string) > $max_length) {
    return false;
  }

  return true;
}

while ($reader->read()) {
  if ($reader->name == "crash" && $reader->nodeType == XMLReader::ELEMENT) {
    $crashIndex++;

    $crashes[$crashIndex]["bundleidentifier"] = "";
    $crashes[$crashIndex]["applicationname"] = "";
    $crashes[$crashIndex]["systemversion"] = "";
    $crashes[$crashIndex]["platform"] = "";
    $crashes[$crashIndex]["senderversion"] = "";
    $crashes[$crashIndex]["version"] = "";
    $crashes[$crashIndex]["userid"] = "";
    $crashes[$crashIndex]["username"] = "";
    $crashes[$crashIndex]["contact"] = "";
    $crashes[$crashIndex]["description"] = "";
    $crashes[$crashIndex]["logdata"] = "";
    $crashes[$crashIndex]["appname"] = "";
  
  } else if ($reader->name == "bundleidentifier" && $reader->nodeType == XMLReader::ELEMENT) {
    $crashes[$crashIndex]["bundleidentifier"] = mysql_real_escape_string(reading($reader, "bundleidentifier"));
  } else if ($reader->name == "version" && $reader->nodeType == XMLReader::ELEMENT) {
    $crashes[$crashIndex]["version"] = mysql_real_escape_string(reading($reader, "version"));
    if( !ValidateString( $crashes[$crashIndex]["version"], array('format'=>VALIDATE_NUM . VALIDATE_ALPHA. VALIDATE_SPACE . VALIDATE_PUNCTUATION) ) )
      die(xml_for_result(FAILURE_XML_VERSION_NOT_ALLOWED));
  } else if ($reader->name == "senderversion" && $reader->nodeType == XMLReader::ELEMENT) {
    $crashes[$crashIndex]["senderversion"] = mysql_real_escape_string(reading($reader, "senderversion"));
    if (!ValidateString( $crashes[$crashIndex]["senderversion"], array('format'=>VALIDATE_NUM . VALIDATE_ALPHA. VALIDATE_SPACE . VALIDATE_PUNCTUATION) ) )
      die(xml_for_result(FAILURE_XML_SENDER_VERSION_NOT_ALLOWED));
  } else if ($reader->name == "applicationname" && $reader->nodeType == XMLReader::ELEMENT) {
    $crashes[$crashIndex]["applicationname"] = mysql_real_escape_string(reading($reader, "applicationname"));
  } else if ($reader->name == "systemversion" && $reader->nodeType == XMLReader::ELEMENT) {
    $crashes[$crashIndex]["systemversion"] = mysql_real_escape_string(reading($reader, "systemversion"));
  } else if ($reader->name == "userid" && $reader->nodeType == XMLReader::ELEMENT) {
    $crashes[$crashIndex]["userid"] = mysql_real_escape_string(reading($reader, "userid"));
  } else if ($reader->name == "username" && $reader->nodeType == XMLReader::ELEMENT) {
    $crashes[$crashIndex]["username"] = mysql_real_escape_string(reading($reader, "username"));
  } else if ($reader->name == "contact" && $reader->nodeType == XMLReader::ELEMENT) {
    $crashes[$crashIndex]["contact"] = mysql_real_escape_string(reading($reader, "contact"));
  } else if ($reader->name == "description" && $reader->nodeType == XMLReader::ELEMENT) {
    $crashes[$crashIndex]["description"] = mysql_real_escape_string(reading($reader, "description"));
  } else if ($reader->name == "log" && $reader->nodeType == XMLReader::ELEMENT) {
    $crashes[$crashIndex]["logdata"] = reading($reader, "log");
  } else if ($reader->name == "platform" && $reader->nodeType == XMLReader::ELEMENT) {
    $crashes[$crashIndex]["platform"] = mysql_real_escape_string(reading($reader, "platform"));
  }
}

$reader->close();

$lastError = 0;

// store the best version status to return feedback
$best_status = VERSION_STATUS_UNKNOWN;

// go through all crah reports
foreach ($crashes as $crash) {

  // don't proceed if we don't have anything to search for
  if ($crashIndex < 0 || $crash["bundleidentifier"] == "")
	  die("No valid data entered!");
	
  // by default set the appname to bundleidentifier, so it has some meaningful value for sure
  $crash["appname"] =  $crash["bundleidentifier"];

  // store the status of the fix version for this crash
  $crash["fix_status"] = VERSION_STATUS_UNKNOWN;

  // the status of the buggy version
  $crash["version_status"] = VERSION_STATUS_UNKNOWN;

  // by default assume push is turned of for the found version
  $notify = $notify_default_version;

  // push ids to send notifications to (per app setting)
  $notify_pushids = '';

  // email addresses to send notifications to (per app setting)
  $notify_emails = '';

  // check out if we accept this app and version of the app
  $acceptlog = false;
  $symbolicate = false;

  $hockeyappidentifier = '';

  // shall we accept any crash log or only ones that are named in the database
  if ($acceptallapps) {
    // external symbolification is turned on by default when accepting all crash logs
    $acceptlog = true;
    $symbolicate = true;

    // get the app name
    $query = "SELECT name, hockeyappidentifier FROM ".$dbapptable." where bundleidentifier = '".$crash["bundleidentifier"]."'";
    $result = mysql_query($query) or die(xml_for_result(FAILURE_SQL_SEARCH_APP_NAME));

    $numrows = mysql_num_rows($result);
    if ($numrows == 1) {
      $crash["appname"] = $row[0];
      $hockeyappidentifier = $row[1];
      $notify_emails = $mail_addresses;
      $notify_pushids = $push_prowlids;
    }
    mysql_free_result($result);
  } else {
    // the bundleidentifier is the important string we use to find a match
    $query = "SELECT id, symbolicate, name, notifyemail, notifypush, hockeyappidentifier FROM ".$dbapptable." where bundleidentifier = '".$crash["bundleidentifier"]."'";
    $result = mysql_query($query) or die(xml_for_result(FAILURE_SQL_SEARCH_APP_NAME));

    $numrows = mysql_num_rows($result);
    if ($numrows == 1) {
      // we found one, so let this crash through
      $acceptlog = true;

      $row = mysql_fetch_row($result);

      // check if a todo entry shall be added to create remote symbolification
      if ($row[1] == 1)
        $symbolicate = true;

      // get the app name
      $crash["appname"] = $row[2];

      $notify_emails = $row[3];
      $notify_pushids = $row[4];

      $hockeyappidentifier = $row[5];
    }

    // add global email addresses
    if ($mail_addresses != '') {
      if ($notify_emails != '') {
        $notify_emails .= ','.$mail_addresses;
      } else {
        $notify_emails = $mail_addresses;
      }
    }

    // add global prowl ids
    if ($push_prowlids != '') {
      if ($notify_pushids != '') {
        $notify_pushids .= ','.$push_prowlids;
      } else {
        $notify_pushids = $push_prowlids;
      }
    }
    
    mysql_free_result($result);
  }

  // Make sure we only have a max of 5 prowl ids
  $push_array=preg_split('/[,]+/',$notify_pushids);
  if (sizeof($push_array) > 5) {
    $notify_pushids = '';
    for ($i=0; $i < 5; $i++) {
      if (i>0)
        $notify_pushids .= ',';
      $notify_pushids .= $push_array[$i];
    }
  }

  // add the crash data to the database
  if ($crash["logdata"] != "" && $crash["version"] != "" && $crash["applicationname"] != "" && $crash["bundleidentifier"] != "" && $acceptlog == true) {
    // check if we need to redirect this crash
    if ($hockeyappidentifier != '') {
      if (!isset($hockeyAppURL))
        $hockeyAppURL = "ssl://beta.hockeyapp.net/";
    	    
      // we assume all crashes in this xml goes to the same app, since it is coming from one client. so push them all at once to HockeyApp
      $result = doPost($hockeyAppURL."api/2/apps/".$hockeyappidentifier."/crashes", utf8_encode($xmlstring));
        
      // we do not parse the result, values are different anyway, so simply return unknown status            
      echo xml_for_result(VERSION_STATUS_UNKNOWN);

      /* schliessen der Verbinung */
      mysql_close($link);

  	  // HockeyApp doesn't support direct feedback, it requires the new client to do that. So exit right away.
  	  exit;
    }

    // Since analyzing the log data seems to have problems, first add it to the database, then read it, since it seems that one is fine then

    // first check if the version status is not discontinued

    // check if the version is already added and the status of the version and notify status
  	$query = "SELECT id, status, notify FROM ".$dbversiontable." WHERE bundleidentifier = '".$crash["bundleidentifier"]."' and version = '".$crash["version"]."'";
  	$result = mysql_query($query) or die(xml_for_result(FAILURE_SQL_CHECK_VERSION_EXISTS));

  	$numrows = mysql_num_rows($result);
  	if ($numrows == 0) {
      // version is not available, so add it with status VERSION_STATUS_AVAILABLE
      $query = "INSERT INTO ".$dbversiontable." (bundleidentifier, version, status, notify) values ('".$crash["bundleidentifier"]."', '".$crash["version"]."', ".VERSION_STATUS_UNKNOWN.", ".$notify_default_version.")";
      $result = mysql_query($query) or die(xml_for_result(FAILURE_SQL_ADD_VERSION));
  	} else {
      $row = mysql_fetch_row($result);
      $crash["version_status"] = $row[1];
      $notify = $row[2];
      mysql_free_result($result);
  	}

  	if ($crash["version_status"] == VERSION_STATUS_DISCONTINUED)
  	{
      $lastError = FAILURE_VERSION_DISCONTINUED;
      continue;
  	}


    $error = groupCrashReport($crash, $link, $notify);
    if ($error != "") {
        die(xml_for_result($error));
    }
    
  	$lastError = 0;
  } else if ($acceptlog == false) {
  	$lastError = FAILURE_INVALID_INCOMING_DATA;
  	continue;
  }
}

/* schliessen der Verbinung */
mysql_close($link);

/* Ausgabe der Ergebnisse in XML */
if ($lastError != 0) {
  echo xml_for_result($lastError);
} else {
  echo xml_for_result($best_status);
}
?>
