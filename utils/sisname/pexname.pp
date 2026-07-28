Program pexname;

{$DEFINE RELEASE}

(*
** TODO:
*)

Uses
  DOS,
  CRC,
  ZBase,
  ZInflate,
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
//  LConvEncoding,
  iconvenc,
  LazFileUtils;

Var
  I,
  O: File;

  MB,
  FT: UInt8;

  DataOfs,
  NameOfs,
  IconOfs: UInt16;

  PackedSize,
  UnpackedSize,
  PackedCRC,
  UnpackedCRC: UInt32;

  PexMajor,
  PexMinor: UInt8;

  CalcCRC: UInt32;

  B: Byte;
  C: Char;

  Res1,
  Res2: Word;

  CkBuf: Array[1..32768] of Byte;
  InBuf,
  OutBuf: Array[0..2097151] of Byte;

  Title: String;
  ETitle: AnsiString;
  OutName: String;

  CalcHdrSum: String[8];
  CalcCkSum: String[4];

Procedure Err(ErrCode: Byte);
Begin
  WriteLn;
  Case ErrCode Of
    0: Begin
      WriteLn('pexname rev 2026-07-28, Copyright (c) 2019-today, Nocturnal Productions');
      WriteLn;
      WriteLn('Usage : pexname filename');
    End;
    101: WriteLn('Error opening file');
    102: WriteLn('Error reading header');
    103: WriteLn('Error seeking in file');
    104: WriteLn('Error reading body');
    105: WriteLn('Invalid outer checksum');
    106: WriteLn('Invalid inner checksum');
    107: WriteLn('Invalid compression method');
    108: WriteLn('Invalid compressed data');
	111: WriteLn('Invalid outer header');
	112: WriteLn('Invalid inner header');
  End;
  If ErrCode > 101 Then Close(I);
  Halt(ErrCode);
End;

Procedure CHECK_ERR(err : Integer; msg : String);
Begin
  If (err <> Z_OK) Then Write(msg, ' error: ', err);
End;

Function MyInflate: Word;
Var
  InPtr,
  OutPtr: PByte;
  err: Integer;
  d_stream: z_stream;
Begin
  MyInflate := $FFFF;
  InPtr := @InBuf[8];
  OutPtr := @OutBuf[0];
  FillChar(OutBuf[0], 2097152, 0);

  d_stream.next_in  := InPtr;
  d_stream.avail_in := PackedSize - 8;

  err := inflateInit(d_stream);
  CHECK_ERR(err, 'inflateInit');

  While TRUE Do Begin
    d_stream.next_out := OutPtr;            { discard the output }
    d_stream.avail_out := 2097152;
    err := inflate(d_stream, Z_NO_FLUSH);
    If (err = Z_STREAM_END) Then Break;
    CHECK_ERR(err, 'large inflate');
  End;

  err := inflateEnd(d_stream);
  CHECK_ERR(err, 'inflateEnd');

  If d_stream.total_out = UnpackedSize Then MyInflate := 0;
//  WriteLn('large_inflate(): OK');
End;

Begin
  Assign(Output, '');
  Rewrite(Output);
{$I-}
  FileMode := 0;
  Assign(I, ParamStr(1));
  FileMode := 0;
  Reset(I, 1);
  If IOResult <> 0 Then Err(101);
  BlockRead(I, MB, 1);
  BlockRead(I, FT, 1);
  If IOResult <> 0 Then Err(102);
  If (MB <> $58) AND (FT <> $02) Then Err(111);
  BlockRead(I, DataOfs, 2);
  BlockRead(I, NameOfs, 2);
  BlockRead(I, IconOfs, 2);
  If IOResult <> 0 Then Err(102);
  Seek(I, FilePos(I) + 8);
  If IOResult <> 0 Then Err(103);
  BlockRead(I, PackedSize, 4);
  BlockRead(I, PackedCRC, 4);
  If IOResult <> 0 Then Err(102);

  Seek(I, DataOfs);
  BlockRead(I, UnpackedSize, 4);
  BlockRead(I, UnpackedCRC, 4);
  If IOResult <> 0 Then Err(102);

//  PackedSize := PackedSize - 8;
  Seek(I, DataOfs);
  BlockRead(I, InBuf[0], PackedSize);
  If IOResult <> 0 Then Err(104);

  CalcCRC := crc32(0, nil, 0);
  CalcCRC := crc32(CalcCRC, @InBuf[0], PackedSize);
  If CalcCRC <> PackedCRC Then Err(105);
  
  If MyInflate <> 0 Then Err(108);

  CalcCRC := crc32(0, nil, 0);
  CalcCRC := crc32(CalcCRC, @OutBuf[0], UnpackedSize);
  If CalcCRC <> UnpackedCRC Then Err(106);
  
  If (OutBuf[0] <> Ord('p')) OR (OutBuf[1] <> Ord('C')) OR (OutBuf[2] <> Ord('e')) OR (OutBuf[3] <> Ord('A')) Then Err(112);

  PexMinor := OutBuf[4];
  PexMajor := OutBuf[5];

  Title := '';
  B := 0;
  Seek(I, NameOfs);
  Repeat
    BlockRead(I, B, 1);
    If B > 0 Then Title := Title + Chr(B);
  Until B = 0;
  
  If Title = '' Then Title := '(Unknown)';
  Title := Title + ' [' + IntToStr(PexMajor) + '.' + IntToStr(PexMinor) + ']';
//  If Not PexValid Then Title := Title + '[b]';
//  For Res1 := 1 To Length(Title) Do If Pos(Title[Res1], '":\/*?<>|`') > 0 Then Title[Res1] := '_';
//  Title := UTF8StringReplace(Title, '  ', ' ', [rfReplaceAll]);
  Iconvert(Title, ETitle, 'cp932', 'UTF-8');
(*
  If renameFile Then Begin
    If Not FileExists(ETitle) Then Rename(pFile, ETitle)
    Else WriteLn('File already exists');
    If IOresult > 0 Then Err(6);
  End;
*)
  WriteLn('* Suggested  : ', ETitle);
End.
simpleｲﾗｽﾄﾛｼﾞｯｸ
