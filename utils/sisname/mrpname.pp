Program mrpname;

{$H+}

Uses
  DOS,
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
  LConvEncoding,

  CRC;

Const

  dumpFiles: Boolean = False;
  fixFile: Boolean = False;
  renameFile: Boolean = False;

Type

  mrpRec = Record
    Magic: String[4];
    FileTable: UInt32;
    FileLen: UInt32;
    IndexTable: UInt32;
    FileName: String; // 12
    AppName: AnsiString; // 24
    AuthCode: String; // 16
    AppID: UInt32;
    AppVer: UInt32;
    AppFlags: UInt32;
    FormatVer: UInt32;
    CRC: UInt32;
    Vendor: AnsiString; // 40
    Description: AnsiString; // 64
    AppIDBE: UInt32;
    AppVerBE: UInt32;
    Dummy1: UInt32;
    ScrW: Word;
    ScrH: Word;
    Platform: Byte;
  End;

Var

  mrp: mrpRec;

  pFile: File;
  pFileSize: DWord;
  pFileName: WideString;
  IOErr: Word;

  Buf: Array[0..239] Of Byte;
  scanPointer,
  scanValue,
  scanCounter: Word;

Procedure Err(ErrCode: Word);
Begin
  Case ErrCode Of
    0: Begin
      WriteLn('mrpname rev 2026-03-17, Copyright (c) 2019-today, Nocturnal Productions');
      WriteLn('Huge thanks to D-Free-J for the structures!');
      WriteLn;
      WriteLn('Usage : mrpname command filename');
      WriteLn;
      WriteLn('Command can be one of (r)ename or (f)ix (single letter)');
      WriteLn('Extract not implemented yet - it is simply too trivial');
    End;
    2: WriteLn('Open error');
    3: WriteLn('Read error');
    4: WriteLn('Seek error at pos ', FilePos(pFile));
    5: WriteLn('File not found');
    6: WriteLn('Rename error ', IOErr);
    7: WriteLn('Write error');
    8: WriteLn('Broken MRP file');
    9: WriteLn('Not an MRP file');
  End;
  Halt(ErrCode);
End;

Procedure ParseParam(pc: Char);
Begin
  Case UpCase(pc) Of
    'R': renameFile := True;
    'F': fixFile := True;
    'X': dumpFiles := True;
    Else Err(0);
  End;
End;

Function GetWord (w: Word): Word;
Begin
  GetWord := (Buf[w]) + (Buf[w + 1] SHL 8);
End;

Function GetLong (w: Word): DWord;
Begin
  GetLong := (Buf[w]) + (Buf[w + 1] SHL 8) + (Buf[w + 2] SHL 16) + (Buf[w + 3] SHL 24);
End;

Function DumpString(Offset, Size: DWord): String;
Var
  c: Word;
Begin
  DumpString := '';
  For c := Offset To (Offset + (Size - 1)) Do
    If (Buf[c] <> 13) And (Buf[c] <> 10) And (Buf[c] <> 0) Then DumpString := DumpString + Chr(Buf[c]);
End;

(* *** *)

Var
  i,
  j,
  Size: Word;
  c: Char;
  s: String;
  crcvalue: DWord;
  NumRead: Word;

{$I-}

Begin
  If ParamCount <> 2 Then Err(0);
  If Length(ParamStr(1)) <> 1 Then Err(0) Else ParseParam(ParamStr(1)[1]);
  If Not FileExists(ParamStr(2)) Then Err(5);
  FileMode := 0;
  Assign(pFile, ParamStr(2));
  Reset(pFile, 1);
  If (IOresult <> 0) Then Err(2);
  pFileSize := FileSize(pFile);
  If pFileSize < 240 Then Err(9);
  BlockRead(pFile, Buf[0], 240);
  If (IOresult <> 0) Then Err(3);
  mrp.Magic := DumpString(0, 4);
  if mrp.Magic <> 'MRPG' Then Err(9);
  mrp.FileTable := GetLong(4);
  mrp.FileLen := GetLong(8);
  If pFileSize <> mrp.FileLen Then Err(8);
  mrp.IndexTable := GetLong(12);
  mrp.FileName := ReplaceText(DumpString(16, 12), '.mrp', '');
  s := DumpString(28, 24);
  mrp.AppName := CP936ToUTF8(s);
  mrp.AuthCode := DumpString(52, 16);
  mrp.AppID := GetLong(68);
  mrp.AppVer := GetLong(72);
  mrp.AppFlags := GetLong(76);
  mrp.FormatVer := GetLong(80);
  mrp.CRC := GetLong(84);
  s := DumpString(88, 40);
  mrp.Vendor := CP936ToUTF8(s);
  s := DumpString(128, 64);
  mrp.Description := CP936ToUTF8(s);
  mrp.AppIDBE := GetLong(192);
  mrp.AppVerBE := GetLong(196);
  mrp.Dummy1 := GetLong(200);
  mrp.ScrW := GetWord(204);
  mrp.ScrH := GetWord(206);
  mrp.Platform := Buf[208];

  crcvalue := crc32(0, nil, 0);
  For i := 84 To 87 Do Buf[i] := 0;
  crcvalue := crc32(crcvalue, @buf[0], 240);
  Seek(pFile, 240);
  Repeat
    BlockRead (pFile, Buf, Sizeof(Buf), NumRead);
    crcvalue := crc32(crcvalue, @Buf[0], NumRead);
  Until (NumRead = 0);

  If dumpFiles Then Begin
  End;

  If fixFile Then Begin
    Close(pFile);
    FileMode := 2;
    Reset(pFile, 1);
    Seek(pFile, 84);
    BlockWrite(pFile, crcvalue, 4);
    If IOresult > 0 Then Err(7);
  End;

  Close(pFile);

  pFileName := mrp.AppName;
  If (mrp.AppVer > 0) Then Begin
    s := IntToStr(mrp.AppVer);
    While Length(s) < 4 Do s := '0' + s;
    s := s[1] + '.' + s[2] + '.' + s[3] + '.' + s[4];
    If Length(s) > 4 Then s := s + Copy(IntToStr(mrp.AppVer), 5, Length(IntToStr(mrp.AppVer)) - 4);
    pFileName := pFileName + ' v' + s;
  End;

  pFileName := PFileName + ' (20xx)(' + mrp.Vendor + ')';
  If IntToHex(mrp.CRC) = IntToHex(crcvalue) Then pFileName := pFileName + '[!]' Else pFileName := pFileName + '[b]';
  pFileName := PFileName + '[' + mrp.FileName + '][' + IntToHex(crcvalue) + ']';
  For i := 1 To Length(pFileName) Do If Pos(pFileName[i], '":\/*?<>|`') > 0 Then pFileName[i] := '_';
  pFileName := ExtractFilePath(ParamStr(2)) + pFileName + '.mrp';
  If renameFile Then Begin
    If Not FileExists(pFileName) Then Rename(pFile, pFileName)
    Else WriteLn('File already exists');
    IOErr := IOresult;
    If IOErr > 0 Then Err(6);
  End;
  WriteLn(ParamStr(2), ' -> ' , pFileName);
End.

