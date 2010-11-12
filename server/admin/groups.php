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
// This script shows all crash groups for a version
//
// This script shows a list of all crash groups of a version of an application,
// the amount of crash logs assigned to this group and the assigned bugfix version
// You can edit the bugfix version, if this version is not added yet, it will be added
// automatically to the version list. You can also assign a short description for
// this crash group or download the latest crash log data for this group directly.
// All crashes that weren't assigned to a group, will be shown in the list with in one
// combined entry too
//

require_once('../config.php');
require_once('common.inc');

function parsestack($pattern) {
    $result = array();
	
    $restpos = strpos($pattern, ")");
    if (strlen($pattern) > $restpost + 1)
        $rest = substr($pattern, $restpos + 1);
    $result["rest"] = $rest;
    $searchpattern = substr($pattern, 0, $restpos + 1);
    preg_match('/\[([^\s]+)\s+([^\s]+)\]\s+\(([^\s]+)\)/', $searchpattern, $matches);
    // what if there is no class name!?
    if (count($matches) == 0) {
        preg_match('/([^\s]+)\s+\(([^\s]+)\)/', $searchpattern, $matches);
        $result["class"] = "-";
        $result["method"] = $matches[1];
        $result["file"] = $matches[2];
    } else {
        $result["class"] = $matches[1];
        $result["method"] = $matches[2];
        $result["file"] = $matches[3];
    }

	return $result;
}

init_database();
parse_parameters(',bundleidentifier,version,');

if (!isset($bundleidentifier)) $bundleidentifier = "";
if (!isset($version)) $version = "";

if ($bundleidentifier == "") die(end_with_result('Wrong parameters'));
if ($version == "") die(end_with_result('Wrong parameters'));

show_header('- Crash Patterns');

echo '<h2>';
if (!$acceptallapps)
	echo '<a href="app_name.php">Apps</a> - ';

echo create_link($bundleidentifier, 'app_versions.php', false, 'bundleidentifier').' - '.create_link('Version '.$version, 'groups.php', false, 'bundleidentifier,version').'</h2>';

$osticks = "";
$osvalues = "";

$crashvaluesarray = array();
$crashvalues = "";


// get the amount of crashes over time

$query = "SELECT timestamp FROM ".$dbcrashtable."  WHERE bundleidentifier = '".$bundleidentifier."' AND version = '".$version."' ORDER BY timestamp desc";
$result = mysql_query($query) or die(end_with_result('Error in SQL '.$query));
$numrows = mysql_num_rows($result);
if ($numrows > 0) {
    while ($row = mysql_fetch_row($result)) {
        $timestamp = $row[0];
        
        if ($timestamp != "" && ($timestampvalue = strtotime($timestamp)) !== false)
		{
            $timeindex = substr($timestamp, 0, 10);

            if (!array_key_exists($timeindex, $crashvaluesarray)) {
                $crashvaluesarray[$timeindex] = 0;
            }
            $crashvaluesarray[$timeindex]++;
        }
    }
}
mysql_free_result($result);


$cols2 = '<colgroup><col width="320"/><col width="320"/><col width="320"/></colgroup>';
echo '<table>'.$cols2.'<tr><th>Platform Overview</th><th>Crashes over time</th><th>System OS Overview</th></tr>';

echo "<tr><td><div id=\"platformdiv\" style=\"height:280px;width:310px; \"></div></td>";
echo "<td><div id=\"crashdiv\" style=\"height:280px;width:310px; \"></div></td>";
echo "<td><div id=\"osdiv\" style=\"height:280px;width:310px; \"></div></td></tr>"; 

// get the amount of crashes per system version
$crashestime = true;

$osticks = "";
$osvalues = "";
$query2 = "SELECT systemversion, COUNT(systemversion) FROM ".$dbcrashtable.$whereclause." WHERE bundleidentifier = '".$bundleidentifier."' AND version = '".$version."' group by systemversion order by systemversion desc";
$result2 = mysql_query($query2) or die(end_with_result('Error in SQL '.$query2));
$numrows2 = mysql_num_rows($result2);
if ($numrows2 > 0) {
	// get the status
	while ($row2 = mysql_fetch_row($result2)) {
		if ($osticks != "") $osticks = $osticks.", ";
		$osticks .= "'".$row2[0]."'";
		if ($osvalues != "") $osvalues = $osvalues.", ";
		$osvalues .= $row2[1];
	}
}
mysql_free_result($result2);

// get the amount of crashes per system version
$crashestime = true;

$platformticks = "";
$platformvalues = "";
$query = "SELECT platform, COUNT(platform) FROM ".$dbcrashtable." WHERE bundleidentifier = '".$bundleidentifier."' AND version = '".$version."' AND platform != \"\" group by platform order by platform desc";
$result = mysql_query($query) or die(end_with_result('Error in SQL '.$query));
$numrows = mysql_num_rows($result);
if ($numrows > 0) {
	// get the status
	while ($row = mysql_fetch_row($result)) {
		if ($platformticks != "") $platformticks = $platformticks.", ";
		$platformticks .= "'".mapPlatform($row[0])."'";
		if ($platformvalues != "") $platformvalues = $platformvalues.", ";
		$platformvalues .= $row[1];
	}
}
mysql_free_result($result);
echo '</table>';


// START Group Deta
$cols2 = '<colgroup><col width="950"/></colgroup>';
echo '<table>'.$cols2.'<tr><th>Group Details</th></tr>';
echo '<tr><td>';
            
show_search("", -1, true, "");

echo " <a href=\"javascript:deleteGroups('$bundleidentifier','$version')\" style=\"float: right; margin-top:-35px;\" class=\"button redButton\" onclick=\"return confirm('Do you really want to delete all items?');\">Delete All</a>";

echo '</tr></td></table>';
// END Group Details


// START Group Listing
$cols = '<colgroup><col width="90"/><col width="50"/><col width="100"/><col width="180"/><col width="360"/><col width="190"/></colgroup>';

echo '<table>'.$cols;
echo "<tr><th>Pattern</th><th>Amount</th><th>Last Update</th><th>Assigned Fix Version</th><th>Description</th><th>Actions</th></tr>";
echo '</table>';

echo '<div id="groups">';

$classes = array();
$unknown = array();

$query = "SELECT fix, pattern, amount, id, description, latesttimestamp FROM ".$dbgrouptable." WHERE bundleidentifier = '".$bundleidentifier."' AND affected = '".$version."' ORDER BY pattern asc";
$result = mysql_query($query) or die(end_with_result('Error in SQL '.$query));

$numrows = mysql_num_rows($result);
if ($numrows > 0) {
	// get the status
	while ($row = mysql_fetch_row($result)) {
		$fix = $row[0];
		$pattern = $row[1];
		$amount = $row[2];
		$groupid = $row[3];
		$description = $row[4];
		$lastupdate = $row[5];
		
        $newpattern = array();
        $newpattern["groupid"] = $groupid;
        $newpattern["desription"] = $description;
        $newpattern["fix"] = $fix;
        $newpattern["amount"] = $amount;
        $newpattern["lastupdate"] = $lastupdate;

		// get classes
        if (strpos($pattern, "(") !== false && substr($pattern, 0, 4) != "0x00") {
                //  [LiveUpdateReader databaseActions:] (LiveUpdateReader.m:62)[fskfjsdlfsd
                // \[ ([^\s]+)      \s+ ([^\s]+)     \] \s+ \( ([^\s]+)\)  \)
                
                $rest = "";
                $class = "";
                $method = "";
                $file = "";
                
                $resultarray = parsestack($pattern);
                $class = $resultarray["class"];
                $method = $resultarray["method"];
                $file = $resultarray["file"];
                $rest = $resultarray["rest"];
/*
                $restpos = strpos($pattern, ")");
                if (strlen($pattern) > $restpost + 1)
                    $rest = substr($pattern, $restpos + 1);
                $searchpattern = substr($pattern, 0, $restpos + 1);
				preg_match('/\[([^\s]+)\s+([^\s]+)\]\s+\(([^\s]+)\)/', $searchpattern, $matches);
				// what if there is no class name!?
				if (count($matches) == 0) {
    				preg_match('/([^\s]+)\s+\(([^\s]+)\)/', $searchpattern, $matches);
                    $class = "-";
                    $method = $matches[1];
                    $file = $matches[2];
                } else {
                    $class = $matches[1];
                    $method = $matches[2];
                    $file = $matches[3];
                }
*/
                if ($method != "" && $file != "") {
                    // check if class exists
                    if (!array_key_exists($class, $classes)) {
                        $classesArray = array();
                        $classesArray["amount"] = $amount;
                        $classesArray["methods"] = array();
                        $classes[$class] = $classesArray;
                    } else {
                        $classes[$class]["amount"] += $amount;
                    }
                    
                    // check if the class array has the method
                    if (!array_key_exists($method, $classes[$class]["methods"])) {
                        $methodArray = array();
                        $methodArray["amount"] = $amount;
                        $methodArray["files"] = array();
                        $classes[$class]["methods"][$method] = $methodArray;
                    } else {
                        $classes[$class]["methods"][$method]["amount"] += $amount;
                    }
                    
                    $newpattern["file"] = $file;
                    $newpattern["callstack"] = "";
                    if ($rest != "") {
                        $rest = str_replace(") ","} ",$rest);
                        $rest = str_replace(")",")\n",$rest);
                        $rest = str_replace("} ",") ",$rest);
                        $newpattern["callstack"] = $rest;
                    }

                    $classes[$class]["methods"][$method]["files"][] = $newpattern;
                } else {
                    // TODO: WHAT NOW !?
                }
        } else {
            if ($amount > 0) {
                $newpattern["pattern"] = $pattern;
                $unknown[] = $newpattern;
            }
        }
    }
	mysql_free_result($result);
}

// $cols1 = '<colgroup><col width="50"/><col width="50"/><col width="50"/><col width="250"/><col width="50"/><col width="100"/><col width="100"/><col width="290"/></colgroup>';

if (count($classes) > 0) {

    echo '<table>';
    echo "<tr><th></th><th>Class</th><th>Method</th><th>File</th><th>Amount</th><th>Updated</th><th>Fix</th></tr>";
    
    foreach ($classes as $classname=> $classvalue) {    
        
        $methodcount = 0;
        
        // go through the class methods
        foreach ($classvalue["methods"] as $methodname=> $methodvalue) {    
            $filecount = 0;
            
            // go through the files
            foreach ($methodvalue["files"] as $filevalue) {

                $methodcount++;
                $filecount++;

                echo "<tr><td><a href='javascript:expandCollapse(".$filevalue["groupid"].")'>+/-</a></td>";
                // write the class
                if ($methodcount == 1)
                    echo "<td>".$classname."</td>";
                else
                    echo "<td></td>";
                    
                // write the method
                if ($filecount == 1)
                    echo "<td>".$methodname."</td>";
                else
                    echo "<td></td>";

                echo "<td><a href='crashes.php?groupid=".$filevalue["groupid"]."&bundleidentifier=".$bundleidentifier."&version=".$version."'>".$filevalue["file"]."</a></td><td>".$filevalue["amount"]."</td><td>";
                
                $lastupdate = $filevalue["lastupdate"];
                $difference = time() - $lastupdate;
                if ($lastupdate != 0) {
                    $timestring = date("Y-m-d H:i:s", $lastupdate);
                    if ($difference < 60)
                        echo "<font color='".$color24h."'>now</font>";
                    else if ($difference < 60 * 60)
                        echo "<font color='".$color24h."'>".round($difference / 60)." min ago</font>";
                    else if ($difference < 60 *60 * 12)
                        echo "<font color='".$color24h."'>".round($difference / (60 * 60))." h ago</font>";
                    else if ($difference < 60 *60 * 24)
                        echo "<font color='".$color24h."'>last 24h</font>";
                    else if ($difference < 60 *60 * 24 * 2)
                        echo "<font color='".$color48h."'>last 48h</font>";
                    else if ($difference < 60 *60 * 24 * 3)
                        echo "<font color='".$color72h."'>last 72h</font>";
                    else
                        echo "<font color='".$colorOther."'>".round($difference / (60 * 60 * 24))." days ago</font>";
                } else {
                    echo "-";
                }
        
                echo '</td><td>'.$filevalue["fix"].'</td></tr>';
                
                if ($filevalue["description"] != "") {
                    echo "<tr id='descriptionpreview".$filevalue["groupid"]."'><td></td><td colspan='6'>".$filevalue["description"]."</td></tr>";
                }
                                
                $lines = explode("\n", $filevalue["callstack"]);
                $numberoflines = 0;
                foreach ($lines as $line) {
                    if ($line == "") continue;
                    $numberoflines++;
                }
                $rownumber = 0;
                foreach ($lines as $line) {
                    if ($line == "") continue;
                    $resultarray = parsestack($line);
                    $rownumber++;
                    if (count($resultarray) == 0) continue;
                    echo "<tr class='expandcallstack".$filevalue["groupid"]."' style='display: none; background-color:#F0F0F0;'>";
                    if ($rownumber == 1)
                        echo "<td rowspan='".($numberoflines + 2)."'></td>";
                    echo "<td>".$resultarray["class"]."</td>";
                    echo "<td>".$resultarray["method"]."</td>";
                    echo "<td>".$resultarray["file"]."</td>";
                    echo "<td colspan='3'></td>";
                    echo "</tr>";
                }
                $rowspan = "";
                if ($rownumber == 0)
                    $rowspan = "<td rowspan='2'></td>";
                    
                echo "<tr id='expandfix".$filevalue["groupid"]."' style='display: none; background-color:#F0F0F0;'>".$rowspan."<td><b style='float: right;'>Fix Version:</b></td><td colspan='2'><input type='text' id='fixversion".$filevalue["groupid"]."' name='fixversion' size='20' maxlength='20' value='".$filevalue["fix"]."'/></td>";
                echo "<td rowspan='2' colspan='3'><a href=\"javascript:updateGroupMeta(".$filevalue["groupid"].",'".$bundleidentifier."')\" class='button'>Update</a>";
                echo " <a href='actionapi.php?action=downloadcrashid&groupid=".$filevalue["groupid"]."' class='button'>Download</a>";
                $issuelink = currentPageURL();
                $issuelink = substr($issuelink, 0, strrpos($issuelink, "/")+1);
                echo "<br/><br/><br/>".create_issue($bundleidentifier, $issuelink.'crashes.php?groupid='.$filevalue["groupid"].'&bundleidentifier='.$bundleidentifier.'&version='.$version);
                echo " <a href='javascript:deleteGroupID(".$filevalue["groupid"].")' class='button redButton' onclick='return confirm(\"Do you really want to delete this item?\");'>Delete</a></td></tr>"; 
                
                echo "<tr id='expanddescription".$filevalue["groupid"]."' style='display: none; background-color:#F0F0F0;'><td><b style='float: right;'>Description:</b></td><td colspan='2'>";
                echo '<textarea id="description'.$filevalue["groupid"].'" cols="50" rows="2" name="description" class="description">'.$filevalue["description"].'</textarea></td></tr>';               
                
            }
            
        }
    }
    echo '</table>';
}

$cols = '<colgroup><col width="90"/><col width="50"/><col width="100"/><col width="180"/><col width="360"/><col width="190"/></colgroup>';

if (count($unknown) > 0) {

    echo '<table>'.$cols;
    echo "<tr><th>Pattern</th><th>Amount</th><th>Last Update</th><th>Assigned Fix Version</th><th>Description</th><th>Actions</th></tr>";
    echo '</table>';

    // todo sort unknown by amount desc
    
    foreach ($unknown as $crashpattern) {    
		$fix = $crashpattern["fix"];
		$pattern = $crashpattern["pattern"];
		$amount = $crashpattern["amount"];
		$groupid = $crashpattern["groupid"];
		$description = $crashpattern["description"];
		$lastupdate = $crashpattern["lastupdate"];
		
        echo "<form name='groupmetadata".$groupid."' action='' method='get'>";
		echo '<table>'.$cols;

        $patterntitle = str_replace("%","\n",$pattern);
        if (strlen($patterntitle) > 54) {
            $patterntitle = substr($patterntitle,0,50)."...";
        }
    
		echo "<tr id='grouprow".$groupid."'><td><a href='crashes.php?groupid=".$groupid."&bundleidentifier=".$bundleidentifier."&version=".$version."'>".$patterntitle."</a></td><td>".$amount."</td><td>";
		
		if ($lastupdate != 0) {
            $timestring = date("Y-m-d H:i:s", $lastupdate);
			if (time() - $lastupdate < 60*24*24)
				echo "<font color='".$color24h."'>".$timestring."</font>";
			else if (time() - $lastupdate < 60*24*24*2)
				echo "<font color='".$color48h."'>".$timestring."</font>";
			else if (time() - $lastupdate < 60*24*24*3)
				echo "<font color='".$color72h."'>".$timestring."</font>";
			else
				echo "<font color='".$colorOther."'>".$timestring."</font>";
		} else {
    		echo "-";
        }
        
		echo '</td><td><input type="text" id="fixversion'.$groupid.'" name="fixversion" size="20" maxlength="20" value="'.$fix.'"/></td><td><textarea id="description'.$groupid.'" cols="50" rows="2" name="description" class="description">'.$description.'</textarea></td><td>';
    echo "<a href=\"javascript:updateGroupMeta(".$groupid.",'".$bundleidentifier."')\" class='button'>Update</a> ";
		echo "<a href='actionapi.php?action=downloadcrashid&groupid=".$groupid."' class='button'>Download</a> ";
		$issuelink = currentPageURL();
		$issuelink = substr($issuelink, 0, strrpos($issuelink, "/")+1);
		echo create_issue($bundleidentifier, $issuelink.'crashes.php?groupid='.$groupid.'&bundleidentifier='.$bundleidentifier.'&version='.$version);
		
        echo " <a href='javascript:deleteGroupID(".$groupid.")' class='button redButton' onclick='return confirm(\"Do you really want to delete this item?\");'>Delete</a></td></tr>";
		echo '</table>';
		echo '</form>';
	}
	
}

// get all bugs not assigned to groups
$query = "SELECT count(*) FROM ".$dbcrashtable." WHERE groupid = 0 and bundleidentifier = '".$bundleidentifier."' AND version = '".$version."'";
$result = mysql_query($query) or die(end_with_result('Error in SQL '.$dbcrashtable));

$numrows = mysql_num_rows($result);
if ($numrows > 0) {
	$row = mysql_fetch_row($result);
	$amount = $row[0];
	if ($amount > 0)
	{
        echo '<table><colgroup><col width="90"/><col width="50"/><col width="200"/><col width="440"/><col width="190"/></colgroup>';
        echo "<tr><th>Pattern</th><th>Amount</th><th>Last Update</th><th></th><th>Actions</th></tr>";
		echo '<tr><td><a href="crashes.php?bundleidentifier='.$bundleidentifier.'&version='.$version.'">Ungrouped</a></td>';
		echo '<td>'.$amount.'</td><td></td><td></td>';
        echo "<td><a href='regroup.php?bundleidentifier=".$bundleidentifier."&version=".$version."' class='button'>Re-Group</a>";
		echo "<a href='groups.php?bundleidentifier=".$bundleidentifier."&version=".$version."&groupid=0' class='button redButton' onclick='return confirm(\"Do you really want to delete this item?\");'>Delete</a></td></tr>";
		echo '</table>';
	}
	mysql_free_result($result);
}

mysql_close($link);

?>
</div>

<script type="text/javascript">
$(document).ready(function(){
    $.jqplot.config.enablePlugins = true;

<?php
    if (sizeof($crashvaluesarray) > 0) {
        foreach ($crashvaluesarray as $key => $value) {
            if ($crashvalues != "") $crashvalues = $crashvalues.", ";
            $crashvalues .= "['".$key."', ".$value."]";
        }

?>
    line1 = [<?php echo $crashvalues; ?>];
    plot1 = $.jqplot('crashdiv', [line1], {
        seriesDefaults: {showMarker:false},
        series:[
            {pointLabels:{
                show: false
            }}],
        axes:{
            xaxis:{
                renderer:$.jqplot.DateAxisRenderer,
                rendererOptions:{tickRenderer:$.jqplot.CanvasAxisTickRenderer},
                tickOptions:{formatString:'%#d-%b'}
            },
            yaxis:{
                min: 0,
                tickOptions:{formatString:'%.0f'}
            }
        },
        highlighter: {sizeAdjust: 7.5}
    });
<?php
    }
    
    if ($platformticks != "") {
?>
    line1 = [<?php echo $platformvalues; ?>];
    plot1 = $.jqplot('platformdiv', [line1], {
        seriesDefaults: {
                renderer:$.jqplot.BarRenderer
            },
        axes:{
            xaxis:{
                renderer:$.jqplot.CategoryAxisRenderer,
                ticks:[<?php echo $platformticks; ?>]
            },
            yaxis:{
                min: 0,
                tickOptions:{formatString:'%.0f'}
            }
        },
        highlighter: {show: false}
    });
<?php
    }
    
    if ($osticks != "") { 
?>
   line1 = [<?php echo $osvalues; ?>];
    plot1 = $.jqplot('osdiv', [line1], {
        seriesDefaults: {
                renderer:$.jqplot.BarRenderer
            },
        axes:{
            xaxis:{
                renderer:$.jqplot.CategoryAxisRenderer,
                ticks:[<?php echo $osticks; ?>]
            },
            yaxis:{
                min: 0,
                tickOptions:{formatString:'%.0f'}
            }
        },
        highlighter: {show: false}
    });
<?php
    }
?>
});
</script>

</body></html>