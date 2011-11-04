/*
 * Author: Andreas Linde <mail@andreaslinde.de>
 *         Kent Sutherland
 *         Stanley Rost
 *
 * Copyright (c) 2011 Andreas Linde & Kent Sutherland.
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

typedef enum CrashReportStatus
{
    // The status of the crash is queued, need to check later (HockeyApp)
    CrashReportStatusQueued = -80,
    
    // This app version is set to discontinued, no new crash reports accepted by the server
    CrashReportStatusFailureVersionDiscontinued = -30,
    
    // XML: Sender ersion string contains not allowed characters, only alphanumberical including space and . are allowed
    CrashReportStatusFailureXMLSenderVersionNotAllowed = -21,
    
    // XML: Version string contains not allowed characters, only alphanumberical including space and . are allowed
    CrashReportStatusFailureXMLVersionNotAllowed = -20,
    
    // SQL for adding a symoblicate todo entry in the database failed
    CrashReportStatusFailureSQLAddSymbolicateTodo = -18,
    
    // SQL for adding crash log in the database failed
    CrashReportStatusFailureSQLAddCrashlog = -17,
    
    // SQL for adding a new version in the database failed
    CrashReportStatusFailureSQLAddVersion = -16,
    
    // SQL for checking if the version is already added in the database failed
    CrashReportStatusFailureSQLCheckVersionExists = -15,
    
    // SQL for creating a new pattern for this bug and set amount of occurrances to 1 in the database failed
    CrashReportStatusFailureSQLAddPattern = -14,
    
    // SQL for checking the status of the bugfix version in the database failed
    CrashReportStatusFailureSQLCheckBugfixStatus = -13,
    
    // SQL for updating the occurances of this pattern in the database failed
    CrashReportStatusFailureSQLUpdatePatternOccurances = -12,
    
    // SQL for getting all the known bug patterns for the current app version in the database failed
    CrashReportStatusFailureSQLFindKnownPatterns = -11,
    
    // SQL for finding the bundle identifier in the database failed
    CrashReportStatusFailureSQLSearchAppName = -10,
    
    // the post request didn't contain valid data
    CrashReportStatusFailureInvalidPostData = -3,
    
    // incoming data may not be added, because e.g. bundle identifier wasn't found
    CrashReportStatusFailureInvalidIncomingData = -2,
    
    // database cannot be accessed, check hostname, username, password and database name settings in config.php
    CrashReportStatusFailureDatabaseNotAvailable = -1,
    
    CrashReportStatusUnknown = 0,
    
    CrashReportStatusAssigned = 1,
    
    CrashReportStatusSubmitted = 2,
    
    CrashReportStatusAvailable = 3,
} CrashReportStatus;
