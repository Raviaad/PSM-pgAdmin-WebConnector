;~ MIT License
;~ Copyright (c) 2024 Michal Masek - masek@fortwana.sk
;~ Modified for pgAdmin 4 installed desktop application - local PostgreSQL authentication
;~ Adapted by Raviaad

; ============================================================
; pgAdmin 4 - CyberArk PSM AutoIT Connector
; Type:   Desktop application (installed pgAdmin4.exe)
; Target: pgAdmin 4 installed on PSM server or target machine
; Auth:   Form-based (local pgAdmin email + password)
; Notes:  pgAdmin installed app runs its own internal web server
;         and opens in a bundled Chromium window (NOT Google Chrome)
;         Do NOT use Chrome launcher - use pgAdmin4.exe directly
; ============================================================

; ============================================================
; HOW TO COMPILE
; ============================================================
; 1. Edit all CHANGE_ME values below
; 2. cd "C:\Program Files (x86)\AutoIt3\Aut2Exe"
; 3. .\Aut2Exe.exe /in "C:\Program Files (x86)\CyberArk\PSM\Components\pgAdmin4-web_PSM.au3" /out "C:\Program Files (x86)\CyberArk\PSM\Components\pgAdmin4-web_PSM.exe" /x86
; 4. Copy pgAdmin4-web_PSM.exe to Components folder on ALL PSM servers
;
; ============================================================
; APPLOCKER - add this line to your AppLocker XML then run the AppLocker script
; ============================================================
;   <Application Name="pgAdmin4-web_PSM" Type="Exe" Path="C:\Program Files (x86)\CyberArk\PSM\Components\pgAdmin4-web_PSM.exe" Method="Hash" />
;
; ============================================================
; CYBERARK ACCOUNT FIELD MAPPING
; ============================================================
; Username  = pgAdmin login email address  e.g. admin@admin.com
; Password  = pgAdmin login password
; Address   = NOT USED for desktop install (pgAdmin4.exe is launched locally)
; ============================================================

#include "PSMGenericClientWrapper.au3"
#include "Constants.au3"
#include "ScreenCapture.au3"
#include "WindowsConstants.au3"

; #FUNCTION# ===============================================================
; Name...........: FetchSessionProperties
; Description ...: Fetches Username and Password from CyberArk session
;                  Address is retrieved but not used for local desktop install
; ==========================================================================
Func FetchSessionProperties()
    If (PSMGenericClient_GetSessionProperty("Username", $TargetUsername) <> $PSM_ERROR_SUCCESS) Then
        Error(PSMGenericClient_PSMGetLastErrorString())
    EndIf
    If (PSMGenericClient_GetSessionProperty("Password", $TargetPassword) <> $PSM_ERROR_SUCCESS) Then
        Error(PSMGenericClient_PSMGetLastErrorString())
    EndIf
    ; Address is fetched but not required for local pgAdmin4.exe launch
    PSMGenericClient_GetSessionProperty("Address", $TargetAddress)
EndFunc

;=======================================
; Consts & Globals
;=======================================
Global $ConnectionClientPID = 0
Global $TargetUsername
Global $TargetPassword
Global $TargetAddress

; Dispatcher name shown in PSM logs and error dialogs
Global Const $DISPATCHER_NAME         = "pgAdmin4"

; Connection Component ID - must exactly match the Id attribute in CC-pgAdmin4-web.xml
Global Const $ConnectionComponent_NAME = "pgAdmin4-web"

Global Const $ERROR_MESSAGE_TITLE      = "PSM " & $DISPATCHER_NAME & " Dispatcher error message"
Global Const $LOG_MESSAGE_PREFIX       = $DISPATCHER_NAME & " Dispatcher - "
Global Const $iScreenWidth             = @DesktopWidth
Global Const $iScreenHeight            = @DesktopHeight

; ============================================================
; pgAdmin 4 executable path
; CHANGE_ME - update version number to match your installed pgAdmin 4 version
; Default install path for pgAdmin 4 on Windows:
;   C:\Program Files\pgAdmin 4\v8\runtime\pgAdmin4.exe   (v8 example)
;   C:\Program Files\pgAdmin 4\v6\runtime\pgAdmin4.exe   (v6 example)
; Check your installed version under C:\Program Files\pgAdmin 4\
; ============================================================
Global Const $PGADMIN_EXE = "C:\Program Files\pgAdmin 4\v8\runtime\pgAdmin4.exe"  ; CHANGE_ME

; How long (ms) to wait for the pgAdmin window to appear after launch
; Increase this on slow machines - pgAdmin startup can take 20-60 seconds
Global Const $AppTimeout    = 60000  ; CHANGE_ME if pgAdmin is slow to start (milliseconds)
Global Const $AppTimeoutSec = 60     ; Same value in seconds for WinWait calls

; ============================================================
; pgAdmin 4 Window Titles
; WinTitleMatchMode=2 (contains) is used, so partial titles work
;
; LOGIN page title  : pgAdmin 4 shows "Login" or "pgAdmin 4" in the title
;                     Test with WinGetTitle("[ACTIVE]") on your version
; POST-LOGIN title  : After login pgAdmin 4 shows "pgAdmin 4 - Browser" or
;                     "pgAdmin 4 - Dashboard" depending on version
; ============================================================
Global Const $PAGE_LOADED_TITLE  = "pgAdmin 4"         ; CHANGE_ME - title substring on login page
Global Const $LOGIN_SUCCESS_TITLE = "pgAdmin 4"        ; CHANGE_ME - pgAdmin 4 reuses same title;
                                                       ; if your version changes title after login,
                                                       ; set this to the post-login title substring

; WinTitleMatchMode 2 = partial/contains match (best for pgAdmin as title includes DB name post-login)
Opt("WinTitleMatchMode", 2)

; Auto-login: yes = auto-type credentials; no = open pgAdmin only (user types manually)
Global Const $AutoLogin = "yes"  ; CHANGE_ME

; ============================================================
; pgAdmin 4 Login Form - Tab Navigation
;
; pgAdmin login page field order:
;   1. Email (username) field  <- focus lands here automatically on page load
;   2. Password field
;   3. Login button
;
; $Tabs_Before_Username    : tabs needed BEFORE typing the email/username
;                            0 = Email field is already focused on load
; $Tabs_From_Username_To_Password : tabs needed to move from email -> password
;                            1 = one TAB moves from Email to Password
; ============================================================
Global Const $Tabs_Before_Username          = 0  ; CHANGE_ME if focus is not on Email field
Global Const $Tabs_From_Username_To_Password = 1  ; CHANGE_ME if tab order differs in your version
Global Const $Submit_Login                  = "{ENTER}"

; Extra wait time (ms) after pgAdmin window appears before typing credentials
; pgAdmin renders its login form asynchronously - typing too early misses the fields
Global Const $FormRenderWait = 5000  ; CHANGE_ME - increase on slow machines (milliseconds)

; Post-login wait (ms) before verifying dashboard has loaded
; pgAdmin loads the browser tree after login which can be slow
Global Const $PostLoginWait = 6000   ; CHANGE_ME - increase on slow servers (milliseconds)

;=======================================
; Entry Point
;=======================================
Exit Main()

;=======================================
; Main
;=======================================
Func Main()
    ; -------------------------------------------------------
    ; Init PSM Dispatcher utils wrapper
    ; -------------------------------------------------------
    If (PSMGenericClient_Init() <> $PSM_ERROR_SUCCESS) Then
        Error(PSMGenericClient_PSMGetLastErrorString())
    EndIf
    LogWrite("INFO: Successfully initialized Dispatcher Utils Wrapper")

    ; -------------------------------------------------------
    ; Get credentials from CyberArk vault
    ; -------------------------------------------------------
    FetchSessionProperties()
    LogWrite("INFO: Session properties fetched - Username: " & $TargetUsername)

    ; -------------------------------------------------------
    ; Phase 1 - Launch pgAdmin4.exe
    ; pgAdmin installed app manages its own internal web server
    ; and renders in a bundled Chromium window - NOT Google Chrome
    ; -------------------------------------------------------
    LogWrite("INFO: Launching pgAdmin 4 desktop application: " & $PGADMIN_EXE)

    If Not FileExists($PGADMIN_EXE) Then
        Error("pgAdmin4.exe not found at: " & $PGADMIN_EXE & ". Update $PGADMIN_EXE with your installed path.")
    EndIf

    $ConnectionClientPID = Run($PGADMIN_EXE, "", @SW_SHOWMAXIMIZED)

    If ($ConnectionClientPID == 0) Then
        Error(StringFormat("Failed to launch pgAdmin4.exe [%s] - Error: %s", $PGADMIN_EXE, @error))
    EndIf

    LogWrite("INFO: pgAdmin4.exe launched with PID: " & $ConnectionClientPID)

    ; Send PID to PSM immediately after launch so session recording starts
    LogWrite("INFO: Sending PID to PSM for session monitoring")
    If (PSMGenericClient_SendPID($ConnectionClientPID) <> $PSM_ERROR_SUCCESS) Then
        Error(PSMGenericClient_PSMGetLastErrorString())
    EndIf
    LogWrite("INFO: PID sent - PSM session recording active")

    ; Phase 1 end

    ; -------------------------------------------------------
    ; Phase 2 - Wait for pgAdmin login window and auto-type credentials
    ; pgAdmin 4 login page: Email field -> Tab -> Password -> Enter
    ; -------------------------------------------------------
    LogWrite("INFO: Waiting for pgAdmin login window title containing: '" & $PAGE_LOADED_TITLE & "'")

    ; Wait for the pgAdmin window to appear
    WinWait($PAGE_LOADED_TITLE, "", $AppTimeoutSec)

    If Not WinExists($PAGE_LOADED_TITLE) Then
        $currentTime = @HOUR & ":" & @MIN & ":" & @SEC & " " & @MDAY & "/" & @MON & "/" & @YEAR
        $errorMsg = "ERROR: pgAdmin window '" & $PAGE_LOADED_TITLE & "' did not appear within " & $AppTimeoutSec & "s. "
        $errorMsg &= "Verify pgAdmin4.exe path and that pgAdmin starts correctly. "
        $errorMsg &= "Session: " & $ConnectionComponent_NAME & "/" & $TargetUsername & "/" & $currentTime
        LogWrite($errorMsg)
        SplashTextOn("Error", $errorMsg, $iScreenWidth, $iScreenHeight)
        Sleep(30000)
        Exit
    EndIf

    WinActivate($PAGE_LOADED_TITLE)
    Local $ActiveWindow = WinGetTitle("[ACTIVE]")
    LogWrite("INFO: pgAdmin window found - title: '" & $ActiveWindow & "'")

    If $AutoLogin = "yes" Then
        ; Wait for pgAdmin login form to fully render
        ; pgAdmin uses an embedded Chromium renderer that loads asynchronously
        LogWrite("INFO: Waiting " & $FormRenderWait & "ms for login form to render...")
        Sleep($FormRenderWait)

        ; Tab to Email field if not already focused
        If $Tabs_Before_Username > 0 Then
            LogWrite("INFO: Sending " & $Tabs_Before_Username & " TAB(s) to reach Email field")
            For $i = 1 To $Tabs_Before_Username
                Send("{TAB}")
                Sleep(200)
            Next
        EndIf

        ; Type the pgAdmin login email (username)
        ; Flag 1 = raw mode - sends characters as-is including @ symbol in email addresses
        LogWrite("INFO: Typing username (email) into pgAdmin login form")
        Send($TargetUsername, 1)
        Sleep(500)

        ; Tab from Email to Password field
        LogWrite("INFO: Sending " & $Tabs_From_Username_To_Password & " TAB(s) to reach Password field")
        For $i = 1 To $Tabs_From_Username_To_Password
            Send("{TAB}")
            Sleep(200)
        Next
        Sleep(400)

        ; Type password
        ; Flag 1 = raw mode - required for passwords with special characters
        LogWrite("INFO: Typing password")
        Send($TargetPassword, 1)
        Sleep(500)

        ; Submit the login form
        LogWrite("INFO: Submitting login form with ENTER")
        Send($Submit_Login)

        ; Wait for pgAdmin dashboard/browser tree to load after login
        LogWrite("INFO: Waiting " & $PostLoginWait & "ms for pgAdmin dashboard to load...")
        Sleep($PostLoginWait)

        ; Verify post-login window exists
        WinWait($LOGIN_SUCCESS_TITLE, "", $AppTimeoutSec)
        $ActiveWindow = WinGetTitle("[ACTIVE]")
        LogWrite("INFO: Post-login active window: '" & $ActiveWindow & "'")

        If WinExists($LOGIN_SUCCESS_TITLE) Then
            WinActivate($LOGIN_SUCCESS_TITLE)
            LogWrite("INFO: Login SUCCESS - pgAdmin dashboard loaded")
            SplashOff()
        Else
            $currentTime = @HOUR & ":" & @MIN & ":" & @SEC & " " & @MDAY & "/" & @MON & "/" & @YEAR
            $errorMsg = "ERROR: pgAdmin dashboard window '" & $LOGIN_SUCCESS_TITLE & "' not found after login attempt. "
            $errorMsg &= "Check credentials and pgAdmin master password settings. "
            $errorMsg &= "Session: " & $ConnectionComponent_NAME & "/" & $TargetUsername & "/" & $currentTime
            LogWrite($errorMsg)
            SplashTextOn("Error", "pgAdmin login verification failed. " & $errorMsg, $iScreenWidth, $iScreenHeight)
            Sleep(30000)
            If ($ConnectionClientPID <> 0) Then ProcessClose($ConnectionClientPID)
            Exit
        EndIf

    ElseIf $AutoLogin = "no" Then
        ; Manual mode - just bring pgAdmin window forward, user logs in themselves
        LogWrite("INFO: AutoLogin=no - pgAdmin window opened, manual login required")
        WinActivate($PAGE_LOADED_TITLE)
        SplashOff()
        LogWrite("INFO: pgAdmin login page active - waiting for user interaction")
    EndIf

    ; Phase 2 end

    ; -------------------------------------------------------
    ; Phase 3 - Terminate PSM Dispatcher utils wrapper
    ; -------------------------------------------------------
    LogWrite("INFO: Terminating Dispatcher Utils Wrapper - session handoff complete")
    PSMGenericClient_Term()

    Return $PSM_ERROR_SUCCESS
EndFunc

;==================================
; Helper Functions
;==================================
Func Error($ErrorMessage, $Code = -1)
    If (PSMGenericClient_IsInitialized()) Then
        LogWrite($ErrorMessage, True)
        PSMGenericClient_Term()
    EndIf
    Local $MessageFlags = BitOr(0, 16, 262144)
    MsgBox($MessageFlags, $ERROR_MESSAGE_TITLE, $ErrorMessage)
    If ($ConnectionClientPID <> 0) Then
        ProcessClose($ConnectionClientPID)
        $ConnectionClientPID = 0
    EndIf
    Exit $Code
EndFunc

Func LogWrite($sMessage, $LogLevel = $LOG_LEVEL_TRACE)
    Return PSMGenericClient_LogWrite($LOG_MESSAGE_PREFIX & $sMessage, $LogLevel)
EndFunc
