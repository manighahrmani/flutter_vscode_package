/**
 * Google Apps Script - Remote Log & Telemetry Collector for Portable Flutter VS Code Package
 * 
 * SETUP INSTRUCTIONS:
 * 1. Go to https://script.google.com and paste this entire code into `Code.gs`.
 * 2. Click "Deploy" -> "Manage deployments" -> Edit -> "New version" -> Deploy.
 *    - Execute as: "Me" (your Google account).
 *    - Who has access: "Anyone".
 */

function doPost(e) {
  try {
    var data = JSON.parse(e.postData.contents);
    var timestamp = data.timestamp || new Date().toISOString();
    var eventType = data.event || data.status || "UNKNOWN";
    var user = data.user || "Unknown";
    var computer = data.computer || "Unknown";
    var os = data.os || "Unknown";
    var choice = data.choice || data.detail || "";
    var duration = data.duration || "";
    var checkFailures = data.checkFailures !== undefined ? data.checkFailures : 0;
    var logContent = data.log || "";

    // 1. Save full raw log file to Google Drive folder if log content exists
    var fileUrl = "";
    if (logContent && logContent.trim().length > 0) {
      var folder = getOrCreateLogsFolder();
      var logFileName = eventType.toLowerCase() + "_" + user + "_" + computer + "_" + new Date().getTime() + ".log";
      var file = folder.createFile(logFileName, logContent, MimeType.PLAIN_TEXT);
      fileUrl = file.getUrl();
    }

    // 2. Log row to Google Sheet
    var sheet = getOrCreateTelemetrySheet();
    sheet.appendRow([
      timestamp,
      eventType,
      user,
      computer,
      choice,
      duration,
      checkFailures,
      os,
      fileUrl
    ]);

    return ContentService.createTextOutput(JSON.stringify({ status: "OK", fileUrl: fileUrl }))
      .setMimeType(ContentService.MimeType.JSON);
  } catch (err) {
    return ContentService.createTextOutput(JSON.stringify({ status: "ERROR", message: err.toString() }))
      .setMimeType(ContentService.MimeType.JSON);
  }
}

function getOrCreateTelemetrySheet() {
  var spreadsheetId = "1idrl2NuRNIKa4jzQEqznFOmP5nt6yj6TsGEv54msdXE";
  var ss;
  try {
    ss = SpreadsheetApp.openById(spreadsheetId);
  } catch (e) {
    var files = DriveApp.getFilesByName("Flutter_VSCode_Telemetry_Log");
    if (files.hasNext()) {
      ss = SpreadsheetApp.open(files.next());
    } else {
      ss = SpreadsheetApp.create("Flutter_VSCode_Telemetry_Log");
    }
  }
  var s = ss.getActiveSheet();
  if (s.getLastRow() === 0) {
    s.appendRow(["Timestamp", "Event", "Student / User", "Computer", "Choice / Details", "Duration", "Failures", "OS", "Log File Link"]);
    s.getRange("A1:I1").setFontWeight("bold").setBackground("#D9E1F2");
    s.setFrozenRows(1);
  }
  return s;
}

function getOrCreateLogsFolder() {
  var folders = DriveApp.getFoldersByName("Flutter_Package_Logs");
  if (folders.hasNext()) {
    return folders.next();
  }
  return DriveApp.createFolder("Flutter_Package_Logs");
}
