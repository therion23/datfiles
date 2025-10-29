Program sisname;

{$DEFINE RELEASE}

(*
** TODO:
** - Prefer English component name
** - Fixup for cases like TV Mobile (invalid Unicode)
** - Double check variables do not need resetting per loop
** - More strict size checking and get rid of trailing junk
*)

Uses
  DOS,
  CRC16,
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
  LazUTF8,
  LazFileUtils;

Const
  Countries: Array[1..98] Of String[2] = ('EN', 'FR', 'GE', 'SP', 'IT', 'SW', 'DA', 'NO', 'FI', 'AM', 'SF', 'SG', 'PO', 'TU', 'IC', 'RU', 'HU', 'DU', 'BL', 'AU', 'BG', 'AS', 'NZ', 'IF', 'CS', 'SK', 'PL', 'SL', 'TC', 'HK', 'ZH', 'JA', 'TH', 'AF', 'SQ', 'AH', 'AR', 'HY', 'TL', 'BE', 'BN', 'BG', 'MY', 'CA', 'HR', 'CE', 'IE', 'SF', 'ET', 'FA', 'CF', 'GD', 'KA', 'EL', 'CG', 'GU', 'HE', 'HI', 'IN', 'GA', 'SZ', 'KN', 'KK', 'KM', 'KO', 'LO', 'LV', 'LT', 'MK', 'MS', 'ML', 'MR', 'MO', 'MN', 'NN', 'BP', 'PA', 'RO', 'SR', 'SI', 'SO', 'OS', 'LS', 'SH', 'FS', 'XX', 'TA', 'TE', 'BO', 'TI', 'CT', 'TK', 'UK', 'UR', 'XX', 'VI', 'CY', 'ZU');

Var
  I: File;

  DirInfo: TSearchRec;
  SourcePath: String;
  FormatVer: Byte;

  CRC1,
  CRC2,
  CRC3,
  CRC4: DWord;
  Csum,
  NumLang,
  NumFiles,
  NumReqs,
  InstLang,
  InstFiles,
  InstDrive,
  NumCaps: Word;
  InstVer: DWord;
  Options,
  Type1,
  MajVer,
  MinVer: Word;
  Variants,
  LangPtr,
  FilePtr,
  ReqPtr,
  CertPtr,
  CompPtr: DWord;

  SigPtr,
  CapPtr,
  InstSpace,
  MaxSpace: DWord;

  CYear,
  CMonth,
  CDay,
  CHour,
  CMinute,
  CSecond: Word;

  NumCerts: DWord;

  Res1,
  Res2: Word;

  DRes1,
  DRes2: DWord;

  CkBuf: Array[1..32768] of Byte;
  Title: WideString;
  ETitle: String;
  OutName: String;

  CalcHdrSum: String[8];
  CalcCkSum: String[4];

Function LeadingZero(Val: Word): WideString;
Begin
  If Val < 10 Then LeadingZero := '0' + WideString(IntToStr(Val)) Else LeadingZero := WideString(IntToStr(Val));
End;

Procedure Err(ErrCode: Byte);
Begin
  WriteLn;
  Case ErrCode Of
    101: Begin
      WriteLn('Error opening file ', DirInfo.Name);
      Close(I);
      Halt(101);
    End;
    102: Begin
      WriteLn('Error reading header from ', DirInfo.Name);
      Close(I);
      Halt(102);
    End;
    103: Begin
      WriteLn('Error seeking in file ', DirInfo.Name, ' - CompPtr: ', CompPtr, ' - DRes1: ', DRes1, ' - DRes2: ', DRes2);
      FormatVer := 0;
    End;
  End;
End;

Begin
  Assign(Output, '');
  Rewrite(Output);
  SourcePath := ExtractFilePath(ParamStr(1));
  init_crcccitt_tab;
  If FindFirst(ParamStr(1), $21, DirInfo) = 0 Then Repeat
{$I-}
    IOresult;
    WriteLn(SourcePath + DirInfo.Name);
    FileMode := 0;
    Assign(I, SourcePath + DirInfo.Name);
    Reset(I, 1);
    If IOResult <> 0 Then Err(101);
    FormatVer := 0;
    If FileSize(I) >= 16 Then Begin
      Blockread(I, CRC1, 4);
      Blockread(I, CRC2, 4);
      Blockread(I, CRC3, 4);
      Blockread(I, CRC4, 4);
      If (CRC2 = $1000006D) AND (CRC3 = $10000419) Then Begin
        WriteLn('EPOC 2-5');
        FormatVer := 2;
      End
      Else If (CRC2 = $10003A12) AND (CRC3 = $10000419) Then Begin
        WriteLn('Symbian 6-9');
        FormatVer := 6;
      End
      Else If (CRC1 = $10201a7a) AND (CRC2 = $00000000) Then Begin
        WriteLn('Symbian 9.1+');
        FormatVer := 9;
      End;
    End;

    If (FormatVer = 2) OR (FormatVer = 6) Then Begin
      Blockread(I, Csum, 2);
      Blockread(I, NumLang, 2);
      Blockread(I, NumFiles, 2);
      Blockread(I, NumReqs, 2);
      Blockread(I, InstLang, 2);
      Blockread(I, InstFiles, 2);
      Blockread(I, InstDrive, 2);
      Blockread(I, NumCaps, 2);
      Blockread(I, InstVer, 4);
      Blockread(I, Options, 2);
      Blockread(I, Type1, 2);
      Blockread(I, MajVer, 2);
      Blockread(I, MinVer, 2);
      Blockread(I, Variants, 4);
      Blockread(I, LangPtr, 4);
      Blockread(I, FilePtr, 4);
      Blockread(I, ReqPtr, 4);
      Blockread(I, CertPtr, 4);
      Blockread(I, CompPtr, 4);
    End;
//    Else WriteLn('Not a SIS');

    If IOResult <> 0 Then Err(102);

    If FormatVer = 6 Then Begin
      Blockread(I, SigPtr, 4);
      Blockread(I, CapPtr, 4);
      Blockread(I, InstSpace, 4);
      Blockread(I, MaxSpace, 4);
    End
    Else If FormatVer > 0 Then Begin
      SigPtr := 0;
      CapPtr := 0;
      InstSpace := 0;
      MaxSpace := 0;
    End;

    If IOResult <> 0 Then Err(102);

    If (FormatVer = 2) OR (FormatVer = 6) Then Begin
      Write('Component offset: ', CompPtr); 
      Write(' - Component: ');
      Seek(I, CompPtr);
      BlockRead(I, DRes1, 4);
      Seek(I, FilePos(I) + ((NumLang - 1) * 4));
      BlockRead(I, DRes2, 4);
      If IOResult <> 0 Then Err(103);
      Seek(I, DRes2);
      If FormatVer = 2 Then Begin
        SetLength(ETitle, DRes1);
        BlockRead(I, ETitle[1], DRes1);
        If IOResult <> 0 Then Err(103);
        SetLength(ETitle, DRes1);
        For Res1 := 1 To Length(ETitle) Do If ETitle[Res1] < #32 Then ETitle[Res1] := #32;
        Title := ETitle;
      End
      Else Begin
        SetLength(Title, DRes1);
        BlockRead(I, Title[1], DRes1);
        If IOResult <> 0 Then Err(103);
        SetLength(Title, DRes1 DIV 2);
      End;
      WriteLn(Title, ' - Version: ', LeadingZero(MajVer), '.', LeadingZero(MinVer));
      Write('Languages: ', NumLang, ' - Inst Language: ', InstLang, ' - ');
      Write('Language offset: ', LangPtr, ' - Languages:');
      Seek(I, LangPtr);
      For Res1 := 1 to NumLang Do Begin
        BlockRead(I, Res2, 2);
        Write(' ', Countries[Res2]);
      End;
      If IOResult <> 0 Then Err(103) Else Begin
        WriteLn;
        WriteLn('Files offset: ', FilePtr, ' - Files: ', NumFiles, ' - Inst Files: ', InstFiles, ' - Inst Drive: ', InstDrive); 
        WriteLn('Inst Ver: ', InstVer, ' - Requisites: ', NumReqs, ' - Num Caps: ', NumCaps);
        Write('Type: ');
        Case Type1 Of
          0: Write('SISAPP');
          1: Write('SISSYSTEM');
          2: Write('SISOPTION');
          3: Write('SISCONFIG');
          4: Write('SISPATCH');
          5: Write('SISUPGRADE');
          Else Write('Unknown');
        End;
        Write(' - Options:');
        If (Options AND  1 =  1) Then Write(' IsUnicode');
        If (Options AND  2 =  2) Then Write(' IsDistributable');
        If (Options AND  8 =  8) Then Write(' NoCompress');
        If (Options AND 16 = 16) Then Write(' ShutdownApps');
        WriteLn;
        If Variants > 0 Then WriteLn('Variant');
        WriteLn('Requisites offset: ', ReqPtr); 
        WriteLn('Certificate offset: ', CertPtr);
      End;
    End;
    If FormatVer = 6 Then Begin
      WriteLn('Signature offset: ', SigPtr); 
      WriteLn('Capabilities offset: ', CapPtr); 
      WriteLn('Installed space: ', InstSpace); 
      WriteLn('Max installed space: ', MaxSpace); 
    End;
    If ((FormatVer = 2) OR (FormatVer = 6)) AND (CertPtr > 0) Then Begin
      Seek (I, CertPtr);
      BlockRead(I, CYear, 2);
      BlockRead(I, CMonth, 2);
      BlockRead(I, CDay, 2);
      BlockRead(I, CHour, 2);
      BlockRead(I, CMinute, 2);
      BlockRead(I, CSecond, 2);
      BlockRead(I, NumCerts, 4);
      If IOResult <> 0 Then Err(103);
      Write('Certificate date: ', CYear, '/', LeadingZero(Cmonth), '/', LeadingZero(CDay));
      If (CYear < 1980) OR (CYear > 2323) OR (CMonth = 0) OR (CMonth > 12) OR (CDay = 0) OR (CDay > 31) Then WriteLn(' (Invalid)')
      Else WriteLn;
    End;
    If FormatVer > 0 Then Begin
      Write('Header checksum: ', inttohex(CRC4), ' - Calculated: ');
      Res1 := 0;
      Res1 := update_crc_ccitt(Res1, Hi(Lo(CRC1)));
      Res1 := update_crc_ccitt(Res1, Hi(Hi(CRC1)));
      Res1 := update_crc_ccitt(Res1, Hi(Lo(CRC2)));
      Res1 := update_crc_ccitt(Res1, Hi(Hi(CRC2)));
      Res1 := update_crc_ccitt(Res1, Hi(Lo(CRC3)));
      Res1 := update_crc_ccitt(Res1, Hi(Hi(CRC3)));
      Res2 := 0;
      Res2 := update_crc_ccitt(Res2, Lo(Lo(CRC1)));
      Res2 := update_crc_ccitt(Res2, Lo(Hi(CRC1)));
      Res2 := update_crc_ccitt(Res2, Lo(Lo(CRC2)));
      Res2 := update_crc_ccitt(Res2, Lo(Hi(CRC2)));
      Res2 := update_crc_ccitt(Res2, Lo(Lo(CRC3)));
      Res2 := update_crc_ccitt(Res2, Lo(Hi(CRC3)));
      CalcHdrSum := inttohex(Res1) + inttohex(Res2);
      WriteLn(CalcHdrSum);
    End;
    If (FormatVer = 2) OR (FormatVer = 6) Then Begin
      Res1 := 0;
      DRes1 := FileSize(I);
      If SigPtr > 0 Then DRes1 := SigPtr;
      Seek(I, 0);
      BlockRead(I, CkBuf[1], 16);
      For Res2 := 1 To 16 Do Res1 := update_crc_ccitt(Res1, CkBuf[Res2]);
      Seek(I, 18);
      DRes1 := DRes1 - 18;
      While DRes1 > 0 Do Begin
        If DRes1 >= 32768 Then Begin
          BlockRead(I, CkBuf[1], 32768);
          For Res2 := 1 To 32768 Do Res1 := update_crc_ccitt(Res1, CkBuf[Res2]);
          DRes1 := DRes1 - 32768;
        End
        Else Begin
          BlockRead(I, CkBuf[1], DRes1);
          For Res2 := 1 To DRes1 Do Res1 := update_crc_ccitt(Res1, CkBuf[Res2]);
          DRes1 := 0;
        End;
      End;
      CalcCkSum := inttohex(Res1);
      WriteLn('File checksum: ', inttohex(CSum), ' - Calculated: ', CalcCkSum);
    End;
    For Res1 := 1 To NumFiles Do Begin
// To be added
    End;
    Close(I);
    If (FormatVer = 2) OR (FormatVer = 6) Then Begin
      If (CalcHdrSum = inttohex(CRC4)) AND (CalcCkSum = inttohex(CSum)) Then Begin
        If FormatVer = 2 Then OutName := 'EPOC - ' Else OutName := 'Symbian - ';
        OutName := OutName + Title + ' v' + LeadingZero(MajVer) + '.' + LeadingZero(MinVer);
        If CertPtr > 0 Then OutName := OutName + ' (' + inttostr(CYear) + ')';
        OutName := OutName + ' [' + CalcCkSum + '].sis';
        For Res1 := 1 To Length(OutName) Do If Pos(OutName[Res1], '":\/*?<>|`') > 0 Then OutName[Res1] := '_';
        WriteLn(OutName);
        If NOT FileExists(SourcePath + OutName) Then Begin
          RenameFile(SourcePath + DirInfo.Name, SourcePath + OutName);
        End
        Else WriteLn(OutName, ' already exists.');
        If IOresult <> 0 Then WriteLn('Error renaming!');
      End
      Else RenameFile(SourcePath + DirInfo.Name, SourcePath + DirInfo.Name + '.broken');
    End;
    If FormatVer = 0 Then Begin
      OutName := SourcePath + DirInfo.Name + '.notasis';
      If NOT FileExists(OutName) Then Begin
        RenameFile(SourcePath + DirInfo.Name, OutName);
      End
      Else WriteLn(OutName, ' already exists.');
      If IOresult <> 0 Then WriteLn('Error renaming!');
    End;
  Until FindNext(DirInfo) <> 0;
  FindClose(DirInfo);
End.
