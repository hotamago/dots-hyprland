import qs
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam

Scope {
    id: root

    enum ActionEnum { Unlock, Poweroff, Reboot }

    signal shouldReFocus()
    signal unlocked(targetAction: var)
    signal failed()

    // These properties are in the context and not individual lock surfaces
    // so all surfaces can share the same state.
    property string currentText: ""
    property bool unlockInProgress: false
    property bool showFailure: false
    property bool fingerprintsConfigured: false
    property var targetAction: LockContext.ActionEnum.Unlock
    property bool alsoInhibitIdle: false
    
    // Fingerprint verification state
    property string fingerprintVerifyResult: "none" // "none", "verifying", "no-match", "unknown-error", "match"
    property bool fingerprintVerifying: false
    property int consecutiveFailures: 0 // Track consecutive failures to detect unknown-error
    property bool authExpanded: true
    property bool fingerPamAbortExpected: false
    readonly property int fingerprintAuthTimeoutMs: 12000

    function resetTargetAction() {
        root.targetAction = LockContext.ActionEnum.Unlock;
    }

    function clearText() {
        root.currentText = "";
    }

    function resetClearTimer() {
        passwordClearTimer.restart();
    }

    function reset() {
        root.resetTargetAction();
        root.clearText();
        root.unlockInProgress = false;
        root.fingerprintVerifyResult = "none";
        root.fingerprintVerifying = false;
        root.consecutiveFailures = 0;
        root.authExpanded = true;
        root.fingerPamAbortExpected = false;
        authCollapseDelayTimer.stop();
        authAttemptTimeoutTimer.stop();
        stopFingerPam();
        stopFingerprintVerify();
    }

    Timer {
        id: passwordClearTimer
        interval: 10000
        onTriggered: {
            root.reset();
        }
    }

    onCurrentTextChanged: {
        if (currentText.length > 0) {
            showFailure = false;
            GlobalStates.screenUnlockFailed = false;
            root.authExpanded = true;
            authCollapseDelayTimer.stop();
            authAttemptTimeoutTimer.stop();
            stopFingerPam();
            stopFingerprintVerify();
        }
        GlobalStates.screenLockContainsCharacters = currentText.length > 0;
        passwordClearTimer.restart();
    }

    function tryUnlock(alsoInhibitIdle = false) {
        root.alsoInhibitIdle = alsoInhibitIdle;
        root.unlockInProgress = true;
        authAttemptTimeoutTimer.stop();
        authCollapseDelayTimer.stop();
        stopFingerPam();
        stopFingerprintVerify();
        pam.start();
    }

    function expandAuth(startFingerprint = true) {
        root.authExpanded = true;
        authCollapseDelayTimer.stop();
        if (startFingerprint && root.fingerprintsConfigured && GlobalStates.screenLocked && root.currentText.length === 0) {
            tryFingerUnlock();
        }
        root.shouldReFocus();
    }

    function collapseAuth() {
        if (root.currentText.length > 0 || root.unlockInProgress || !root.fingerprintsConfigured) {
            return;
        }
        authCollapseDelayTimer.stop();
        authAttemptTimeoutTimer.stop();
        stopFingerPam();
        stopFingerprintVerify();
        root.fingerprintVerifyResult = "none";
        root.fingerprintVerifying = false;
        root.authExpanded = false;
        root.shouldReFocus();
    }

    function scheduleAuthCollapse(delay = 0) {
        if (root.currentText.length > 0 || root.unlockInProgress || !root.fingerprintsConfigured) {
            return;
        }
        authCollapseDelayTimer.interval = delay;
        authCollapseDelayTimer.restart();
    }

    function tryFingerUnlock() {
        if (root.fingerprintsConfigured && GlobalStates.screenLocked && root.currentText.length === 0 && !fingerPam.active) {
            // Only use PAM for authentication - it handles fingerprint verification
            // fprintd-verify will only be used for error diagnosis if PAM fails
            root.authExpanded = true;
            root.fingerPamAbortExpected = false;
            root.fingerprintVerifyResult = "verifying";
            root.fingerprintVerifying = true;
            authCollapseDelayTimer.stop();
            authAttemptTimeoutTimer.interval = root.fingerprintAuthTimeoutMs;
            authAttemptTimeoutTimer.restart();
            fingerPam.start();
        }
    }

    function stopFingerPam() {
        if (fingerPam.active) {
            root.fingerPamAbortExpected = true;
            fingerPam.abort();
        }
    }
    
    function startFingerprintVerify() {
        if (fingerprintVerifyProc.running) {
            return;
        }
        root.fingerprintVerifying = true;
        root.fingerprintVerifyResult = "verifying";
        fingerprintVerifyProc.output = "";
        fingerprintVerifyProc.errorOutput = "";
        fingerprintVerifyProc.running = true;
    }
    
    function stopFingerprintVerify() {
        if (fingerprintVerifyProc.running) {
            fingerprintVerifyProc.running = false;
        }
        root.fingerprintVerifying = false;
    }

    function refreshFingerprintCheck() {
        fingerprintCheckProc.running = false;
        fingerprintCheckProc.running = true;
    }

    Process {
        id: fingerprintCheckProc
        running: true
        command: ["bash", "-c", "fprintd-list $(whoami)"]
        stdout: StdioCollector {
            id: fingerprintOutputCollector
            onStreamFinished: {
                const output = fingerprintOutputCollector.text || "";
                // Check if there are actual fingerprint entries (lines like " - #0: right-index-finger")
                // Just having "Fingerprints for user" header is not enough - need actual enrolled fingerprints
                const lines = output.split('\n');
                const hasFingerprintEntries = lines.some(line => /^\s*-\s*#\d+:/.test(line.trim()));
                const wasConfigured = root.fingerprintsConfigured;
                root.fingerprintsConfigured = output.includes("Fingerprints for user") && hasFingerprintEntries;
                
                // If fingerprints just became configured and screen is locked, start fingerprint unlock
                if (!wasConfigured && root.fingerprintsConfigured && GlobalStates.screenLocked && root.authExpanded && !fingerPam.active) {
                    Qt.callLater(() => tryFingerUnlock());
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                // console.warn("[LockContext] fprintd-list command exited with error:", exitCode, exitStatus);
                root.fingerprintsConfigured = false;
            }
        }
    }
    
    // Watch for fingerprintsConfigured changes and auto-start unlock if screen is locked
    onFingerprintsConfiguredChanged: {
        // If fingerprints become configured while screen is locked, start fingerprint unlock
        if (fingerprintsConfigured && GlobalStates.screenLocked && root.authExpanded && !fingerPam.active) {
            Qt.callLater(() => tryFingerUnlock());
        }
    }
    
    PamContext {
        id: pam

        // pam_unix will ask for a response for the password prompt
        onPamMessage: {
            if (this.responseRequired) {
                this.respond(root.currentText);
            }
        }

        // pam_unix won't send any important messages so all we need is the completion status.
        onCompleted: result => {
            if (result == PamResult.Success) {
                root.unlocked(root.targetAction);
                stopFingerPam();
            } else {
                root.clearText();
                root.unlockInProgress = false;
                GlobalStates.screenUnlockFailed = true;
                root.showFailure = true;
            }
        }
    }

    PamContext {
        id: fingerPam

        configDirectory: "pam"
        config: "fprintd.conf"

        onCompleted: result => {
            if (result == PamResult.Success) {
                root.fingerPamAbortExpected = false;
                root.fingerprintVerifyResult = "match";
                root.fingerprintVerifying = false;
                root.consecutiveFailures = 0;
                root.unlocked(root.targetAction);
                stopFingerPam();
                stopFingerprintVerify();
            } else {
                authAttemptTimeoutTimer.stop();
                if (root.fingerPamAbortExpected) {
                    root.fingerPamAbortExpected = false;
                    root.fingerprintVerifyResult = "none";
                    root.fingerprintVerifying = false;
                    return;
                }
                // PAM failed - assume no-match for UI feedback
                // Only change state if not already showing no-match (prevents animation retrigger)
                if (root.fingerprintVerifyResult !== "no-match") {
                    root.fingerprintVerifyResult = "no-match";
                    fingerprintErrorResetTimer.restart();
                } else {
                    // Already showing no-match, just restart the timer to keep it visible
                    fingerprintErrorResetTimer.restart();
                }
                root.fingerprintVerifying = false;
                root.consecutiveFailures++;
                
                // Only use fprintd-verify for diagnosis if we have multiple failures
                // This helps detect unknown-error without interfering with normal operation
                if (root.consecutiveFailures >= 3 && !fingerprintVerifyProc.running) {
                    startFingerprintVerify();
                }
                
                // Do not keep the sensor hot by retrying automatically. The next
                // attempt starts only when the user expands auth again.
                scheduleAuthCollapse(3000);
            }
        }
    }
    
    // Process to run fprintd-verify and parse results
    Process {
        id: fingerprintVerifyProc
        property string output: ""
        property string errorOutput: ""
        command: ["fprintd-verify"]
        
        stdout: SplitParser {
            onRead: data => {
                fingerprintVerifyProc.output += data + "\n";
                // Parse the output for verification results
                // Note: fprintd-verify is only used for error diagnosis after PAM fails
                const output = fingerprintVerifyProc.output.toLowerCase();
                if (output.includes("verify result: verify-unknown-error")) {
                    // Override no-match with unknown-error if detected
                    root.fingerprintVerifyResult = "unknown-error";
                    root.fingerprintVerifying = false;
                    // Keep showing error until user acknowledges
                } else if (output.includes("verify result: verify-no-match")) {
                    // Confirm it's no-match (already set by PAM failure)
                    root.fingerprintVerifyResult = "no-match";
                    root.fingerprintVerifying = false;
                } else if (output.includes("verify started")) {
                    root.fingerprintVerifyResult = "verifying";
                }
            }
        }
        
        stderr: SplitParser {
            onRead: data => {
                fingerprintVerifyProc.errorOutput += data + "\n";
            }
        }
        
        onExited: (exitCode, exitStatus) => {
            // If process exited without clear result, check output
            if (root.fingerprintVerifyResult === "verifying") {
                const fullOutput = (fingerprintVerifyProc.output + fingerprintVerifyProc.errorOutput).toLowerCase();
                if (fullOutput.includes("verify-no-match")) {
                    root.fingerprintVerifyResult = "no-match";
                    fingerprintErrorResetTimer.restart();
                } else if (fullOutput.includes("verify-unknown-error")) {
                    root.fingerprintVerifyResult = "unknown-error";
                } else {
                    // Reset to none if no clear result
                    root.fingerprintVerifyResult = "none";
                }
            }
            root.fingerprintVerifying = false;
            
            // Don't restart fprintd-verify automatically - only use it for error diagnosis
            // PAM will handle the actual authentication attempts
            scheduleAuthCollapse(1000);
        }
    }

    Timer {
        id: authAttemptTimeoutTimer
        repeat: false
        onTriggered: {
            stopFingerPam();
            stopFingerprintVerify();
            root.fingerprintVerifyResult = "none";
            root.fingerprintVerifying = false;
            scheduleAuthCollapse(0);
        }
    }

    Timer {
        id: authCollapseDelayTimer
        repeat: false
        onTriggered: root.collapseAuth()
    }
    
    // Timer to reset fingerprint error state after showing it
    Timer {
        id: fingerprintErrorResetTimer
        interval: 3000 // Show error for 3 seconds (longer for better visibility)
        onTriggered: {
            if (root.fingerprintVerifyResult === "no-match") {
                // Only reset if PAM is not currently active (waiting for next scan)
                if (!fingerPam.active) {
                    root.fingerprintVerifyResult = "none";
                } else {
                    // If PAM is still active, restart timer to keep showing error
                    fingerprintErrorResetTimer.restart();
                }
            }
        }
    }
    
}
