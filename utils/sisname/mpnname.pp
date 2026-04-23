Program mpnname;

{$DEFINE RELEASE}

(*
** TODO:
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

  Magic: String[4];
  Heap: DWord;
  Stack: DWord;
  Flags: Word;
  Code,
  Data,
  BSS,
  Resource,
  ResDecomp: DWord;
  Pool: QWord;
  StringTable: DWord;
  Gunk1,
  Gunk2: DWord;

  Encrypted,
  Compressed,
  Valid: Boolean;

  Res1,
  Res2: Word;

  DRes1,
  DRes2: DWord;

  CkBuf: AnsiString;

  Field,
  Value,
  IMEI,
  Title,
  Vendor,
  Copyright,
  Version,
  Help: WideString;

  CertificateDate,
  ExpirationDate,
  PhoneNumber: String;

  Dummy: Byte;
  c: Char;

  Year: WideString;

  ETitle: String;
  OutName: String;

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
      WriteLn('Error seeking in ', DirInfo.Name);
      Valid := False;
    End;
    103: Begin
      WriteLn('Error reading header from ', DirInfo.Name);
      Valid := False;
    End;
    104: Begin
      WriteLn('Invalid .mrp file ', DirInfo.Name);
      Valid := False;
    End;
    105: Begin
      WriteLn('Magic value not found in ', DirInfo.Name);
      Valid := False;
    End;
    106: Begin
      WriteLn('Ambiguous header information in ', DirInfo.Name);
      Valid := False;
    End;
    107: Begin
      WriteLn('Metadata section not found in ', DirInfo.Name);
      Valid := False;
    End;
    108: Begin
      WriteLn('Metadata section possibly corrupt in ', DirInfo.Name);
      Valid := False;
    End;
  End;
End;

Procedure ClearVars;
Begin
  Field := '';
  Value := '';
  IMEI := '';
  Title := '';
  Vendor := '';
  Copyright := '';
  Version := '';
  Help := '';
  CertificateDate := '';
  ExpirationDate := '';
  PhoneNumber := '';
End;

Begin
  Assign(Output, '');
  Rewrite(Output);
  SourcePath := ExtractFilePath(ParamStr(1));
  If FindFirst(ParamStr(1), $21, DirInfo) = 0 Then Repeat
{$I-}
    IOresult;
    WriteLn(SourcePath + DirInfo.Name);
    FileMode := 0;
    Assign(I, SourcePath + DirInfo.Name);
    Reset(I, 1);
    If IOResult <> 0 Then Err(101);
    FormatVer := 0;
    If FileSize(I) < 48 Then Err(104) Else Begin
      Encrypted := False;
      Compressed := False;
      Valid := True;
      Blockread(I, Magic[1], 4);
      Magic[0] := #4;
      If Magic <> 'VMGP' Then Err(105) Else Begin
        BlockRead(I, Heap, 4);
        Heap := (Heap AND $ffff) SHL 2;
        BlockRead(I, Stack, 2);
        Stack := (Stack AND $ffff) SHL 2;
        BlockRead(I, Flags, 2);
        BlockRead(I, Code, 4);
        While Code MOD 4 <> 0 Do Inc(Code);
        BlockRead(I, Data, 4);
        While Data MOD 4 <> 0 Do Inc(Data);
        BlockRead(I, BSS, 4);
        BlockRead(I, Resource, 4);
        While Resource MOD 4 <> 0 Do Inc(Resource);
        BlockRead(I, ResDecomp, 4);
        BlockRead(I, Pool, 4);
        Pool := (Pool AND $ffffffff) SHL 3;
        BlockRead(I, StringTable, 4);
        While StringTable MOD 4 <> 0 Do Inc(StringTable);
        BlockRead(I, Gunk1, 4);
        BlockRead(I, Gunk2, 4);
        If (Flags AND $8000 = $8000) Then Begin
          If Lo(Gunk2) = $5a4c Then Compressed := True Else Encrypted := True;
        End;
        If ResDecomp = 0 Then If (Compressed) OR (Encrypted) Then Err(106);
      End;
    End;

    If IOResult <> 0 Then Err(103);

    If (Valid) AND (NOT Encrypted) AND (NOT Compressed) Then Begin
      Seek(I, Code + Data + 40);
      If IOResult <> 0 Then Err(102) Else Begin
        BlockRead(I, DRes1, 4);
        Seek(I, FilePos(I) + (DRes1 - 4));
        If IOResult = 0 Then Begin
          BlockRead(I, DRes2, 4);
          If DRes2 = $4154454d Then Begin
            WriteLn('Header    :', 0:10, 40:10);
            WriteLn('Code      :', 40:10, Code:10);
            WriteLn('Data      :', Code + 40:10, Data:10);
            WriteLn('BSS       :', '-':10, BSS:10);
            WriteLn('Heap      :', '-':10, Heap:10);
            WriteLn('Stack     :', '-':10, Stack:10);
            WriteLn('Resource  :', Code + Data + 40:10, Resource:10);
            WriteLn('Pool      :', Code + Data + Resource + 40:10, Pool:10);
            WriteLn('StringTbl :', Code + Data + Resource + Pool + 40:10, StringTable:10);
            Write('Filesize  :', FileSize(I):10);
            If FileSize(I) > Code + Data + Resource + Pool + StringTable + 40 Then WriteLn(' (Extra data at end)')
            Else If FileSize(I) = Code + Data + Resource + Pool + StringTable + 40 Then WriteLn(' (Valid)')
            Else Begin
              WriteLn(' (Truncated)');
              Valid := False;
            End;              
          End
          Else Err(107);

          ClearVars;

          Seek(I, FilePos(I) + 262);
          If IOResult <> 0 Then Err(102);

(*          While Valid Do Repeat
            BlockRead(I, Res1, 2);
            If IOResult <> 0 Then Err(108);
            BlockRead(I, Res2, 2);
            If IOResult <> 0 Then Err(108);
            If (Res1 > 0) AND (Res2 > 0) Then While Valid Do Begin
              SetLength(Field, (Res1 SHR 1) - 1);
              If Length(Field) > 0 Then BlockRead(I, Field[1], Res1) Else Seek(I, FilePos(I) + 2);
              WriteLn(Field);
              SetLength(Value, (Res2 SHR 1) - 1);
              If Length(Value) > 0 Then BlockRead(I, Value[1], Res2) Else Seek(I, FilePos(I) + 2);
              WriteLn(Value);
              BlockRead(I, Dummy, 1);
              If IOResult <> 0 Then Err(108);
              If (Valid) AND (Length(Field) > 0) AND (Length(Value) > 0) Then Begin
                If Field = 'IMEI' Then IMEI := Value;
                If Field = 'Title' Then Title := Value;
                If Field = 'Vendor' Then Vendor := Value;
                If Field = 'Copyright info' Then Copyright := Value;
                If Field = 'Program version' Then Version := Value;
                If Field = 'Help' Then Help := Value;
              End;
              WriteLn('Inner: ', Res1, ' - ', Res2);
            End;
            WriteLn(Res1, ' - ' , Res2);
          Until (EOF(I)) OR ((Res1 = 0) AND (Res2 = 0));
*)

          If Valid Then Repeat
            BlockRead(I, Res1, 2);
            BlockRead(I, Res2, 2);
            If (Res1 > 0) AND (Res2 > 0) Then Begin
              SetLength(Field, (Res1 SHR 1) - 1);
              If Length(Field) > 0 Then BlockRead(I, Field[1], Res1) Else Seek(I, FilePos(I) + 2);
              SetLength(Value, (Res2 SHR 1) - 1);
              If Length(Value) > 0 Then BlockRead(I, Value[1], Res2) Else Seek(I, FilePos(I) + 2);
              BlockRead(I, Dummy, 1);
              If (Length(Field) > 0) AND (Length(Value) > 0) Then Begin
                If Field = 'IMEI' Then IMEI := Value;
                If Field = 'Title' Then Title := Value;
                If Field = 'Vendor' Then Vendor := Value;
                If Field = 'Copyright info' Then Copyright := Value;
                If Field = 'Program version' Then Version := Value;
                If Field = 'Help' Then Help := Value;
              End;
            End;
          Until (Res1 = 0) AND (Res2 = 0);

//          Halt(0);

          If FileSize(I) < 131072 Then Begin
            Seek(I, 0);
            SetLength(CkBuf, FileSize(I));
            BlockRead(I, CkBuf[1], FileSize(I));
            If Pos('M001', CkBuf) > 0 Then Begin
              Seek(I, Pos('M001', CkBuf));
              Repeat
                BlockRead(I, c, 1);
                If (c <> ':') And (c <> #0) Then CertificateDate := CertificateDate + c;
              Until (c = ':') Or (c = #0);
              Delete(CertificateDate, 1, 3);
            End;
            If Pos('M002', CkBuf) > 0 Then Begin
              Seek(I, Pos('M002', CkBuf));
              Repeat
                BlockRead(I, c, 1);
                If (c <> ':') And (c <> #0) Then ExpirationDate := ExpirationDate + c;
              Until (c = ':') Or (c = #0);
              Delete(ExpirationDate, 1, 3);
            End;
            If Pos('M010', CkBuf) > 0 Then Begin
              Seek(I, Pos('M010', CkBuf));
              Repeat
                BlockRead(I, c, 1);
                If (c <> ':') And (c <> #0) Then PhoneNumber := PhoneNumber + c;
              Until (c = ':') Or (c = #0);
              Delete(PhoneNumber, 1, 3);
            End;
          End;
        End
        Else Err(102);
      End;
    End;

    If (Valid) AND (NOT Encrypted) AND (NOT Compressed) Then Begin
      If CertificateDate <> '' Then WriteLn('Cert date : ', CertificateDate);
      If ExpirationDate <> '' Then WriteLn('Expires   : ', ExpirationDate);
      If PhoneNumber <> '' Then WriteLn('Phone #   : ', PhoneNumber);

      If IMEI <> '' Then WriteLn('IMEI      : ', IMEI);
      If Title <> '' Then WriteLn('Title     : ', Title);
      If Vendor <> '' Then WriteLn('Vendor    : ', Vendor);
      If Copyright <> '' Then WriteLn('Copyright : ', Copyright);
      If Version <> '' Then WriteLn('Version   : ', Version);
      If Help <> '' Then WriteLn('Help text : ', Help);
      If Pos('20', Copyright) > 1 Then Begin
        If Copyright[Pos('20', Copyright) + 1] in ['0'..'9'] Then
        If Copyright[Pos('20', Copyright) + 2] in ['0'..'9'] Then
        Year := Copy(Copyright, Pos('20', Copyright), 4);
      End
      Else Year := '';
    End;

    Close(I);
    IOResult;

    If (Valid) AND (NOT Encrypted) AND (NOT Compressed) Then Begin
      OutName := Title;
      If Version <> '' Then OutName := OutName + ' v' + Version;
      If Year = '' Then Year := '20xx';
      OutName := OutName + ' (' + Year + ')';
      If Vendor <> '' Then OutName := OutName + '(' + Vendor + ')'
      Else OutName := OutName + '(' + Copyright + ')';
      If NOT Compressed Then OutName := OutName + '[Comp-]'
      Else If NOT Encrypted Then OutName := OutName + '[Encr-]'
      Else OutName := OutName + '[Encr+]';
      OutName := OutName + '.mpn';
      For Res1 := 1 To Length(OutName) Do If Pos(OutName[Res1], '":\/*?<>|`'#13#10) > 0 Then OutName[Res1] := '_';
    End
    Else If Encrypted Then OutName := SourcePath + DirInfo.Name + '.encrypted'
    Else If Compressed Then OutName := SourcePath + DirInfo.Name + '.compressed'
    Else OutName := SourcePath + DirInfo.Name + '.notanmpn';
//    If IMEI = '' Then WriteLn(OutName, 'lacks IMEI!') Else
    WriteLn('Suggested : ', OutName);
(*
    If NOT FileExists(SourcePath + OutName) Then RenameFile(SourcePath + DirInfo.Name, SourcePath + OutName)
    Else WriteLn(OutName, ' already exists.');
    If IOresult <> 0 Then WriteLn('Error renaming!');
*)
  Until FindNext(DirInfo) <> 0;
  FindClose(DirInfo);
End.
