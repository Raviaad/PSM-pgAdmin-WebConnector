;~ MIT License
;~ Copyright (c) 2024 Michal Masek - masek@fortwana.sk
;~ Modified for pgAdmin 4 local PostgreSQL authentication
;~ Adapted by Raviaad

; ============================================================
; pgAdmin 4 - CyberArk PSM AutoIT Web Connector
; Target: pgAdmin 4 web UI (default: http://localhost:5050)
; Auth:   Form-based (local pgAdmin master password / postgres user)
; ============================================================

; Convert to exe after editing
; Place into C:\Program Files (x86)\CyberArk\PSM\Components\
; Add to applocker:
;    <Application Name="pgAdmin4-web_PSM" Type="Exe" Path="C:\Program Files (x86)\CyberArk\PSM\Components\pgAdmin4-web_PSM.exe" Method="Hash" />
; Exe conversion command:
; cd "C:\Program Files (x86)\AutoIt3\Aut2Exe"
; .\Aut2Exe.exe /in "C:\Program Files (x86)\CyberArk\PSM\Components\pgAdmin4-web_PSM.au3" /out "C:\Program Files (x86)\CyberArk\PSM\Components\pgAdmin4-web_PSM.exe" /x86

#include "PSMGenericClientWrapper.au3"
#include "Constants.au3"
#include "ScreenCapture.au3"
#include "WindowsConstants.au3"

; #FUNCTION# ====================================================================================================================
; Name...........: FetchSessionProperties
; Description ...: Fetches Username, Password, Address from CyberArk session
; ===============================================================================================================================
Func FetchSessionProperties()
    If (PSMGenericClient_GetSessionProperty("Username", $TargetUsername) <> $PSM_ERROR_SUCCESS) Then
        Error(PSMGenericClient_PSMGetLastErrorString())
    EndIf
    If (PSMGenericClient_GetSessionProperty("Password", $TargetPassword) <> $PSM_ERROR_SUCCESS) Then
        Error(PSMGenericClient_PSMGetLastErrorString())
    EndIf
    If (PSMGenericClient_GetSessionProperty("Address", $TargetAddress) <> $PSM_ERROR_SUCCESS) Then
        Error(PSMGenericClient_PSMGetLastErrorString())
    EndIf
EndFunc

;=======================================
; Consts & Globals
;=======================================
Global $ConnectionClientPID = 0
Global $TargetUsername
Global $TargetPassword
Global $TargetAddress

; Browser name shown in logs and error messages
Global Const $DISPATCHER_NAME = "Google Chrome"

; Connection Component ID - must match the Id attribute in your XML
Global Const $ConnectionComponent_NAME = "pgAdmin4-web"

Global Const $ERROR_MESSAGE_TITLE  = "PSM " & $DISPATCHER_NAME & " Dispatcher error message"
Global Const $LOG_MESSAGE_PREFIX   = $DISPATCHER_NAME & " Dispatcher - "
Global Const $iScreenWidth  = @DesktopWidth
Global Const $iScreenHeight = @DesktopHeight

; How long (seconds) to wait for browser/page to appear
Global Const $AppTimeout    = "45"  ; CHANGE_ME if pgAdmin is slow to start
Global Const $WindowTimeout = "60"  ; CHANGE_ME - not actively used in default flow

; pgAdmin 4 default URL parts
; Address field in CyberArk should contain ONLY the host, e.g. "localhost" or "10.0.0.5"
; Port 5050 is the pgAdmin default - adjust if yours is different
Global $WebPrefix = "http://"        ; CHANGE_ME to https:// if TLS is enabled
Global $WebSuffix = ":5050/login"    ; CHANGE_ME if your pgAdmin port differs

; Autologin: pgAdmin local auth uses a form (email + password)
Global Const $AutoLogin          = "yes"   ; yes = auto-type credentials; no = open browser only
Global Const $AuthenticationMode = "form"  ; pgAdmin does NOT support HTTP Basic auth - must be form

; Verification mode
; "title"  - match window titles before/after login
; "color"  - use PixelSearch on a characteristic colour
; pgAdmin 4 has distinct titles so "title" is the most reliable option here
Global Const $VerificationMode = "title"

; Window title of the pgAdmin 4 LOGIN page (contains this substring)
Global Const $PAGE_LOADED_TITLE   = "pgAdmin 4"   ; CHANGE_ME if your version shows a different title
; Window title AFTER successful login (the dashboard/browser tree page)
Global Const $LOGIN_SUCCESS_TITLE = "pgAdmin 4"   ; CHANGE_ME - pgAdmin keeps the same title; adjust if your build differs

; Color values are only used when $VerificationMode = "color"
; Leave as-is when using title mode, but populate if you switch to color mode
Global Const $PAGE_LOADED_COLOR   = "0x336791"  ; CHANGE_ME - pgAdmin blue header (approx)
Global Const $LOGIN_SUCCESS_COLOR = "0x4D4D4D"  ; CHANGE_ME - pgAdmin dashboard sidebar (approx)
Global Const $ColorErrorHandling  = "yes"

; WinTitleMatchMode: 2 = contains (recommended for pgAdmin as title may include DB name after login)
Opt("WinTitleMatchMode", 2)

; Login form tab navigation for pgAdmin 4
; pgAdmin login page: Email field is first, then Password
; Focus lands on the Email field automatically, so 0 tabs needed before username
Global Const $Tabs_Before_Username          = "0"  ; CHANGE_ME if focus is elsewhere on your pgAdmin version
Global Const $Tabs_From_Username_To_Password = "1"  ; 1 TAB moves from Email -> Password field
Global Const $Submit_Login                  = "{ENTER}"

; Kiosk mode hides browser chrome for a cleaner PSM session
Global Const $KioskMode = "yes"  ; CHANGE_ME - set to "no" if you need the address bar visible

; WARNING: --ignore-certificate-errors is for lab/dev only. Remove for production.
If $KioskMode = "yes" Then
    Global $connect = "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe --private --no-first-run --no-default-browser-check --ignore-certificate-errors --disable-translate --kiosk "
ElseIf $KioskMode = "no" Then
    Global $connect = "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe --private --no-first-run --no-default-browser-check --ignore-certificate-errors --disable-translate "
EndIf

;=======================================
; Entry Point
;=======================================
Exit Main()

;=======================================
; Main
;=======================================
Func Main()

    ; Init PSM Dispatcher utils wrapper
    If (PSMGenericClient_Init() <> $PSM_ERROR_SUCCESS) Then
        Error(PSMGenericClient_PSMGetLastErrorString())
    EndIf

    LogWrite("INFO: Successfully initialized Dispatcher Utils Wrapper")
    LogWrite("INFO: Verification mode is set to " & $VerificationMode & " mode")

    ; Get credentials from CyberArk
    FetchSessionProperties()

    LogWrite("INFO: Variables set successfully")
    LogWrite("INFO: Target address is " & $TargetAddress)

    ; -------------------------------------------------------
    ; Phase 1 - Launch Chrome and navigate to pgAdmin login
    ; -------------------------------------------------------
    LogWrite("INFO: Starting client application - " & $DISPATCHER_NAME)

    ; AuthenticationMode is always "form" for pgAdmin
    Global Const $CLIENT_EXECUTABLE = $connect & $WebPrefix & $TargetAddress & $WebSuffix

    $ConnectionClientPID = Run($CLIENT_EXECUTABLE, "", @SW_SHOWMAXIMIZED)
    LogWrite("INFO: Executed Chrome targeting pgAdmin at " & $WebPrefix & $TargetAddress & $WebSuffix)

    If ($ConnectionClientPID == 0) Then
        Error(StringFormat("Failed to execute process [%s]", $connect, @error))
    EndIf
    ; Phase 1 end

    ; -------------------------------------------------------
    ; Phase 2 - Wait for login page and auto-type credentials
    ; pgAdmin 4 login: Email field -> Password field -> Enter
    ; -------------------------------------------------------
    If $VerificationMode = "title" And $AuthenticationMode = "form" Then
        LogWrite("INFO: Verification=title, Auth=form")

        $window1 = $PAGE_LOADED_TITLE
        $window2 = $LOGIN_SUCCESS_TITLE
        LogWrite("INFO: Waiting for login page window: " & $window1)

        If $AutoLogin = "yes" Then
            WinWait($window1, "", $AppTimeout)
            $ActiveWindow = WinGetTitle("[ACTIVE]")
            LogWrite("INFO: Current window title is " & $ActiveWindow)

            If WinExists($window1) Then
                WinActivate($window1)
                $Window1RealTitle = WinGetTitle("[ACTIVE]")
                LogWrite("INFO: pgAdmin login window title: " & $Window1RealTitle)

                ; Wait extra time for the Angular/React login form to fully render
                Sleep(4000)  ; CHANGE_ME - increase if pgAdmin takes longer to render form elements

                LogWrite("INFO: Typing pgAdmin email/username into first field")

                ; Tab to Email field if needed
                For $i = 1 To $Tabs_Before_Username
                    Send("{TAB}")
                Next

                ; Type the username (pgAdmin uses email address as username for local auth)
                Send($TargetUsername, 1)
                Sleep(600)

                ; Tab to Password field
                For $i = 1 To $Tabs_From_Username_To_Password
                    Send("{TAB}")
                Next
                Sleep(600)

                LogWrite("INFO: Typing password")
                Send($TargetPassword, 1)
                Sleep(600)

                LogWrite("INFO: Submitting login form")
                Send($Submit_Login)
                LogWrite("INFO: Login submitted, waiting for dashboard to load...")

                ; Wait for pgAdmin dashboard to appear after login
                ; pgAdmin 4 loads a dashboard with the same title - wait extra time
                Sleep(5000)  ; CHANGE_ME - increase on slow servers

                WinWait($window2, "", $AppTimeout)
                $ActiveWindow = WinGetTitle("[ACTIVE]")
                LogWrite("INFO: Post-login window title: " & $ActiveWindow)

                If WinExists($window2) Then
                    WinActivate($window2)
                    LogWrite("INFO: Login success verified - pgAdmin dashboard is loaded")
                    SplashOff()
                Else
                    $currentTime = @HOUR & ":" & @MIN & ":" & @SEC & " " & @MDAY & "/" & @MON & "/" & @YEAR
                    $errorMsg  = "ERROR: pgAdmin4 PSM failed - dashboard window not found after login. "
                    $errorMsg &= "Session: " & $ConnectionComponent_NAME & "/" & $TargetUsername & "/" & $TargetAddress & "/" & $currentTime
                    LogWrite($errorMsg)
                    SplashTextOn("Error", "pgAdmin login verification failed. " & $errorMsg, $iScreenWidth, $iScreenHeight)
                    Sleep(30000)
                    WinClose($ActiveWindow)
                    Exit
                EndIf

            Else
                $currentTime = @HOUR & ":" & @MIN & ":" & @SEC & " " & @MDAY & "/" & @MON & "/" & @YEAR
                $errorMsg  = "ERROR: pgAdmin4 PSM failed - login page window '" & $window1 & "' not found within timeout. "
                $errorMsg &= "Session: " & $ConnectionComponent_NAME & "/" & $TargetUsername & "/" & $TargetAddress & "/" & $currentTime
                LogWrite($errorMsg)
                SplashTextOn("Error", $errorMsg, $iScreenWidth, $iScreenHeight)
                Sleep(30000)
                WinClose($ActiveWindow)
                Exit
            EndIf

        ElseIf $AutoLogin = "no" Then
            LogWrite("INFO: AutoLogin=no, opening pgAdmin login page only")
            WinWait($window1, "", $AppTimeout)
            $ActiveWindow = WinGetTitle("[ACTIVE]")
            If WinExists($window1) Then
                WinActivate($window1)
                SplashOff()
                LogWrite("INFO: pgAdmin login page loaded, user may interact")
            Else
                $currentTime = @HOUR & ":" & @MIN & ":" & @SEC & " " & @MDAY & "/" & @MON & "/" & @YEAR
                $errorMsg  = "ERROR: pgAdmin4 PSM - login page not found. "
                $errorMsg &= "Session: " & $ConnectionComponent_NAME & "/" & $TargetUsername & "/" & $TargetAddress & "/" & $currentTime
                LogWrite($errorMsg)
                SplashTextOn("Error", $errorMsg, $iScreenWidth, $iScreenHeight)
                Sleep(30000)
                WinClose($ActiveWindow)
                Exit
            EndIf
        EndIf

    ElseIf $VerificationMode = "color" And $AuthenticationMode = "form" Then
        ; Color mode (fallback) - populate $PAGE_LOADED_COLOR / $LOGIN_SUCCESS_COLOR above
        LogWrite("INFO: Verification=color, Auth=form")
        $window1 = "Google Chrome"
        WinWait($window1, "", $AppTimeout)
        $ActiveWindow = WinGetTitle("[ACTIVE]")
        If WinExists($window1) Then
            WinActivate($window1)
            SplashOff()
            Local $startTime = TimerInit()
            While True
                $colorFound = PixelSearch(0, 0, @DesktopWidth, @DesktopHeight, $PAGE_LOADED_COLOR)
                If Not @error Then
                    LogWrite("INFO: Login page colour found - " & $PAGE_LOADED_COLOR)
                    ExitLoop
                EndIf
                If TimerDiff($startTime) > $AppTimeout * 1000 Then
                    $currentTime = @HOUR & ":" & @MIN & ":" & @SEC & " " & @MDAY & "/" & @MON & "/" & @YEAR
                    $errorMsg  = "ERROR: pgAdmin login page colour not found within timeout. "
                    $errorMsg &= "Session: " & $ConnectionComponent_NAME & "/" & $TargetUsername & "/" & $TargetAddress & "/" & $currentTime
                    LogWrite($errorMsg)
                    SplashTextOn("Error", $errorMsg, $iScreenWidth, $iScreenHeight)
                    Sleep(30000)
                    WinClose($ActiveWindow)
                    Exit
                EndIf
                Sleep(1000)
            WEnd

            Sleep(3000)
            For $i = 1 To $Tabs_Before_Username
                Send("{TAB}")
            Next
            Send($TargetUsername, 1)
            Sleep(600)
            For $i = 1 To $Tabs_From_Username_To_Password
                Send("{TAB}")
            Next
            Sleep(600)
            Send($TargetPassword, 1)
            Sleep(600)
            Send($Submit_Login)

            If $ColorErrorHandling = "yes" Then
                Sleep(3000)
                Send("{F5}")
            EndIf

            SplashOff()
            Local $startTime2 = TimerInit()
            While True
                $colorFound = PixelSearch(0, 0, @DesktopWidth, @DesktopHeight, $LOGIN_SUCCESS_COLOR)
                If Not @error Then
                    LogWrite("INFO: Login success colour found - " & $LOGIN_SUCCESS_COLOR)
                    ExitLoop
                EndIf
                If TimerDiff($startTime2) > $AppTimeout * 1000 Then
                    $currentTime = @HOUR & ":" & @MIN & ":" & @SEC & " " & @MDAY & "/" & @MON & "/" & @YEAR
                    $errorMsg  = "ERROR: pgAdmin dashboard colour not found - login may have failed. "
                    $errorMsg &= "Session: " & $ConnectionComponent_NAME & "/" & $TargetUsername & "/" & $TargetAddress & "/" & $currentTime
                    LogWrite($errorMsg)
                    SplashTextOn("Error", $errorMsg, $iScreenWidth, $iScreenHeight)
                    Sleep(30000)
                    WinClose($ActiveWindow)
                    Exit
                EndIf
                Sleep(1000)
            WEnd
        Else
            $currentTime = @HOUR & ":" & @MIN & ":" & @SEC & " " & @MDAY & "/" & @MON & "/" & @YEAR
            $errorMsg  = "ERROR: Chrome window not found. "
            $errorMsg &= "Session: " & $ConnectionComponent_NAME & "/" & $TargetUsername & "/" & $TargetAddress & "/" & $currentTime
            LogWrite($errorMsg)
            SplashTextOn("Error", $errorMsg, $iScreenWidth, $iScreenHeight)
            Sleep(30000)
            WinClose($ActiveWindow)
            Exit
        EndIf
    EndIf
    ; Phase 2 end

    ; Send PID to PSM so recording/monitoring starts
    LogWrite("INFO: Sending PID to PSM")
    If (PSMGenericClient_SendPID($ConnectionClientPID) <> $PSM_ERROR_SUCCESS) Then
        Error(PSMGenericClient_PSMGetLastErrorString())
    EndIf
    LogWrite("INFO: PID sent successfully - session monitoring active")

    ; Terminate PSM Dispatcher utils wrapper
    LogWrite("INFO: Terminating Dispatcher Utils Wrapper - DONE")
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
