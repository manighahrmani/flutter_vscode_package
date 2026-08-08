# Remote Telemetry & Log Collection Setup

This folder contains zero-cost, automated receivers to collect and analyze installation logs from student computers in real-time.

## Recommended Option: Google Drive & Google Sheets (Free & Zero Maintenance)

1. Open [Google Apps Script](https://script.google.com) and click **New Project**.
2. Paste the contents of [`google_apps_script.js`](./google_apps_script.js).
3. Click **Deploy** -> **New deployment**:
   - Select **Web app**.
   - Execute as: **Me**.
   - Who has access: **Anyone**.
4. Copy the resulting **Web App URL**.
5. Set `$TelemetryEndpoint` in `install.ps1`:
   ```powershell
   $TelemetryEndpoint = "https://script.google.com/macros/s/YOUR_DEPLOYMENT_ID/exec"
   ```

### What happens automatically:
- Every installation (successful or failed) appends a row to a Google Sheet (`Flutter_VSCode_Telemetry_Log`).
- The full `.log` file is automatically saved into a Google Drive folder (`Flutter_Package_Logs`) for easy search and error diagnosis.
