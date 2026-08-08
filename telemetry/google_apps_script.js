/**
 * Google Apps Script - Remote Log & Telemetry Collector for Portable Flutter VS Code Package
 * 
 * SETUP INSTRUCTIONS (2 Minutes):
 * 1. Go to https://script.google.com and click "New project".
 * 2. Paste this entire code into `Code.gs`.
 * 3. Click "Deploy" -> "New deployment".
 * 4. Select type: "Web app".
 *    - Execute as: "Me" (your Google account).
 *    - Who has access: "Anyone".
 * 5. Copy the Web App URL and set it in `install.ps1`:
 *    $TelemetryEndpoint = "https://script.google.com/macros/s/.../exec"
 */

function doPost(e) {
  try {
    var data = JSON.parse(e.postData.contents);
    var timestamp = data.timestamp || new Date().toISOString();
    var user = data.user || "Unknown";
    var computer = data.computer || "Unknown";
    var os = data.os || "Unknown";
    var status = data.status || "Unknown";
    var checkFailures = data.checkFailures || 0;
    var logContent = data.log || "";

    // 1. Log to Google Sheet
    var sheet = getOrCreateTelemetrySheet();
    sheet.appendRow([
      timestamp,
      user,
      computer,
      os,
      status,
      checkFailures,
      logContent.substring(0, 1000) // Brief snippet in sheet
    ]);

    // 2. Save full raw log file to Google Drive folder
    var folder = getOrCreateLogsFolder();
    var logFileName = "install_" + user + "_" + computer + "_" + new Date().getTime() + ".log";
    folder.createFile(logFileName, logContent, MimeType.PLAIN_TEXT);

    return ContentService.createTextOutput(JSON.stringify({ status: "OK", id: logFileName }))
      .setMimeType(ContentService.MimeType.JSON);
  } catch (err) {
    return ContentService.createTextOutput(JSON.stringify({ status: "ERROR", message: err.toString() }))
      .setMimeType(ContentService.MimeType.JSON);
  }
}

function getOrCreateTelemetrySheet() {
  var files = DriveApp.getFilesByName("Flutter_VSCode_Telemetry_Log");
  var ss;
  if (files.hasNext()) {
    ss = SpreadsheetApp.open(files.next());
  } else {
    ss = SpreadsheetApp.create("Flutter_VSCode_Telemetry_Log");
    var s = ss.getActiveSheet();
    s.appendRow(["Timestamp", "User", "Computer", "OS", "Status", "Failures", "Log Snippet"]);
    s.getRange("A1:G1").setFontWeight("bold").setBackground("#EFEFEF");
  }
  return ss.getActiveSheet();
}

function getOrCreateLogsFolder() {
  var folders = DriveApp.getFoldersByName("Flutter_Package_Logs");
  if (folders.hasNext()) {
    return folders.next();
  }
  return DriveApp.createFolder("Flutter_Package_Logs");
}
