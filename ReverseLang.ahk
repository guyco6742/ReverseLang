#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; ==========================================================
;  ReverseLang - ממיר טקסט שהוקלד בשפת מקלדת לא נכונה (עברית/אנגלית)
; ==========================================================

global INI := A_ScriptDir "\settings.ini"
global EN  := "qwertyuiopasdfghjkl;'zxcvbnm,./"
global HE  := "/'קראטוןםפשדגכעיחלךף,זסבהנמצתץ."
global E2H := Map(), H2E := Map()
Loop StrLen(EN) {
    e := SubStr(EN, A_Index, 1), h := SubStr(HE, A_Index, 1)
    E2H[e] := h
    H2E[h] := e
}

; ---------- הגדרות ----------
global CfgHotkey   := IniRead(INI, "General", "Hotkey", "^+e")
global CfgAuto     := IniRead(INI, "General", "AutoMode", "0") = "1"
global CfgMinLen   := Integer(IniRead(INI, "General", "AutoMinLength", "3"))
global CfgNoSel    := IniRead(INI, "General", "NoSelection", "line")   ; line | word
global CfgEnKLID   := IniRead(INI, "General", "EnglishKLID", "00000409")
global CfgHeKLID   := IniRead(INI, "General", "HebrewKLID", "0000040D")
if !FileExist(INI)
    SaveSettings()

; ---------- מילונים (למצב אוטומטי) ----------
global EnDict := LoadDict(A_ScriptDir "\en.txt")
global HeDict := LoadDict(A_ScriptDir "\he.txt")
global Except := LoadDict(A_ScriptDir "\exceptions.txt")

; ---------- תפריט מגש ----------
A_IconTip := "ReverseLang - " HotkeyLabel(CfgHotkey)
tray := A_TrayMenu
tray.Delete()
tray.Add("הגדרות...", ShowSettings)
tray.Default := "הגדרות..."
tray.Add()
tray.Add("המרה אוטומטית תוך כדי הקלדה", ToggleAuto)
tray.Add("הפעלה עם Windows", ToggleStartup)
tray.Add()
tray.Add("פתח קובץ הגדרות", (*) => Run('notepad.exe "' INI '"'))
tray.Add("פתח רשימת חריגים", OpenExceptions)
tray.Add("טען מחדש", (*) => Reload())
tray.Add()
tray.Add("יציאה", (*) => ExitApp())
if CfgAuto
    tray.Check("המרה אוטומטית תוך כדי הקלדה")
if FileExist(A_Startup "\ReverseLang.lnk")
    tray.Check("הפעלה עם Windows")

try Hotkey(CfgHotkey, FixSelection)
catch {
    MsgBox "קיצור המקלדת '" CfgHotkey "' לא תקין. בדוק את settings.ini", "ReverseLang", 48
}

global ih := "", wordBuf := "", History := [], SetGui := ""
if CfgAuto
    StartAuto()

ToolTip "ReverseLang פועל. קיצור: " HotkeyLabel(CfgHotkey)
SetTimer () => ToolTip(), -2500
return

; ==========================================================
;  המרה ידנית
; ==========================================================
FixSelection(*) {
    for k in ["Ctrl", "Alt", "Shift", "LWin", "RWin"]
        KeyWait k, "T1"
    saved := ClipboardAll()
    A_Clipboard := ""
    Send "^c"
    if !ClipWait(0.3) {
        ; אין טקסט מסומן: מסמנים לבד
        Send CfgNoSel = "word" ? "^+{Left}" : "+{Home}"
        Sleep 40
        Send "^c"
        if !ClipWait(0.3) {
            A_Clipboard := saved
            return
        }
    }
    orig := A_Clipboard
    res := Convert(orig)
    AddHistory(orig, res.text)
    A_Clipboard := res.text
    Send "^v"
    Sleep 200
    A_Clipboard := saved
    SetLayout(res.lang)
    global wordBuf := ""
}

; ==========================================================
;  לוגיקת המרה
; ==========================================================
Convert(txt) {
    heb := 0, lat := 0
    Loop Parse txt {
        o := Ord(A_LoopField)
        if (o >= 0x5D0 && o <= 0x5EA)
            heb++
        else if (A_LoopField ~= "[A-Za-z]")
            lat++
    }
    if (heb > lat)
        return {text: ToEng(txt), lang: "en"}
    return {text: ToHeb(txt), lang: "he"}
}

ToHeb(s) {
    out := ""
    Loop Parse s {
        c := StrLower(A_LoopField)
        out .= E2H.Has(c) ? E2H[c] : A_LoopField
    }
    return out
}

ToEng(s) {
    out := ""
    Loop Parse s
        out .= H2E.Has(A_LoopField) ? H2E[A_LoopField] : A_LoopField
    return out
}

SetLayout(lang) {
    klid := lang = "he" ? CfgHeKLID : CfgEnKLID
    hkl := DllCall("LoadKeyboardLayout", "Str", klid, "UInt", 1, "Ptr")
    try PostMessage 0x50, 0, hkl, , "A"
}

; ==========================================================
;  מצב אוטומטי
; ==========================================================
StartAuto() {
    global ih, wordBuf := ""
    ih := InputHook("V I1 L0")
    ih.OnChar := AutoOnChar
    ih.KeyOpt("{Backspace}{Left}{Right}{Up}{Down}{Home}{End}{Delete}{Escape}{Enter}{Tab}", "N")
    ih.OnKeyDown := AutoOnKey
    ih.Start()
}

StopAuto() {
    global ih
    if IsObject(ih)
        ih.Stop()
    ih := ""
}

AutoOnChar(hook, ch) {
    global wordBuf
    if (ch = " ") {
        TryAutoFix()
        wordBuf := ""
    } else if (ch = "`n" || ch = "`r" || ch = "`t") {
        wordBuf := ""
    } else {
        wordBuf .= ch
    }
}

AutoOnKey(hook, vk, sc) {
    global wordBuf
    if (vk = 8)   ; Backspace
        wordBuf := SubStr(wordBuf, 1, -1)
    else
        wordBuf := ""
}

~LButton:: {
    global wordBuf := ""
}

TryAutoFix() {
    global wordBuf
    w := wordBuf
    if (w = "" || Except.Has(w))
        return
    conv := "", lang := ""

    if (w ~= "^[A-Za-z;',./]+$") {
        ; הוקלד באנגלית, אולי התכוונו לעברית
        core := RegExReplace(w, "[^A-Za-z]")
        hebW := ToHeb(w)
        hebCore := RegExReplace(hebW, "[.,/']+$")
        if (StrLen(hebCore) >= CfgMinLen && hebCore ~= "^[\x{5D0}-\x{5EA}]+$"
            && HeDict.Has(hebCore) && !EnDict.Has(core))
            conv := hebW, lang := "he"
    } else if (w ~= "[\x{5D0}-\x{5EA}]") {
        ; הוקלד בעברית, אולי התכוונו לאנגלית
        Loop Parse w
            if !H2E.Has(A_LoopField) && !(A_LoopField ~= "[A-Za-z]")
                return
        core := RegExReplace(w, "[^\x{5D0}-\x{5EA}]")
        engW := ToEng(w)
        engCore := RegExReplace(engW, "[;',./]+$")
        if (StrLen(engCore) >= CfgMinLen && engCore ~= "^[A-Za-z]+$"
            && EnDict.Has(engCore) && !HeDict.Has(core))
            conv := engW, lang := "en"
    }

    if (conv = "")
        return
    AddHistory(w, conv)
    SendLevel 1
    Send "{Backspace " (StrLen(w) + 1) "}"
    SendText conv " "
    SendLevel 0
    SetLayout(lang)
}

; ==========================================================
;  עזרים
; ==========================================================
LoadDict(path) {
    m := Map()
    m.CaseSense := "Off"
    if !FileExist(path)
        return m
    for line in StrSplit(FileRead(path, "UTF-8"), "`n", "`r") {
        line := Trim(line)
        if (line != "" && SubStr(line, 1, 1) != "#")
            m[line] := 1
    }
    return m
}

ToggleAuto(item, *) {
    global CfgAuto := !CfgAuto
    if CfgAuto {
        StartAuto()
        A_TrayMenu.Check(item)
    } else {
        StopAuto()
        A_TrayMenu.Uncheck(item)
    }
    SaveSettings()
}

ToggleStartup(item, *) {
    lnk := A_Startup "\ReverseLang.lnk"
    if FileExist(lnk) {
        FileDelete lnk
        A_TrayMenu.Uncheck(item)
    } else {
        target := A_IsCompiled ? A_ScriptFullPath : A_AhkPath
        args := A_IsCompiled ? "" : '"' A_ScriptFullPath '"'
        FileCreateShortcut target, lnk, A_ScriptDir, args
        A_TrayMenu.Check(item)
    }
}

OpenExceptions(*) {
    p := A_ScriptDir "\exceptions.txt"
    if !FileExist(p)
        FileAppend "# מילה בכל שורה. מילים כאן לא יומרו אוטומטית`n", p, "UTF-8"
    Run 'notepad.exe "' p '"'
}

SaveSettings() {
    IniWrite CfgHotkey, INI, "General", "Hotkey"
    IniWrite CfgAuto ? "1" : "0", INI, "General", "AutoMode"
    IniWrite CfgMinLen, INI, "General", "AutoMinLength"
    IniWrite CfgNoSel, INI, "General", "NoSelection"
    IniWrite CfgEnKLID, INI, "General", "EnglishKLID"
    IniWrite CfgHeKLID, INI, "General", "HebrewKLID"
}

HotkeyLabel(hk) {
    names := Map("^", "Ctrl+", "!", "Alt+", "+", "Shift+", "#", "Win+")
    out := ""
    while (StrLen(hk) > 1 && names.Has(SubStr(hk, 1, 1))) {
        out .= names[SubStr(hk, 1, 1)]
        hk := SubStr(hk, 2)
    }
    return out StrUpper(hk)
}

; ==========================================================
;  היסטוריה
; ==========================================================
AddHistory(src, dst) {
    global History
    History.InsertAt(1, {t: FormatTime(, "HH:mm"), src: src, dst: dst})
    if History.Length > 30
        History.Pop()
    if IsObject(SetGui)
        try FillHistory()
}

; ==========================================================
;  חלון הגדרות
; ==========================================================
ShowSettings(*) {
    global SetGui
    if IsObject(SetGui) {
        SetGui.Show()
        return
    }
    g := Gui("+E0x400000 -MaximizeBox", "ReverseLang - הגדרות")
    g.SetFont("s10", "Segoe UI")
    g.OnEvent("Close", (*) => CloseSettings())
    g.OnEvent("Escape", (*) => CloseSettings())

    g.Add("GroupBox", "x10 y10 w460 h185", "כללי")
    g.Add("Text", "x25 y40 w170", "קיצור מקלדת:")
    g.Add("Hotkey", "x200 y36 w250 vHk", CfgHotkey)
    g.Add("Text", "x25 y75 w170", "בלי טקסט מסומן, המר את:")
    g.Add("DropDownList", "x200 y71 w250 vNoSel Choose" (CfgNoSel = "word" ? 2 : 1),
        ["השורה עד הסמן", "המילה האחרונה"])
    g.Add("Text", "x25 y110 w170", "פריסת אנגלית:")
    g.Add("DropDownList", "x200 y106 w250 vEnK Choose" (CfgEnKLID = "00000809" ? 2 : 1),
        ["English (US)", "English (UK)"])
    g.Add("Checkbox", "x25 y150 w420 vStartup" (FileExist(A_Startup "\ReverseLang.lnk") ? " Checked" : ""),
        "הפעלה אוטומטית עם Windows")

    g.Add("GroupBox", "x10 y205 w460 h200", "המרה אוטומטית תוך כדי הקלדה")
    g.Add("Checkbox", "x25 y232 w420 vAuto" (CfgAuto ? " Checked" : ""), "פעיל")
    g.Add("Text", "x25 y265 w170", "אורך מילה מינימלי:")
    g.Add("Edit", "x200 y261 w60 Number vMinLen")
    g.Add("UpDown", "Range2-10", CfgMinLen)
    g.Add("Text", "x25 y298 w420", "מילים שלא יומרו אף פעם (מילה בשורה):")
    exc := FileExist(A_ScriptDir "\exceptions.txt") ? FileRead(A_ScriptDir "\exceptions.txt", "UTF-8") : ""
    g.Add("Edit", "x25 y322 w430 h70 Multi vExc", exc)

    g.Add("GroupBox", "x10 y415 w460 h220", "המרות אחרונות")
    lv := g.Add("ListView", "x25 y440 w430 h150 vHist -Multi", ["שעה", "מקור", "אחרי המרה"])
    g.Add("Button", "x25 y598 w210", "העתק את המקור").OnEvent("Click", (*) => CopyHist("src"))
    g.Add("Button", "x245 y598 w210", "העתק את ההמרה").OnEvent("Click", (*) => CopyHist("dst"))

    g.Add("Button", "x250 y650 w105 Default", "שמור").OnEvent("Click", (*) => SaveFromGui())
    g.Add("Button", "x365 y650 w105", "ביטול").OnEvent("Click", (*) => CloseSettings())
    SetGui := g
    FillHistory()
    g.Show("w480 h695")
}

FillHistory() {
    lv := SetGui["Hist"]
    lv.Delete()
    for h in History
        lv.Add(, h.t, h.src, h.dst)
    lv.ModifyCol(1, 50), lv.ModifyCol(2, 185), lv.ModifyCol(3, 185)
}

CopyHist(field) {
    row := SetGui["Hist"].GetNext()
    if row
        A_Clipboard := History[row].%field%
}

CloseSettings() {
    global SetGui
    SetGui.Destroy()
    SetGui := ""
}

SaveFromGui() {
    global CfgHotkey, CfgAuto, CfgMinLen, CfgNoSel, CfgEnKLID, Except
    v := SetGui.Submit(false)
    newHk := v.Hk
    if (newHk = "") {
        MsgBox "צריך לבחור קיצור מקלדת", "ReverseLang", 48
        return
    }
    if (newHk != CfgHotkey) {
        try {
            Hotkey(newHk, FixSelection, "On")
        } catch {
            MsgBox "הקיצור הזה לא תקין", "ReverseLang", 48
            return
        }
        try Hotkey(CfgHotkey, "Off")
        CfgHotkey := newHk
    }
    CfgNoSel  := v.NoSel = 2 ? "word" : "line"
    CfgEnKLID := v.EnK = 2 ? "00000809" : "00000409"
    CfgMinLen := Integer(v.MinLen = "" ? 3 : v.MinLen)
    if (v.Auto != CfgAuto) {
        CfgAuto := v.Auto
        CfgAuto ? StartAuto() : StopAuto()
        CfgAuto ? A_TrayMenu.Check("המרה אוטומטית תוך כדי הקלדה")
                : A_TrayMenu.Uncheck("המרה אוטומטית תוך כדי הקלדה")
    }
    lnk := A_Startup "\ReverseLang.lnk"
    if (v.Startup != !!FileExist(lnk))
        ToggleStartup("הפעלה עם Windows")
    p := A_ScriptDir "\exceptions.txt"
    try FileDelete p
    FileAppend v.Exc, p, "UTF-8"
    Except := LoadDict(p)
    SaveSettings()
    A_IconTip := "ReverseLang - " HotkeyLabel(CfgHotkey)
    CloseSettings()
    ToolTip "נשמר. קיצור: " HotkeyLabel(CfgHotkey)
    SetTimer () => ToolTip(), -2000
}
