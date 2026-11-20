#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent
SendMode "Input"
SetKeyDelay -1, -1
; ה-InputHooks (I1) מתעלמים מהקשות שהסקריפט שולח ב-SendLevel 0, כך שהן לא נספרות כהקלדה של המשתמש

; ==========================================================
;  ReverseLang - ממיר טקסט שהוקלד בשפת מקלדת לא נכונה
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
global CfgLangs    := IniRead(INI, "General", "Languages", "")   ; HKL בהקסה, מופרדים בפסיק, לפי סדר המעבר
global CfgHidden   := IniRead(INI, "General", "HiddenLanguages", "")
global CfgDebug    := IniRead(INI, "General", "Debug", "0") = "1"
global Layouts     := LoadLayouts()
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
tray.Add("Settings...", ShowSettings)
tray.Default := "Settings..."
tray.Add()
tray.Add("Auto-fix while typing", ToggleAuto)
tray.Add("Start with Windows", ToggleStartup)
tray.Add()
tray.Add("Open settings file", (*) => Run('notepad.exe "' INI '"'))
tray.Add("Open exceptions list", OpenExceptions)
tray.Add("Reload", (*) => Reload())
tray.Add()
tray.Add("Exit", (*) => ExitApp())
if CfgAuto
    tray.Check("Auto-fix while typing")
if FileExist(A_Startup "\ReverseLang.lnk")
    tray.Check("Start with Windows")

try Hotkey(CfgHotkey, FixSelection)
catch {
    MsgBox "The shortcut '" CfgHotkey "' is not valid. Check settings.ini", "ReverseLang", 48
}

global ih := "", wordBuf := "", History := [], SetGui := ""
global Last := "", KeyCount := 0, GuiOrder := []
StartKeyCounter()
if CfgAuto
    StartAuto()

ToolTip "ReverseLang is running. Shortcut: " HotkeyLabel(CfgHotkey)
SetTimer () => ToolTip(), -2500
return

; ==========================================================
;  המרה ידנית
; ==========================================================
FixSelection(*) {
    global Last, wordBuf
    ; בלי KeyWait: Send משחרר בעצמו את Ctrl/Shift שעדיין לחוצים ומחזיר אותם אחר כך
    t0 := A_TickCount
    act := ActiveLangs()
    if (act.Length < 2) {
        ShowTip("Select at least two keyboard languages in Settings")
        return
    }
    saved := ClipboardAll()

    ; לחיצה חוזרת מיד אחרי המרה: עוברים לשפה הבאה
    repeat := IsObject(Last) && A_TickCount - Last.t < 8000 && KeyCount - Last.keys <= 1
    if repeat {
        ; מוחקים את ההמרה הקודמת עם Backspace. לא מסמנים עם Shift+Left,
        ; כי בטקסט מימין לשמאל (עברית, ערבית) החץ זז קדימה ולא אחורה
        n := StrLen(Last.out)
        Send "{Backspace " n "}"
        Sleep 20
        orig := Last.orig, src := Last.src, idx := Last.idx + 1
    } else {
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
        orig := StrReplace(A_Clipboard, "`r`n", "`n")
        src := GuessSource(orig, act)
        idx := 1
    }

    ; סדר המעבר: כל השפות חוץ ממקור, ובסוף חזרה לטקסט המקורי
    targets := []
    for L in act
        if (L.id != src.id)
            targets.Push(L)
    targets.Push(src)
    if (idx > targets.Length)
        idx := 1
    tgt := targets[idx]
    out := tgt.id = src.id ? orig : ConvertLayout(orig, src, tgt)
    ; מדלגים על שפות שההמרה אליהן לא משנה כלום
    while (out == orig && tgt.id != src.id && idx < targets.Length) {
        idx++
        tgt := targets[idx]
        out := tgt.id = src.id ? orig : ConvertLayout(orig, src, tgt)
    }
    if (out == orig && !repeat) {
        A_Clipboard := saved
        ShowTip("Nothing to convert")
        return
    }

    t1 := A_TickCount
    A_Clipboard := StrReplace(out, "`n", "`r`n")
    Send "^v"
    t2 := A_TickCount
    Sleep 200
    A_Clipboard := saved
    PostLayout(tgt.hkl)

    if (idx = 1)
        AddHistory(orig, out)
    else if (History.Length) {
        History[1].dst := out
        if IsObject(SetGui)
            try FillHistory()
    }
    Last := {orig: orig, src: src, idx: idx, out: out, t: A_TickCount, keys: KeyCount}
    wordBuf := ""
    if CfgDebug
        ShowTip(tgt.name "  [prepare " (t1 - t0) " ms, paste " (t2 - t1) " ms]", 4000)
    else
        ShowTip(tgt.name)
}

; ==========================================================
;  שפות מקלדת: המיפוי נבנה מ-Windows לכל פריסה מותקנת
; ==========================================================
LoadLayouts() {
    ; רשימת שפות הקלט כפי שהיא מוגדרת ב-Windows
    list := [], seen := Map()
    Loop 30 {
        try klid := RegRead("HKCU\Keyboard Layout\Preload", String(A_Index))
        catch
            continue
        try klid := RegRead("HKCU\Keyboard Layout\Substitutes", klid)
        hkl := DllCall("LoadKeyboardLayoutW", "Str", klid, "UInt", 0x80, "Ptr")   ; KLF_NOTELLSHELL
        if !hkl
            continue
        L := BuildLayout(hkl, klid)
        if (L.c2k.Count > 20 && !seen.Has(L.id))
            list.Push(L), seen[L.id] := 1
    }
    if list.Length
        return list
    ; גיבוי: מה שטעון כרגע
    n := DllCall("GetKeyboardLayoutList", "Int", 0, "Ptr", 0, "Int")
    if (n <= 0)
        return list
    buf := Buffer(n * A_PtrSize, 0)
    DllCall("GetKeyboardLayoutList", "Int", n, "Ptr", buf, "Int")
    Loop n {
        L := BuildLayout(NumGet(buf, (A_Index - 1) * A_PtrSize, "Ptr"))
        if (L.c2k.Count > 20)
            list.Push(L)
    }
    return list
}

BuildLayout(hkl, klid := "") {
    k2c := Map(), c2k := Map()
    ks := Buffer(256, 0), zero := Buffer(256, 0), out := Buffer(32, 0)
    for shift in [0, 1] {
        DllCall("RtlZeroMemory", "Ptr", ks, "UPtr", 256)
        if shift
            NumPut("UChar", 0x80, ks, 0x10)
        vk := 0x20
        while (vk <= 0xFE) {
            sc := DllCall("MapVirtualKeyExW", "UInt", vk, "UInt", 0, "Ptr", hkl, "UInt")
            if sc {
                r := DllCall("ToUnicodeEx", "UInt", vk, "UInt", sc, "Ptr", ks, "Ptr", out, "Int", 8, "UInt", 4, "Ptr", hkl, "Int")
                if (r < 0) {
                    ; מקש מת (למשל ^ בצרפתית): מנקים את המצב
                    spc := DllCall("MapVirtualKeyExW", "UInt", 0x20, "UInt", 0, "Ptr", hkl, "UInt")
                    Loop 2
                        DllCall("ToUnicodeEx", "UInt", 0x20, "UInt", spc, "Ptr", zero, "Ptr", Buffer(32), "Int", 8, "UInt", 4, "Ptr", hkl, "Int")
                }
                if (r = 1 || r = -1) {
                    ch := Chr(NumGet(out, 0, "UShort"))
                    if (Ord(ch) >= 0x20) {
                        key := vk | (shift << 8)
                        k2c[key] := ch
                        if !c2k.Has(ch)
                            c2k[ch] := key
                    }
                }
            }
            vk++
        }
    }
    return {hkl: hkl, id: Format("{:08X}", hkl & 0xFFFFFFFF), name: LayoutName(hkl, klid), k2c: k2c, c2k: c2k}
}

LayoutName(hkl, klid := "") {
    nb := Buffer(256, 0)
    DllCall("GetLocaleInfoW", "UInt", hkl & 0xFFFF, "UInt", 0x72, "Ptr", nb, "Int", 128)   ; LOCALE_SENGLISHDISPLAYNAME
    lang := StrGet(nb, "UTF-16")
    if (klid = "")
        klid := KlidFromHkl(hkl)
    kb := ""
    try kb := RegRead("HKLM\SYSTEM\CurrentControlSet\Control\Keyboard Layouts\" klid, "Layout Text")
    if (lang = "")
        lang := Format("{:08X}", hkl & 0xFFFFFFFF)
    return kb != "" ? lang " - " kb : lang
}

KlidFromHkl(hkl) {
    hi := (hkl >> 16) & 0xFFFF
    if ((hi & 0xF000) != 0xF000)
        return Format("{:08X}", hi)
    want := Format("{:04x}", hi & 0x0FFF)
    Loop Reg, "HKLM\SYSTEM\CurrentControlSet\Control\Keyboard Layouts", "K" {
        id := ""
        try id := RegRead(A_LoopRegKey "\" A_LoopRegName, "Layout Id")
        if (id = want)
            return A_LoopRegName
    }
    return ""
}

ActiveLangs() {
    act := []
    for id in StrSplit(CfgLangs, ",", " ")
        for L in Layouts
            if (L.id = id)
                act.Push(L)
    if (act.Length < 2)
        act := Layouts.Clone()
    return act
}

GuessSource(txt, act) {
    ; השפה שבה הוקלד הטקסט, מבין כל השפות המותקנות: זו שמכסה הכי הרבה תווים.
    ; בתיקו מעדיפים את שפת המקלדת הפעילה, אחר כך שפות פעילות לפי הסדר
    tid := DllCall("GetWindowThreadProcessId", "Ptr", WinExist("A"), "Ptr", 0, "UInt")
    cur := Format("{:08X}", DllCall("GetKeyboardLayout", "UInt", tid, "Ptr") & 0xFFFFFFFF)
    cands := act.Clone()
    for L in Layouts {
        inAct := false
        for A in act
            if (A.id = L.id)
                inAct := true
        if !inAct
            cands.Push(L)
    }
    best := cands[1], bestScore := -1
    for L in cands {
        score := 0
        Loop Parse txt {
            if (A_LoopField ~= "[\s\d]")
                continue
            if L.c2k.Has(A_LoopField)
                score += 2
        }
        if (L.id = cur)
            score += 1
        if (score > bestScore)
            best := L, bestScore := score
    }
    return best
}

ConvertLayout(s, src, tgt) {
    out := ""
    Loop Parse s {
        c := A_LoopField
        if src.c2k.Has(c) {
            k := src.c2k[c]
            out .= tgt.k2c.Has(k) ? tgt.k2c[k] : c
        } else
            out .= c
    }
    return out
}

PostLayout(hkl) {
    try PostMessage 0x50, 0, hkl, , "A"
}

SetLayout(lang) {
    ; למצב האוטומטי (עברית/אנגלית)
    prim := lang = "he" ? 0x0D : 0x09
    for L in Layouts
        if ((L.hkl & 0x3FF) = prim) {
            PostLayout(L.hkl)
            return
        }
    klid := lang = "he" ? CfgHeKLID : CfgEnKLID
    PostLayout(DllCall("LoadKeyboardLayout", "Str", klid, "UInt", 1, "Ptr"))
}

StartKeyCounter() {
    kc := InputHook("V I1 L0")
    kc.KeyOpt("{All}", "N")
    kc.KeyOpt("{LCtrl}{RCtrl}{LShift}{RShift}{LAlt}{RAlt}{LWin}{RWin}", "-N")
    kc.OnKeyDown := CountKey
    kc.Start()
}

CountKey(*) {
    global KeyCount
    KeyCount += 1
}

ShowTip(msg, ms := 1000) {
    ToolTip msg
    SetTimer () => ToolTip(), -ms
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
    global wordBuf := "", Last := ""
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
    Send "{Backspace " (StrLen(w) + 1) "}"
    SendText conv " "
    SetLayout(lang)
}

; ==========================================================
;  עזרים
; ==========================================================
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
        FileAppend "# One word per line. These words are never auto-fixed`n", p, "UTF-8"
    Run 'notepad.exe "' p '"'
}

SaveSettings() {
    IniWrite CfgHotkey, INI, "General", "Hotkey"
    IniWrite CfgAuto ? "1" : "0", INI, "General", "AutoMode"
    IniWrite CfgMinLen, INI, "General", "AutoMinLength"
    IniWrite CfgNoSel, INI, "General", "NoSelection"
    IniWrite CfgEnKLID, INI, "General", "EnglishKLID"
    IniWrite CfgHeKLID, INI, "General", "HebrewKLID"
    IniWrite CfgLangs, INI, "General", "Languages"
    IniWrite CfgHidden, INI, "General", "HiddenLanguages"
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
    global SetGui, GuiOrder
    if IsObject(SetGui) {
        SetGui.Show()
        return
    }
    g := Gui("-MaximizeBox", "ReverseLang - Settings")
    g.SetFont("s10", "Segoe UI")
    g.OnEvent("Close", (*) => CloseSettings())
    g.OnEvent("Escape", (*) => CloseSettings())
    tab := g.Add("Tab3", "x10 y10 w460 h330", ["General", "Languages", "Auto-fix", "History"])

    tab.UseTab(1)
    g.Add("Text", "x30 y55 w160", "Shortcut:")
    g.Add("Hotkey", "x200 y51 w250 vHk", CfgHotkey)
    g.Add("Text", "x30 y90 w160", "With no selection, convert:")
    g.Add("DropDownList", "x200 y86 w250 vNoSel Choose" (CfgNoSel = "word" ? 2 : 1),
        ["The line up to the cursor", "The last word"])
    g.Add("Checkbox", "x30 y130 w420 vStartup" (FileExist(A_Startup "\ReverseLang.lnk") ? " Checked" : ""),
        "Start with Windows")
    g.Add("Text", "x30 y170 w420 cGray", "Press the shortcut again right after a conversion to move to the next language. After the last one you get the original text back.")

    tab.UseTab(2)
    g.Add("Text", "x30 y50 w420", "Keyboard languages installed in Windows. Tick the ones to use; the order sets the cycle order for repeated presses.")
    g.Add("ListView", "x30 y95 w300 h190 vLangs Checked -Hdr -Multi NoSortHdr", ["Language"])
    g.Add("Button", "x340 y95 w110", "Move up").OnEvent("Click", (*) => MoveLang(-1))
    g.Add("Button", "x340 y130 w110", "Move down").OnEvent("Click", (*) => MoveLang(1))
    g.Add("Button", "x340 y185 w110", "Add language...").OnEvent("Click", (*) => Run("ms-settings:regionlanguage"))
    g.Add("Button", "x340 y220 w110", "Refresh").OnEvent("Click", (*) => RefreshLangs())
    g.Add("Button", "x340 y255 w110", "Show all").OnEvent("Click", (*) => ShowAllLangs())
    g.Add("Text", "x30 y292 w420 cGray", "Refresh reloads the list from Windows and removes unticked languages. Show all brings them back.")

    tab.UseTab(3)
    g.Add("Checkbox", "x30 y55 w420 vAuto" (CfgAuto ? " Checked" : ""), "Enabled (Hebrew and English only)")
    g.Add("Text", "x30 y90 w160", "Minimum word length:")
    g.Add("Edit", "x200 y86 w60 Number vMinLen")
    g.Add("UpDown", "Range2-10", CfgMinLen)
    g.Add("Text", "x30 y125 w420", "Never auto-fix these words (one per line):")
    exc := FileExist(A_ScriptDir "\exceptions.txt") ? FileRead(A_ScriptDir "\exceptions.txt", "UTF-8") : ""
    g.Add("Edit", "x30 y150 w420 h170 Multi vExc", exc)

    tab.UseTab(4)
    g.Add("ListView", "x30 y50 w420 h230 vHist -Multi", ["Time", "Original", "Converted"])
    g.Add("Button", "x30 y290 w205", "Copy original").OnEvent("Click", (*) => CopyHist("src"))
    g.Add("Button", "x245 y290 w205", "Copy converted").OnEvent("Click", (*) => CopyHist("dst"))

    tab.UseTab()
    g.Add("Button", "x250 y350 w105 Default", "Save").OnEvent("Click", (*) => SaveFromGui())
    g.Add("Button", "x365 y350 w105", "Cancel").OnEvent("Click", (*) => CloseSettings())
    SetGui := g
    FillLangs(ActiveIds())
    FillHistory()
    g.Show("w480 h395")
}

ActiveIds() {
    ids := []
    for L in ActiveLangs()
        ids.Push(L.id)
    return ids
}

IsHidden(id) {
    for h in StrSplit(CfgHidden, ",", " ")
        if (h = id)
            return true
    return false
}

FillLangs(checkedIds) {
    global GuiOrder := []
    for id in checkedIds
        for L in Layouts
            if (L.id = id)
                GuiOrder.Push(id)
    for L in Layouts {
        found := false
        for id in GuiOrder
            if (id = L.id)
                found := true
        if (!found && !IsHidden(L.id))
            GuiOrder.Push(L.id)
    }
    lv := SetGui["Langs"]
    lv.Delete()
    for id in GuiOrder {
        name := id
        for L in Layouts
            if (L.id = id)
                name := L.name
        chk := false
        for c in checkedIds
            if (c = id)
                chk := true
        lv.Add(chk ? "Check" : "", name)
    }
    lv.ModifyCol(1, 280)
}

CheckedIds() {
    lv := SetGui["Langs"], ids := [], row := 0
    while (row := lv.GetNext(row, "C"))
        ids.Push(GuiOrder[row])
    return ids
}

MoveLang(dir) {
    lv := SetGui["Langs"]
    row := lv.GetNext()
    if !row
        return
    dst := row + dir
    if (dst < 1 || dst > GuiOrder.Length)
        return
    chk := CheckedIds()
    tmp := GuiOrder[row], GuiOrder[row] := GuiOrder[dst], GuiOrder[dst] := tmp
    ; בונים מחדש לפי הסדר החדש ושומרים סימונים
    newChecked := []
    for id in GuiOrder
        for c in chk
            if (c = id)
                newChecked.Push(id)
    order := GuiOrder.Clone()
    lv.Delete()
    for id in order {
        name := id
        for L in Layouts
            if (L.id = id)
                name := L.name
        isChk := false
        for c in newChecked
            if (c = id)
                isChk := true
        lv.Add(isChk ? "Check" : "", name)
    }
    lv.Modify(dst, "Select Focus")
}

RefreshLangs() {
    ; טוען מחדש מ-Windows ומסיר מהרשימה שפות לא מסומנות
    global Layouts, CfgHidden
    chk := CheckedIds()
    for id in GuiOrder {
        isChk := false
        for c in chk
            if (c = id)
                isChk := true
        if (!isChk && !IsHidden(id))
            CfgHidden .= (CfgHidden = "" ? "" : ",") id
    }
    known := GuiOrder.Clone()
    Layouts := LoadLayouts()
    for L in Layouts {
        isKnown := false
        for id in known
            if (id = L.id)
                isKnown := true
        if (!isKnown && !IsHidden(L.id))
            chk.Push(L.id)   ; שפה חדשה נכנסת מסומנת
    }
    FillLangs(chk)
}

ShowAllLangs() {
    global CfgHidden := ""
    FillLangs(CheckedIds())
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
    global CfgHotkey, CfgAuto, CfgMinLen, CfgNoSel, CfgLangs, Except
    v := SetGui.Submit(false)
    ids := CheckedIds()
    if (ids.Length < 2) {
        MsgBox "Tick at least two languages", "ReverseLang", 48
        return
    }
    CfgLangs := ""
    for id in ids
        CfgLangs .= (A_Index > 1 ? "," : "") id
    newHk := v.Hk
    if (newHk = "") {
        MsgBox "Choose a shortcut", "ReverseLang", 48
        return
    }
    if (newHk != CfgHotkey) {
        try {
            Hotkey(newHk, FixSelection, "On")
        } catch {
            MsgBox "That shortcut is not valid", "ReverseLang", 48
            return
        }
        try Hotkey(CfgHotkey, "Off")
        CfgHotkey := newHk
    }
    CfgNoSel  := v.NoSel = 2 ? "word" : "line"
    CfgMinLen := Integer(v.MinLen = "" ? 3 : v.MinLen)
    if (v.Auto != CfgAuto) {
        CfgAuto := v.Auto
        CfgAuto ? StartAuto() : StopAuto()
        CfgAuto ? A_TrayMenu.Check("Auto-fix while typing")
                : A_TrayMenu.Uncheck("Auto-fix while typing")
    }
    lnk := A_Startup "\ReverseLang.lnk"
    if (v.Startup != !!FileExist(lnk))
        ToggleStartup("Start with Windows")
    p := A_ScriptDir "\exceptions.txt"
    try FileDelete p
    FileAppend v.Exc, p, "UTF-8"
    Except := LoadDict(p)
    SaveSettings()
    A_IconTip := "ReverseLang - " HotkeyLabel(CfgHotkey)
    CloseSettings()
    ToolTip "Saved. Shortcut: " HotkeyLabel(CfgHotkey)
    SetTimer () => ToolTip(), -2000
}
