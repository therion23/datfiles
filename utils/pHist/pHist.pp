Program PalmHistorian;

{$H+}

Uses
  DOS,
  Math,

// Comment this out if you have no use for it

{$DEFINE SQLITE}

{$IFDEF WIN32}
  Windows,
{$ENDIF}
{$IFDEF LINUX}
  Unix,
{$ENDIF}
{$IFDEF DARWIN}
  Unix,
{$ENDIF}

  SysUtils,
  StrUtils,
  DateUtils,

(* Do not worry if the SQLite stuff makes no sense
   I could say "for internal use only", but that would be a lie
   In fact, i only have half a clue what to use it for, but i bet you there was a reason i added it
   You tell me *)

{$IFDEF SQLITE}
  SQLite3,
{$ENDIF}

  CRC,
  MD5,
  SHA1;

Const

(* Offset between Palm timestamps and UNIX timestamps, in seconds *)
(* 66 years of 365 days plus 17 leap days, with 86'400 seconds in each *)
(* Theoretically meaning the Palm will outlive 32 bit UNIX with four years *)

  timeOffset: DWord = 2082844886;

  dumpAlerts: Boolean = False;
  dumpForms: Boolean = False;
  dumpInfo: Boolean = False;
  dumpResTable: Boolean = False;
  dumpSQL: Boolean = False;
  dumpStrings: Boolean = False;
  dumpStringTables: Boolean = False;
  dumpTraps: Boolean = False;
  addToSQL: Boolean = False;
  renameFile: Boolean = False;

{$INCLUDE pHist.Traps.inc}

Type

(* Resource entry *)
(* No, "p" is not for "pointer", you dipshit *)

  pResRec = Record
    pResName: String[4];
    pResID: Word;
    pResOffset: DWord;
  End;

(* tFRM entry *)

  pFrmRec = Record
    pFrmID: Word;
    pFrmOffset: DWord;
  End;

Var

(* Absolute swinery to allocate a whole two and a half Kilobytes! *)

//  pResTable: Array[0..255] of pResRec;

(* Which, bizarrely, wasn't enough *)

  pResTable: Array[0..65535] of pResRec;

(* Would not surprise me if some joker out there would make this necessary *)

  pFrmTable: Array[0..10239] of pFrmRec;

(* PRC and PDB files have similar headers *)
(* With bonus added confusion since String's are 1-based *)

  pHeader: Array[0..77] of Byte;

  pName: String[32];
  pCategory: String;
  pFlags: Word;
  pVersion: Word;
  pCreate,
  pModify,
  pBackup: DWord;
  pModNum,
  pAppInfo,
  pSortInfo: DWord;
  pType,
  pID: String[4];
  pUniqueSeed,
  pNextList: DWord;
  pNumRecords: Word;

(* And they can damn well share the same file handle too *)

  pFile: File;
  pFileSize: DWord;

  pFileName: String;
  IOErr: Word;

  pVer: String;

  frmType: Word;
  frmPointer: DWord;

  DB: PSQLite3;
  DBPath: String;
  SQL: AnsiString;

  SQLresult: Integer;

(* So let's be pigs! *)

  scanBuf: Array[0..65535] Of Byte;
  scanBufSize,
  scanPointer,
  scanValue,
  scanCounter,
  dispatchValue: Word;

  Libraries,
  FRequests: AnsiString;
  Identifier: String[4];

(* Half of these could be boolean's, but why bother
   The bird bird bird is the word *)

  ARMC,
  TapWave,
  Clie,
  HandEra,
  Dana,
  Lib,
  Feature,
  ExtLib,
  MaxTrap10,
  MaxTrap20,
  MaxTrap30,
  MaxTrap31,
  MaxTrap32,
  MaxTrap35,
  MaxTrap40,
  MaxTrap50: Word;

(* Standard fare - if you don't hit it, it won't fall! *)

Procedure Err(ErrCode: Word);
Begin
  Case ErrCode Of
    0: Begin
      WriteLn('Usage : pHist command filename');
      WriteLn('Help  : pHist helpme');
    End;
    1: Begin
      WriteLn('pHist rev 2025-10-29, Copyright (c) 2019-today, Nocturnal Productions');
      WriteLn;
      WriteLn('Usage   : pHist command filename');
      WriteLn;
      WriteLn('  Command can be exactly one of (a)lerts, (f)orms, (i)nfo, (r)esources,');
      WriteLn('  (s)trings, string(l)ists, (t)raps or (x) for everything');
      WriteLn;
      WriteLn('Example : pHist i QuickBits.prc');
{$IFDEF SQLITE}
      WriteLn('Notes   : Uppercase the command to log to SQL (experimental)');
{$ENDIF}
    End;
    2: WriteLn('Open error');
    3: WriteLn('Read error');
    4: WriteLn('Seek error');
    5: WriteLn('File not found');
    6: WriteLn('Rename error ', IOErr);
    101: WriteLn('SQL open error');
    102: WriteLn('SQL execute error');
  End;
  Halt(ErrCode);
End;

(* Cut and paste still beats AI *)

Function CrcFile (filename: String): DWord;
Var
  crcvalue: DWord;
  f: File;
  NumRead: Word;
  buf: Array[1..32768] of byte;
Begin
  crcvalue := crc32(0, nil, 0);
  Assign (f, filename);
  Reset (f, 1);
  Repeat
    BlockRead (f, buf, Sizeof(buf), NumRead);
    crcvalue := crc32(crcvalue, @buf[1], NumRead);
  Until (NumRead=0);
  Close (f);
  CrcFile := crcvalue;
End;

(* Ten Little Endians .. sorry, i had to .. *)
(* Probably a smarter way of doing this *)

Function GetWord (a: Array of Byte; w: Word): Word;
Begin
  GetWord := (a[w] SHL 8) + a[w + 1];
End;

Function GetLong (a: Array Of Byte; w: Word): DWord;
Begin
  GetLong := (a[w] SHL 24) + (a[w + 1] SHL 16) + (a[w + 2] SHL 8) + a[w + 3];
End;

Function GetString(a: Array Of Byte; w: Word): String;
Begin
  GetString := '';
  While a[w] <> 0 Do Begin
    If a[w] = 13 Then GetString := GetString + LineEnding Else GetString := GetString + Chr(a[w]);
    Inc(w);
  End;
  If Pos(LineEnding, GetString) > 0 Then GetString := LineEnding + GetString;
End;

(* The question is, what is a mah na mah na? *)

Procedure ParseParam(pc: Char);
Begin
  If pc = UpCase(pc) Then addToSQL := True;
  pc := UpCase(pc);
  If Pos(pc, 'AX') > 0 Then dumpAlerts := True;
  If Pos(pc, 'FX') > 0 Then dumpForms := True;
  If Pos(pc, 'IX') > 0 Then dumpInfo := True;
  If Pos(pc, 'RX') > 0 Then dumpResTable := True;
  If Pos(pc, 'EX') > 0 Then dumpSQL := True;
  If Pos(pc, 'SX') > 0 Then dumpStrings := True;
  If Pos(pc, 'LX') > 0 Then dumpStringTables := True;
  If Pos(pc, 'TX') > 0 Then dumpTraps := True;
  If Pos(pc, 'NX') > 0 Then renameFile := True;
End;

(* No, the question is, who cares? *)

Function DumpString(Offset, Size: DWord): String;
Var
  c: Word;
Begin
  DumpString := '';
  Seek(pFile, Offset);
  If (IOresult <> 0) Then Err(4);
  BlockRead(pFile, scanBuf[0], Size);
  If (IOresult <> 0) Then Err(3);
  For c := 0 To (Size - 1) Do If scanBuf[c] = 0 Then scanBuf[c] := 10;
  For c := 0 To (Size - 1) Do DumpString := DumpString + Chr(scanBuf[c]);
End;

(* I give you my heart, i give you my heart - but not in ASCII *)

Function Validate(s: String): Boolean;
Var
  c: Word;
Begin
  Validate := True;
  For c := 1 To Length(s) Do If UpCase(s[c]) = LowerCase(s[c]) Then Validate := False;
End;

(* Lights, camera .. wait, hold it! *)

Var
  i,
  j,
  Size: Word;
  c: Char;
  s,
  NewDir,
  OldDir: AnsiString;
  listString: String;
  listCounter: Word;
  listPointer: DWord;

(* Fuck the fuckers *)
{$I-}
(* End of fucking *)

Begin
  If ParamStr(1) = 'helpme' Then Err(1);
  If ParamCount <> 2 Then Err(0);
  If Length(ParamStr(1)) <> 1 Then Err(0) Else ParseParam(ParamStr(1)[1]);
  If Not FileExists(ParamStr(2)) Then Err(5);
  FileMode := 0;
  Assign(pFile, ParamStr(2));
  Reset(pFile, 1);
  If (IOresult <> 0) Then Err(2);

  pFileSize := FileSize(pFile);

  BlockRead(pFile, pHeader[0], 78);
  If (IOresult <> 0) Then Err(3);

(* Let's make some sense out of this data *)
(* All of this is purely cosmetic, so i can still figure it out 5 minutes from now *)

  ARMC := 0;
  TapWave := 0;
  Clie := 0;
  HandEra := 0;
  Dana := 0;
  Lib := 0;
  Feature := 0;
  Libraries := '';
  FRequests := '';

(* Head for sale, body not much so .. *)

  For i := 0 To 31 do pName[i + 1] := Chr(pHeader[i]);
  pFlags := GetWord(pHeader, 32);
  pVersion := GetWord(pHeader, 34);
  pCreate := GetLong(pHeader, 36);
  pModify := GetLong(pHeader, 40);
  pBackup := GetLong(pHeader, 44);
  pModNum := GetLong(pHeader, 48);
  pAppInfo := GetLong(pHeader, 52);
  pSortInfo := GetLong(pHeader, 56);
  For i := 1 to 4 do pType[i] := Chr(pHeader[i + 59]);
  For i := 1 to 4 do pID[i] := Chr(pHeader[i + 63]);
  pUniqueSeed := GetLong(pHeader, 68);
  pNextList := GetLong(pHeader, 72);
  pNumRecords := GetWord(pHeader, 76);

  SetLength(pName, 32);
  SetLength(pType, 4);
  SetLength(pID, 4);

(* On with the show *)

  For i := 1 To pNumRecords do Begin
    BlockRead(pFile, pResTable[i].pResName[1], 4);
    If (IOresult <> 0) Then Err(3);
    SetLength(pResTable[i].pResName, 4);
	If pResTable[i].pResName = 'sKst' Then HandEra := 1;
	If pResTable[i].pResName = 'wTap' Then Dana := 1;
    BlockRead(pFile, pHeader[0], 6);
    If (IOresult <> 0) Then Err(3);
    pResTable[i].pResID := GetWord(pHeader, 0);
    pResTable[i].pResOffset := GetLong(pHeader, 2);
    If dumpResTable Then WriteLn('Resource      : ', pResTable[i].pResName, ' at offset 0x', IntToHex(pResTable[i].pResOffset, 8));
  End;

(* Insert Dalek joke here *)

  If dumpAlerts Then For i := 1 To pNumRecords Do If pResTable[i].pResName = 'Talt' Then Begin
    If i = pNumRecords Then Size := (pFileSize - pResTable[i].pResOffset)
    Else Size := (pResTable[i + 1].pResOffset - pResTable[i].pResOffset);
    WriteLn('Talt 0x', IntToHex(pResTable[i].pResOffset, 8), ' size 0x', IntToHex(Size, 4));
    Write(DumpString(pResTable[i].pResOffset + 8, Size - 8));
  End;

  If dumpStrings Then For i := 1 To pNumRecords Do If pResTable[i].pResName = 'tSTR' Then Begin
    If i = pNumRecords Then Size := (pFileSize - pResTable[i].pResOffset)
      Else Size := (pResTable[i + 1].pResOffset - pResTable[i].pResOffset);
    WriteLn('tSTR 0x', IntToHex(pResTable[i].pResOffset, 8), ' size 0x', IntToHex(Size, 4));
    Write(DumpString(pResTable[i].pResOffset, Size));
  End;

(* Cable, able, Mabel, fable? *)

  If dumpStringTables Then For i := 1 To pNumRecords Do If pResTable[i].pResName = 'tSTL' Then Begin
    If i = pNumRecords Then Size := (pFileSize - pResTable[i].pResOffset)
      Else Size := (pResTable[i + 1].pResOffset - pResTable[i].pResOffset);
    WriteLn('tSTL 0x', IntToHex(pResTable[i].pResOffset, 8), ' size 0x', IntToHex(Size, 4));
    Write(DumpString(pResTable[i].pResOffset + 2, Size - 2));
  End;

// Highly incomplete, visibility low, return to base

  If dumpForms Then For i := 1 To pNumRecords Do If pResTable[i].pResName = 'tFRM' Then Begin
    Seek(pFile, pResTable[i].pResOffset);
    If (IOresult <> 0) Then Err(4);
    If i = pNumRecords Then scanBufSize := FileSize(pFile) - FilePos(pFile)
      Else scanBufSize := pResTable[i + 1].pResOffset - FilePos(pFile);
    BlockRead(pFile, scanBuf[0], scanBufSize);
    If (IOresult <> 0) Then Err(3);
    scanPointer := 62;
    scanValue := GetWord(scanBuf, scanPointer);
    Inc(scanPointer, 6);
    WriteLn('Form with ID 0x', IntToHex(GetWord(scanBuf, 40), 4), ' at 0x', IntToHex(pResTable[i].pResOffset, 8));
    For scanCounter := 0 To (scanValue - 1) Do Begin
      pFrmTable[scanCounter].pFrmID := GetWord(scanBuf, scanPointer);
      Inc(scanPointer, 2);
      pFrmTable[scanCounter].pFrmOffset := GetLong(scanBuf, scanPointer);
      Inc(scanPointer, 4);
      Write('  0x', IntToHex(pFrmTable[scanCounter].pFrmOffset, 4),': ');
      Case pFrmTable[scanCounter].pFrmID Of
        $0000: WriteLn('Field');
        $0100: Begin
          Case GetWord(scanBuf, pFrmTable[scanCounter].pFrmOffset + 16) Of
// TODO: Add fix for graphical buttons
            $0000: WriteLn('Button: ', GetString(scanBuf, pFrmTable[scanCounter].pFrmOffset + 20));
            $0100: WriteLn('PushButton');
            $0200: WriteLn('Checkbox: ', GetString(scanBuf, pFrmTable[scanCounter].pFrmOffset + 20));
            $0300: WriteLn('PopupTrigger');
            $0400: WriteLn('SelectorTrigger');
            $0500: WriteLn('RepeatingButton');
            $0600: WriteLn('Slider');
            $0700: WriteLn('FeedbackSlider');
          Else WriteLn('Unknown Control');
          End;
        End;
        $0200: Begin
          WriteLn('List: ');
          listPointer := pFrmTable[scanCounter].pFrmOffset + 16;
          listCounter := GetWord(scanBuf, listPointer);
          Inc(listPointer, 16 + (listCounter * 4));
          While listCounter > 0 Do Begin
            listString := GetString(scanBuf, listPointer);
            WriteLn('  - ', listString);
            Inc(listPointer, Length(listString) + 1);
            Dec(listCounter);
          End;
        End;
        $0300: WriteLn('Table');
        $0400: WriteLn('Bitmap');
        $0500: WriteLn('Line');
        $0600: WriteLn('Frame');
        $0700: WriteLn('Rectangle');
        $0800: WriteLn('Label: ', GetString(scanBuf, pFrmTable[scanCounter].pFrmOffset + 14));
        $0900: WriteLn('Title: ', GetString(scanBuf, pFrmTable[scanCounter].pFrmOffset + 12));
        $0A00: WriteLn('Popup');
        $0B00: WriteLn('GraffitiState');
        $0C00: WriteLn('Gadget');
        $0D00: WriteLn('ScrollBar');
      Else WriteLn(IntToHex(pFrmTable[scanCounter].pFrmID, 4));
      End;
    End;
  End;

// Totally forgot what this and the next are
// Scratch that, i know what the second is for

  For i := 1 to pNumRecords do If pResTable[i].pResName = 'taic' Then Begin
    pCategory := '';
    Seek(pFile, pResTable[i].pResOffset);
    If (IOresult <> 0) Then Err(4);
    Repeat
      BlockRead(pFile, c, 1);
      If (IOresult <> 0) Then Err(3);
      pCategory := pCategory + c;
    Until c = #0;
    Delete(pCategory, Length(pCategory), 1);
  End;

  For i := 1 to pNumRecords do If pResTable[i].pResName = 'tver' Then Begin
    Seek(pFile, pResTable[i].pResOffset);
    If (IOresult <> 0) Then Err(4);
    pVer := '';
    Repeat
      BlockRead(pFile, c, 1);
      If (IOresult <> 0) Then Err(3);
      If c <> #0 Then pVer := pVer + c;
    Until c = #0;
  End;

// The Covenant, The Sword And The ARM Of The Lord

  If (pType = 'appl') Or (pType = 'libr') Then For i := 1 to pNumRecords do If LowerCase(pResTable[i].pResName) = 'armc' Then Inc(ARMC);

  MaxTrap10 := 0;
  MaxTrap20 := 0;
  MaxTrap30 := 0;
  MaxTrap31 := 0;
  MaxTrap32 := 0;
  MaxTrap35 := 0;
  MaxTrap40 := 0;
  MaxTrap50 := 0;

(* GO MOTHERFUCKER GO! *)

  If (pType = 'appl') Or (pType = 'libr') Then For i := 1 to pNumRecords do If (pResTable[i].pResName = 'code') Or (pResTable[i].pResName = 'libr') Then Begin
    Seek(pFile, pResTable[i].pResOffset);
    If (IOresult <> 0) Then Err(4);
    If i = pNumRecords Then scanBufSize := FileSize(pFile) - FilePos(pFile)
      Else scanBufSize := pResTable[i + 1].pResOffset - FilePos(pFile);
    BlockRead(pFile, scanBuf[0], scanBufSize);
    If (IOresult <> 0) Then Err(3);
    scanPointer := 0;

// I know the following is shoddy as a shovelful of manure, but for now, it works

    Repeat
      scanValue := GetWord(scanBuf, scanPointer);
      Inc(scanPointer, 2);
	  If scanValue = $2F3C Then Begin
	    Identifier := '';
	    For j := 0 To 3 Do Identifier := Identifier + Chr(scanBuf[scanPointer + j]);
		If Identifier = 'libr' Then Begin
		  Identifier := '';
		  For j := 6 DownTo 3 Do Identifier := Identifier + Chr(scanBuf[scanPointer - j]);
		  Lib := 1;
		  If (Identifier <> 'libr') And (Pos(Identifier, Libraries) = 0) And (Validate(Identifier)) Then Libraries := Libraries + ' ' + Identifier;
		End;
		If (Clie = 0) And (Pos(Identifier, 'SoNySsYsSlHrSlMaSlRmSlScSlIrpcmRSlSdSnJp') MOD 4 = 1) Then Clie := 2;
		If (Clie < 3) And (Pos(Identifier, 'SlSi') MOD 4 = 1) Then Clie := 3;
		If (Clie < 5) And (Pos(Identifier, 'SeSySeRmSeIRSeSiSeSdSlJuSlCpSlMMSlMUSlMISlPrSlVo') MOD 4 = 1) Then Clie := 5;
		If (Clie < 5) And (Pos(Identifier, 'SlkwaSkwStawaStwSkAiSknGStrG') MOD 4 = 1) Then Clie := 5;
	  End;

(* Yeah, let us trap the TRAPs
   The funky shit about $A443 is all about catching anything "TapWave enhanced"
   And really, parsing TRAPs is the whole magick against manual labour *)

      If scanValue = $4E4F Then Begin
        scanValue := GetWord(scanBuf, scanPointer);
        Inc(scanPointer, 2);
        If (scanValue >= $A000) Then Begin
          If (InRange(scanValue, $A000, $A2B5)) AND (scanValue > MaxTrap10) Then MaxTrap10 := scanValue;
          If (InRange(scanValue, $A2B6, $A306)) AND (scanValue > MaxTrap20) Then MaxTrap20 := scanValue;
          If (InRange(scanValue, $A307, $A349)) AND (scanValue > MaxTrap30) Then MaxTrap30 := scanValue;
          If (InRange(scanValue, $A34A, $A35D)) AND (scanValue > MaxTrap31) Then MaxTrap31 := scanValue;
          If (InRange(scanValue, $A35E, $A371)) AND (scanValue > MaxTrap32) Then MaxTrap32 := scanValue;
          If (InRange(scanValue, $A370, $A3EB)) AND (scanValue > MaxTrap35) Then MaxTrap35 := scanValue;
          If (InRange(scanValue, $A3EA, $A459)) AND (scanValue > MaxTrap40) Then MaxTrap40 := scanValue;
          If (InRange(scanValue, $A45A, $A477)) AND (scanValue > MaxTrap50) Then MaxTrap50 := scanValue;
          If InRange(scanValue, $A800, $A8FF) Then ExtLib := scanValue;
    	  If scanValue = $A27B Then Begin
	        Identifier := '';
            For j := 8 DownTo 5 Do Identifier := Identifier + Chr(scanBuf[scanPointer - j]);
            Feature := 1;
	        If (Pos(Identifier, FRequests) = 0) And (Validate(Identifier)) Then FRequests := FRequests + ' ' + Identifier;
	      End;
          If ScanValue = $A443 Then Begin
            dispatchValue := (scanBuf[scanPointer - 8] SHL 8) + scanBuf[scanPointer - 7];
            If dispatchValue = $343C Then Begin
              dispatchValue := (scanBuf[scanPointer - 6] SHL 8) + scanBuf[scanPointer - 5];
              If (dispatchValue >= $0100) AND (dispatchValue < $01D7) Then TapWave := dispatchValue;
            End;
          End;
          If dumpTraps Then WriteLn('Trap 0x', IntToHex(scanValue, 4), ' : ', Traps[scanValue]);
        End;
      End;
    Until scanPointer >= scanBufSize;
  End;

  Close(pFile);

(* Experimental quick hack *)
  If pCreate > timeOffset Then pCreate := pCreate - timeOffset;
  If pModify > timeOffset Then pModify := pModify - timeOffset;
  If pBackup > timeOffset Then pBackup := pBackup - timeOffset;
(* End of hack *)

  If Length(Libraries) > 0 Then Delete(Libraries, 1, 1);
  If Length(FRequests) > 0 Then Delete(FRequests, 1, 1);

(* Sharing is caring *)

  If dumpInfo Then Begin
    If (pType = 'appl') Or (pType = 'libr') Then Begin
      Write('Application   : ');
      i := 1;
      While (pName[i] <> #0) and (i < 32) Do Begin
        Write(pName[i]);
        Inc(i);
      End;
      WriteLn;
      If (pVer <> '') Then WriteLn('Version       : ' + pVer);
    End
    Else WriteLn('Database Type : ' + pType);

    If pCategory <> '' Then WriteLn('Category      : ' + pCategory);

    WriteLn('Owner ID      : ' + pID);
    If Length(Libraries) > 0 Then WriteLn('Libraries     : ' + Libraries);
    If Length(FRequests) > 0 Then WriteLn('Feature Reqs  : ' + FRequests);
    Write('Flags         : ', IntToBin(pFlags, 16, 4));
    s := ')';
    If pFlags AND $8000 = $8000 Then s := ' Open' + s;
    If pFlags AND $0800 = $0800 Then s := ' Bundle' + s;
    If pFlags AND $0400 = $0400 Then s := ' Recyclable' + s;
    If pFlags AND $0200 = $0200 Then s := ' LaunchableData' + s;
    If pFlags AND $0100 = $0100 Then s := ' Hidden' + s;
    If pFlags AND $0080 = $0080 Then s := ' Stream' + s;
    If pFlags AND $0040 = $0040 Then s := ' CopyPrevention' + s;
    If pFlags AND $0020 = $0020 Then s := ' ResetAfterInstall' + s;
    If pFlags AND $0010 = $0010 Then s := ' OKToInstallNewer' + s;
    If pFlags AND $0008 = $0008 Then s := ' Backup' + s;
    If pFlags AND $0004 = $0004 Then s := ' AppInfoDirty' + s;
    If pFlags AND $0002 = $0002 Then s := ' ReadOnly' + s;
    If pFlags AND $0001 = $0001 Then s := ' ResDB' + s;
    If s[1] = ' ' Then Delete(s, 1, 1);
    s := ' (' + s;
    WriteLn (s);

    WriteLn('Records       : ' + IntToStr(pNumRecords));
    WriteLn('Max API calls : 1.0: 0x', IntToHex(MaxTrap10, 4) + ', 2.0: 0x', IntToHex(MaxTrap20, 4) + ', 3.0: 0x', IntToHex(MaxTrap30, 4) + ', 3.1: 0x', IntToHex(MaxTrap31, 4) + ', 3.2: 0x', IntToHex(MaxTrap32, 4) + ', 3.5: 0x', IntToHex(MaxTrap35, 4) + ', 4.0: 0x', IntToHex(MaxTrap40, 4) + ', 5.0: 0x', IntToHex(MaxTrap50, 4));
    If ARMC > 0 Then WriteLn('ARM code      : Yes');
    If TapWave > 0 Then WriteLn('Tapwave code  : Yes');
	If (Lib > 0) And (Clie > 0) Then WriteLn('Sony Clie SDK : ', Clie);
    If HandEra > 0 Then WriteLn('HandEra QVGA  : Yes');
    If ExtLib > 0 Then WriteLn('External lib  : Yes');
    If MaxTrap35 > $A3E8 Then WriteLn('Has Colour    : Yes');

    DateTimeToString(s, '"Created       : "yyyy/mm/dd" at "hh:mm:ss', UnixToDateTime(pCreate));
    WriteLn(s);
    DateTimeToString(s, '"Modified      : "yyyy/mm/dd" at "hh:mm:ss', UnixToDateTime(pModify));
    If pCreate <> pModify Then WriteLn(s) Else WriteLn('Modified      : Never');
    DateTimeToString(s, '"Backed up     : "yyyy/mm/dd" at "hh:mm:ss', UnixToDateTime(pBackup));
    If pBackup <> 0 Then WriteLn(s) Else WriteLn('Backed up     : Never');
  End;

(* Sorry, compadres, the next section makes sense to about three people on this planet
   Me, myself and i
   I had this brilliant idea about what it could be used for - and forgot it *)

{$IFDEF SQLITE}

  DBPath := ParamStr(0) + '.sqlite3';
  If (addToSQL) AND (FileExists(DBPath)) Then Begin
    If sqlite3_open(PChar(DBPath), DB) <> SQLITE_OK Then Err(101);
    SQL := 'INSERT INTO PRC VALUES ("' + ExtractFileName(ParamStr(2)) + '", "';
    s := ExtractFileDir(ParamStr(2)) + DirectorySeparator;
//    if s[1] <> DirectorySeparator Then s := GetCurrentDir + DirectorySeparator + s;
    If s[1] <> DirectorySeparator Then Begin
      s := GetCurrentDir + DirectorySeparator + s;
      OldDir := GetCurrentDir;
      SetCurrentDir(s);
      NewDir := GetCurrentDir;
      SetCurrentDir(OldDir);
    End
    Else NewDir := GetCurrentDir;
    SQL := SQL + NewDir + '", ' + IntToStr(pFileSize) + ', "';
    i := 1;
    While (pName[i] <> #0) and (i < 32) Do Begin
      SQL := SQL + pName[i];
      Inc(i);
    End;
    SQL := SQL + '", "' + pVer + '", ' + IntToStr(pFlags) + ', ' + IntToStr(pVersion) + ', "';
    DateTimeToString(s, 'yyyy-mm-dd hh:mm:ss', UnixToDateTime(pCreate));
    SQL := SQL + s + '", "';
    DateTimeToString(s, 'yyyy-mm-dd hh:mm:ss', UnixToDateTime(pModify));
    SQL := SQL + s + '", "';
    DateTimeToString(s, 'yyyy-mm-dd hh:mm:ss', UnixToDateTime(pBackup));
    SQL := SQL + s + '", ';
    SQL := SQL + IntToStr(pModNum) + ', ';
    SQL := SQL + '"' + pType + '", "' + pID + '", "' + Libraries + '", "' + FRequests + '", ';
    SQL := SQL + '"' + IntToHex(CrcFile(ParamStr(2)), 8) + '", ';
    SQL := SQL + '"' + MD5Print(MD5File(ParamStr(2))) + '", ';
    SQL := SQL + '"' + SHA1Print(SHA1File(ParamStr(2))) + '", ';
    SQL := SQL + '"0x' + IntToHex(MaxTrap10, 4) + '", "0x' + IntToHex(MaxTrap20, 4) + '", ';
    SQL := SQL + '"0x' + IntToHex(MaxTrap30, 4) + '", "0x' + IntToHex(MaxTrap31, 4) + '", ';
    SQL := SQL + '"0x' + IntToHex(MaxTrap32, 4) + '", "0x' + IntToHex(MaxTrap35, 4) + '", ';
    SQL := SQL + '"0x' + IntToHex(MaxTrap40, 4) + '", "0x' + IntToHex(MaxTrap50, 4) + '", ';
    SQL := SQL + IntToStr(ARMC) + ', ' + IntToStr(Tapwave) + ', ' + IntToStr(Clie) + ', ' + 
	             IntToStr(HandEra) + ', ' + IntToStr(Dana) + ');';

    If dumpSQL Then WriteLn(SQL);
    SQLResult := sqlite3_exec(DB, PChar(SQL), NIL, NIL, NIL);
    If SQLResult <> SQLITE_OK Then Begin
      Err(102);
    End;
    sqlite3_close(DB);
  End;

{$ENDIF}

// Feature, not a bug

  If (renameFile) and ((pType = 'appl') Or (pType = 'libr')) Then Begin
    pFileName := ExtractFilePath(ParamStr(2));
    i := 1;
    While (pName[i] <> #0) and (i < 32) Do Begin
      pFileName := pFileName + pName[i];
      Inc(i);
    End;
	While Pos(' ', pFileName) = 1 Do Delete(pFileName, 1, 1);
	While Pos(' ', pFileName) = Length(pFilename) Do Delete(pFileName, Length(pFileName), 1);
    If (pVer <> '') Then pFileName := pFileName + ' v' + pVer;
    DateTimeToString(s, 'yyyy-mm-dd', UnixToDateTime(pCreate));
    pFileName := pFileName + ' (' + s + ')' + ExtractFileExt(ParamStr(2));
	For i := 1 To Length(pFileName) Do If Pos(pFileName[i], '":\/*?<>|`') > 0 Then pFileName[i] := '_';
    If Not FileExists(pFileName) Then Rename(pFile, pFileName);
    IOErr := IOresult;
    If IOErr > 0 Then Err(6);
    WriteLn(ParamStr(2), ' -> ' , pFileName);
  End;

End.
