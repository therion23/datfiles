Program mifname;

{$H+}

{.$DEFINE DEBUG}

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
  LazUTF8,
  LConvEncoding;

Type
  mifMapEntry = Record
    resType,
    firstID,
    addID,
    ofsIdx: UInt16;
  End;

Const

  dumpFile: Boolean = False;
  fixFile: Boolean = False;
  trimFile: Boolean = False;
  renameFile: Boolean = False;

Var

(*
  There is a good reason for setting these arrays to larger than apparently
  necessary sizes. Some .bar files are in the same format as .mif files, so
  you *can* technically validate those as well. Renaming will obviously not
  work - but why would you?
*)

  mifHeader: Array[0..7] Of UInt32;
  mifMap: Array[0..511] Of mifMapEntry;
  mifTable: Array[0..511] Of UInt32;
  mifBody: Array[0..511] Of UInt32;

  mifMapCount: UInt16;
  mifMapPtr,
  mifMapLen: UInt32;

  mifTablePtr,
  mifTableLen: UInt32;

  mifBodyPtr,
  mifBodyLen: UInt32;

  mifPointer: UInt16;

  mifHeaderID,
  mifExpClasses,
  mifAppletID,
  mifExtClasses,
  mifMimeTypes: String;

  mifTitle,
  mifPublisher,
  mifCopyright,
  mifVersion: WideString;

  mifValid: Boolean;

  pFile: File;
  pFileSize: UInt32;
  pFileName: WideString;

  IOErr: UInt16;

  Buf: Array[0..511] Of Byte;
  scanPointer,
  scanValue,
  scanCounter: UInt16;

Procedure Err(ErrCode: Word);
Begin
  Case ErrCode Of
    0: Begin
      WriteLn('mifname rev 2026-03-18, Copyright (c) 2019-today, Nocturnal Productions');
      WriteLn;
      WriteLn('Usage : mifname command filename');
    End;
    2: WriteLn('Open error');
    3: WriteLn('Read error');
    4: WriteLn('Seek error at pos ', FilePos(pFile));
    5: WriteLn('File not found');
    6: WriteLn('Rename error ', IOErr);
    8: WriteLn('* Broken MIF file');
    9: WriteLn('Not a MIF file');
  End;
  If ErrCode > 2 Then Close(pFile);
  Halt(ErrCode);
End;

Procedure ParseParam(pc: Char);
Begin
  Case UpCase(pc) Of
    'C': ;
    'R': renameFile := True;
    'X': dumpFile := True;
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

Function DumpString(Index: DWord): WideString;
Var
  c,
  l: Word;
  s: String;
Begin
  DumpString := '';
  l := mifTable[mifPointer + 1] - mifTable[mifPointer];
  Seek(pFile, mifTable[mifPointer]);
  BlockRead(pFile, Buf[0], l);
{$IFDEF DEBUG}
  If dumpFile Then Case Buf[0] Of
      2: WriteLn('UTF-8');
      3: WriteLn('Latin-1');
    252: WriteLn('GB2312');
    253: WriteLn('SJIS');
    254: WriteLn('CP949');
    255: WriteLn('UTF16LE');
  Else WriteLn('Unicode');
  End;
{$ENDIF}
  s := '';
  c := 0;
  If Buf[0] In [2, 3] Then c := 1;
  If Buf[0] In [252..255] Then c := 2;
  While c < l Do Begin
    s := s + Chr(Buf[c]);
    Inc(c);
  End;
  DumpString := s;
{$IFDEF DEBUG}
  WriteLn(s);
{$ENDIF}
End;

(* *** *)

Var
  i,
  j,
  Size: Word;
  ID: UInt32;
  c: Word;
  s: String;
  ws: WideString;
  NumRead: Word;

{$I-}

(* Legend:

Struct map_entry:
  UInt16 resource_type
  UInt16 first_id
  UInt16 add_ids
  UInt16 offset_table_idx

  0x00 UInt16 = file_type
  0x02 UInt16 = version
  0x04 UInt16 = oldest_version
  0x06 UInt16 = num_map_entries
  0x08 UInt32 = offset_to_map
  0x0C UInt32 = map_size
  0x10 UInt32 = offset_to_offsets
  0x14 UInt32 = num_offsets
  0x18 UInt32 = offset_to_rsc_data
  0x1C UInt32 = rsc_data_size

  offset_to_map      UInt64 = map_entry DUP num_map_entries
  offset_to_offsets  UInt32 = offset_offset 
  offset_to_rsc_data UInt32 = rsc_offset 

*)

Begin
  If ParamCount <> 2 Then Err(0);
  If Length(ParamStr(1)) <> 1 Then Err(0) Else ParseParam(ParamStr(1)[1]);
  If Not FileExists(ParamStr(2)) Then Err(5);
  FileMode := 0;
  Assign(pFile, ParamStr(2));
  Reset(pFile, 1);
  If (IOresult <> 0) Then Err(2);

(*
  The structure of everything, except the map table, is pretty straight forward.
  First we have the header, which is in fact file type and version, however, these
  have never changed throughout history, so we can use them as a magic value.
*)

  For i := 0 To 7 Do BlockRead(pFile, mifHeader[i], 4);
  If (IOresult <> 0) Then Err(3);
  If (mifHeader[0] <> $00010011) Or (Lo(mifHeader[1]) <> $0001) Then Err(9);

(*
  The mifMap is in fact the only tricky part about this format - you will see later.
*)

  mifMapCount := Hi(mifHeader[1]);
  mifMapPtr := mifHeader[2];
  mifMapLen := mifHeader[3];

(*
  What i call the mifTable is officially known as the "offset table".
*)

  mifTablePtr := mifHeader[4];
  mifTableLen := mifHeader[5];

(*
  And the mifBody is "rsc_data" according to Qualcomm.
*)

  mifBodyPtr := mifHeader[6];
  mifBodyLen := mifHeader[7];

(*
  Already here we can do some preliminary validation checks, which are handy, since
  there are no checksums to rely on. Some checks are non fatal, others are very bad
  news.

  The last one is actually non fatal and seen broken in a very low amount of filesets,
  and can be fixed with Qualcomm's MIFEditor. For now, we stick to whining about it.
*)

  mifValid := True;
  If mifMapPtr + mifMapLen <> mifTablePtr Then Err(8);
  If mifTablePtr + (mifTableLen * 4) + 4 <> mifBodyPtr Then Err(8);
  If FileSize(pFile) <> mifBodyPtr + mifBodyLen Then mifValid := False;
//  If FileSize(pFile) <> mifBodyPtr + mifBodyLen Then Err(8);

  For i := 0 To mifMapCount - 1 Do BlockRead(pFile, mifMap[i], 8);
  For i := 0 To mifTableLen - 1 Do BlockRead(pFile, mifTable[i], 4);
{$IFDEF DEBUG}
  If dumpFile Then For i := 0 To 7 Do WriteLn((i * 4):5, ' - ', IntToHex(mifHeader[i]));
{$ENDIF}

(*
  Under most, but not all, circumstances, the mifTable ends with a pointer to EOF.
  Since the specifications (what specifications?) say absolutely nothing about this,
  we treat it as a non fatal error - as long as it looks like an overdump.
*)

  BlockRead(pFile, pFileSize, 4);
  If pFileSize > FileSize(pFile) Then Err(8)
  Else If pFileSize < FileSize(pFile) Then Begin
    WriteLn('* Header inconsistency (', pFileSize, ' != ', FileSize(pFile), ')');
    mifValid := False;
  End;
  mifTable[mifTableLen] := FileSize(pFile);

  If mifValid Then WriteLn('* All header checks passed')
  Else WriteLn('* Non fatal header check error');

(*
  Now for the fun bits. The whole confusion is that a map entry can point to one or
  more table entries of the same type. So the second ID of a type 6 entry is in fact
  a type 7 entry.

  This is of course completely simple to parse, butt figuring it out from hex dumps
  was a nightmare and a half.
*)

  mifPointer := 0;

  For i := 0 To mifMapCount - 1 Do Begin
{$IFDEF DEBUG}
    If dumpFile Then WriteLn('Map #', i:2, ' - Type ', mifMap[i].resType:5, ' - ID ', mifMap[i].firstID:5, ' - Count ', mifMap[i].addID + 1);
{$ENDIF}
    For j := 0 To mifMap[i].addID Do Begin
      If mifMap[i].resType = 1 Then Begin
        Case mifMap[i].firstID + j Of
             6: mifPublisher := DumpString(mifPointer);
             7: mifCopyright := DumpString(mifPointer);
             8: mifVersion := DumpString(mifPointer);
            20,
          1000: mifTitle := DumpString(mifPointer);
        End;
        If dumpFile Then Case mifMap[i].firstID + j Of
             6: WriteLn('* Company    : ', mifPublisher);
             7: WriteLn('* Copyright  : ', mifCopyright);
             8: WriteLn('* Version    : ', mifVersion);
            20,
          1000: WriteLn('* Title      : ', mifTitle);
        Else WriteLn('* Unknown type ', mifMap[i].firstID + j);
        End;
      End;
      If mifMap[i].resType = 6 Then Begin
        If dumpFile Then Case mifMap[i].firstID + j Of
            21,
          1001: Write('* Medium img :');
            22,
          1002: Write('* Large img  :');
            23,
          1003: Write('* Small img  :');
        Else Write('* Unknown    ');
        End;
        If dumpFile Then WriteLn(' Offset ', mifTable[mifPointer]:7, ' size ', (mifTable[mifPointer + 1] - mifTable[mifPointer]):5);
      End;
      If mifMap[i].resType = 20480 Then Begin
        Case mifMap[i].firstID + j Of
          0: Begin
               Seek(pFile, mifTable[mifPointer]);
               If IOresult <> 0 Then Err(4);
               BlockRead(pFile, ID, 4);
               If IOresult <> 0 Then Err(3);
               mifHeaderID := IntToHex(ID, 8);
             End;
          1: Begin
               Seek(pFile, mifTable[mifPointer]);
               If IOresult <> 0 Then Err(4);
               BlockRead(pFile, ID, 4);
               If IOresult <> 0 Then Err(3);
               mifExpClasses := IntToHex(ID, 8);
             End;
          2: Begin
               Seek(pFile, mifTable[mifPointer]);
               If IOresult <> 0 Then Err(4);
               BlockRead(pFile, ID, 4);
               If IOresult <> 0 Then Err(3);
               mifAppletID := IntToHex(ID, 8);
             End;
          3: Begin
               Seek(pFile, mifTable[mifPointer]);
               If IOresult <> 0 Then Err(4);
               For c := 0 To ((mifTable[mifPointer + 1] - mifTable[mifPointer]) DIV 4) - 2 Do Begin
                 BlockRead(pFile, ID, 4);
                 If IOresult <> 0 Then Err(3);
                 mifExtClasses := mifExtClasses + ' ' + IntToHex(ID, 8);
               End;
               Delete(mifExtClasses, 1, 1);
             End;
//          5: Write('* Mime Types');
//        Else Write('* Unknown   ');
        End;
        If dumpFile Then Case mifMap[i].firstID + j Of
          0: WriteLn('* Header     : ', mifHeaderID);
          1: WriteLn('* Exports    : ', mifExpClasses);
          2: WriteLn('* Applet     : ', mifAppletID);
          3: WriteLn('* Requires   : ', mifExtClasses);
          5: WriteLn('* Mime Types ID at ', mifTable[mifPointer]:5, ' size ', (mifTable[mifPointer + 1] - mifTable[mifPointer]):5);
        Else WriteLn('* Unknown    ID at ', mifTable[mifPointer]:5, ' size ', (mifTable[mifPointer + 1] - mifTable[mifPointer]):5);
        End;
      End;
      Inc(mifPointer);
    End;
  End;

  Close(pFile);

  If mifTitle = '' Then mifTitle := '(Unknown)';
  pFileName := mifTitle + ' v' + mifVersion + ' (' + mifCopyright + ')(' + mifPublisher + ')';
  If mifAppletID <> '' Then pFileName := pFileName + '[ID ' + mifAppletID + ']'
  Else If mifExpClasses <> '' Then pFileName := pFileName + '[Exports ' + mifExpClasses + ']';
  If Not mifValid Then pFileName := pFileName + '[b]';

  For i := 1 To Length(pFileName) Do If Pos(pFileName[i], '":\/*?<>|`') > 0 Then pFileName[i] := '_';
  pFileName := UTF8StringReplace(pFileName, '  ', ' ', [rfReplaceAll]);
  pFileName := UTF8Trim(ExtractFilePath(ParamStr(2)) + pFileName + '.mif');
  If renameFile Then Begin
(*
    If Not FileExists(pFileName) Then Rename(pFile, pFileName)
    Else WriteLn('File already exists');
*)
    IOErr := IOresult;
    If IOErr > 0 Then Err(6);
  End;
  WriteLn('* Suggested  : ', pFileName);
End.

