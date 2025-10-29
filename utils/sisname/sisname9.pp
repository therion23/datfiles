Program sisname9;

{$DEFINE RELEASE}

(*
** TODO:
** - Decode Controller
** - Implement BlockRead() for OutBuf?
** - Prefer English component name
** - Fixup for cases like TV Mobile (invalid Unicode)
** - Double check variables do not need resetting per loop
** - More strict size checking and get rid of trailing junk
*)

Uses
  DOS,
  CRC16,
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
  LazFileUtils;

Const
  Countries: Array[1..98] Of String[2] = ('EN', 'FR', 'GE', 'SP', 'IT', 'SW', 'DA', 'NO', 'FI', 'AM', 'SF', 'SG', 'PO', 'TU', 'IC', 'RU', 'HU', 'DU', 'BL', 'AU', 'BG', 'AS', 'NZ', 'IF', 'CS', 'SK', 'PL', 'SL', 'TC', 'HK', 'ZH', 'JA', 'TH', 'AF', 'SQ', 'AH', 'AR', 'HY', 'TL', 'BE', 'BN', 'BG', 'MY', 'CA', 'HR', 'CE', 'IE', 'SF', 'ET', 'FA', 'CF', 'GD', 'KA', 'EL', 'CG', 'GU', 'HE', 'HI', 'IN', 'GA', 'SZ', 'KN', 'KK', 'KM', 'KO', 'LO', 'LV', 'LT', 'MK', 'MS', 'ML', 'MR', 'MO', 'MN', 'NN', 'BP', 'PA', 'RO', 'SR', 'SI', 'SO', 'OS', 'LS', 'SH', 'FS', 'XX', 'TA', 'TE', 'BO', 'TI', 'CT', 'TK', 'UK', 'UR', 'XX', 'VI', 'CY', 'ZU');

Var
  I,
  O: File;

  DirInfo: TSearchRec;
  SourcePath: String;
  FormatVer: Byte;

  SisFieldType: DWord;

  SisControllerOffset,
  SisControllerSize,
  SisContentsOffset,
  SisContentsSize,
  SisDataOffset,
  SisDataSize: DWord;

  SisControllerUncompSize: QWord;

  SisControllerChecksum,
  SisContentsChecksum,
  SisDataChecksum,
  SisControllerMethod: DWord;

  CalcControllerChecksum,
  CalcContentsChecksum,
  CalcDataChecksum: Word;

  CBlock,
  DBlock: Boolean;

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
  InBuf,
  OutBuf: Array[0..2097151] of Byte;

  InSize: DWord;
  OutSize: QWord;

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
//    103: WriteLn('Error seeking in file ', DirInfo.Name, ' - CompPtr: ', CompPtr, ' - DRes1: ', DRes1, ' - DRes2: ', DRes2);
    103: WriteLn('Error seeking in file ', DirInfo.Name);
    104: WriteLn(DirInfo.Name, ' truncated by ', (SISContentsSize - 24) - DirInfo.Size, ' bytes');
    105: WriteLn('Invalid ESISFieldType');
    106: WriteLn('Invalid checksum size');
    107: WriteLn('Invalid compression method');
    108: WriteLn('Invalid compressed data');
  End;
  FormatVer := 0;
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
  InPtr := @InBuf[0];
  OutPtr := @OutBuf[0];
  FillChar(OutBuf[0], 2097152, 0);

  d_stream.next_in  := InPtr;
  d_stream.avail_in := SisControllerSize;

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

  If d_stream.total_out = SisControllerUncompSize Then MyInflate := 0;
(*
    Assign(O, 'testing.out');
    Rewrite(O, 1);
    BlockWrite(O, Outbuf[0], SisControllerUncompSize);
    Close(O);
    WriteLn('large_inflate(): OK');
    WriteLn(IntToHex(OutBuf[0]));
*)
End;

Function CalcCRC(FStart, FLen: DWord): DWord;
Begin
  Res1 := 0;
  Seek(I, FStart);
  DRes1 := FLen;
  While DRes1 MOD 4 <> 0 Do Inc(DRes1);
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
  CalcCRC := Res1;
//  Write(IntToHex(FStart), ' - ' , IntToHex(FLen), ' - ');
End;

Function ParseFieldType(ESISFieldType: DWord): DWord;
Begin
  ParseFieldType := 0;
  Case ESISFieldType Of
    $00: Err(105);
    $01: ; // SISString
    $02: ; // SISArray
    $03: Begin // SISCompressed
           SisControllerOffset := FilePos(I);
           BlockRead(I, SisControllerSize, 4);
           SisControllerSize := SisControllerSize - 12;
           BlockRead(I, SisControllerMethod, 4);
           BlockRead(I, SisControllerUncompSize, 8);
           FillChar(InBuf[0], 2097152, 0);
           BlockRead(I, InBuf[0], SisControllerSize);
           While FilePos(I) MOD 4 <> 0 Do Seek(I, FilePos(I) + 1);
           WriteLn(SisControllerUncompSize);
           Case SisControllerMethod Of
             0: OutBuf := InBuf;
             1: If MyInflate <> 0 Then Err(108);
           Else Err(107);
           End;
         End;
    $04: ; // SISVersion
    $05: ; // SISVersionRange
    $06: ; // SISDate
    $07: ; // SISTime
    $08: ; // SISDateTime
    $09: ; // SISUid
    $0a: Err(105);
    $0b: ; // SISLanguage
    $0c: Begin // SISContents
           BlockRead(I, SisContentsSize, 4);
           If (SisContentsSize + 24) > FileSize(I) Then Err(104);
//           WriteLn('Size: ', SisContentsSize, ' (', IntToHex(SisContentsSize), ') - Calculated: ', FileSize(I) - 24, ' (', IntToHex(Filesize(I) - 24), ')');
         End;
    $0d: ; // SISController
    $0e: ; // SISInfo
    $0f: ; // SISSupportedLanguages
    $10: ; // SISSupportedOptions
    $11: ; // SISPrerequisites
    $12: ; // SISDependency
    $13: ; // SISProperties
    $14: ; // SISProperty
    $15: ; // SISSignatures
    $16: ; // SISCertificateChain
    $17: ; // SISLogo
    $18: ; // SISFileDescription
    $19: ; // SISHash
    $1a: ; // SISIf
    $1b: ; // SISElseIf
    $1c: ; // SISInstallBlock
    $1d: ; // SISExpression
    $1e: Begin // SISData
           SisDataOffset := FilePos(I);
           BlockRead(I, SisDataSize, 4);
           Seek(I, FilePos(I) + SisDataSize);
           While FilePos(I) MOD 4 <> 0 Do Seek(I, FilePos(I) + 1);
         End;
    $1f: ; // SISDataUnit
    $20: ; // SISFileData
    $21: ; // SISSupportedOption
    $22: Begin // SISControllerChecksum
           BlockRead(I, DRes1, 4);
           If DRes1 > 4 Then Err(106) Else Begin
             SisControllerChecksum := 0;
             BlockRead(I, SisControllerChecksum, DRes1);
             Seek(I, FilePos(I) + (4 - DRes1));
             If SisControllerChecksum = 0 Then SisControllerChecksum := $FF000000;
           End;
         End;
    $23: Begin // SISDataChecksum
           BlockRead(I, DRes1, 4);
           If DRes1 > 4 Then Err(106) Else Begin
             SisDataChecksum := 0;
             BlockRead(I, SisDataChecksum, DRes1);
             Seek(I, FilePos(I) + (4 - DRes1));
             If SisDataChecksum = 0 Then SisDataChecksum := $FF000000;
           End;
         End;
    $24: ; // SISSignature
    $25: ; // SISBlob
    $26: ; // SISSignatureAlgorithm
    $27: ; // SISSignatureCertificateChain
    $28: ; // SISDataIndex
    $29: ; // SISCapabilities
  Else Err(105);
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
//    WriteLn(SourcePath + DirInfo.Name);
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
//        WriteLn('EPOC 2-5');
        FormatVer := 2;
      End
      Else If (CRC2 = $10003A12) AND (CRC3 = $10000419) Then Begin
//        WriteLn('Symbian 6-9');
        FormatVer := 6;
      End
      Else If (CRC1 = $10201a7a) AND (CRC2 = $00000000) Then Begin
//        WriteLn('Symbian 9.1+');
        FormatVer := 9;
      End;
    End;
    CalcHdrSum := '';
    If FormatVer > 0 Then Begin
//      Write('Header checksum: ', inttohex(CRC4), ' - Calculated: ');
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
//      WriteLn(CalcHdrSum);
    End;
    CBlock := False;
    DBlock := False;
    SisControllerOffSet := 0;
    SisControllerSize := 0;
    SisControllerChecksum := $FF000000;
    SisDataOffSet := 0;
    SisDataSize := 0;
    SisDataChecksum := $FF000000;
    If FormatVer = 9 Then Repeat
      BlockRead(I, SisFieldType, 4);
//      WriteLn('Filepos: ', IntToHex(FilePos(I)), ' - Opcode ', IntToHex(SisFieldType), ' at ', IntToHex(FilePos(I) - 4));
      If IOResult <> 0 Then Err(103)
      Else ParseFieldType(SisFieldType);
      If IOResult <> 0 Then Err(103)
    Until (EOF(I)) OR (FilePos(I) >= SisContentsSize + 24) OR (FormatVer <> 9);
    If CalcHdrSum <> IntToHex(CRC4) Then WriteLn('Header checksum mismatch');
    If FormatVer = 9 Then Begin
      If SisControllerChecksum <= $FFFF Then Begin
        If IntToHex(Lo(CalcCRC(SisControllerOffset - 4, SisControllerSize + 20))) <> IntToHex(Lo(SisControllerChecksum)) Then Begin
          WriteLn('Controller checksum mismatch');
        End;
      End;
      If SisDataChecksum <= $FFFF Then Begin
        If IntToHex(Lo(CalcCRC(SisDataOffset - 4, SisDataSize + 8))) <> IntToHex(Lo(SisDataChecksum)) Then Begin
          WriteLn('Data checksum mismatch');
        End;
      End;
    End;
    Close(I);
    If FormatVer = 0 Then Begin
      OutName := SourcePath + DirInfo.Name + '.notasis';
      If NOT FileExists(OutName) Then Begin
//        RenameFile(SourcePath + DirInfo.Name, OutName);
      End
      Else WriteLn(OutName, ' already exists.');
      If IOresult <> 0 Then WriteLn('Error renaming!');
    End;
  Until FindNext(DirInfo) <> 0;
  FindClose(DirInfo);
End.
