Program vpxname;

{$DEFINE RELEASE}

(*
** TODO:
**
** OLD TODO:
** - Prefer English component name
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

  VpxFieldType: DWord;

  VpxMetaOffset,
  VpxMetaSize,
  VpxContentsOffset,
  VpxContentsSize,
  VpxDataOffset,
  VpxDataSize,
  VpxChunkSize,
  VpxChunkUncompSize: DWord;

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

  Background,
  Rotation,
  Compressed,
  Unicode,
  Venus,
  NoScreen,
  Push,
  AB2,
  AppAdvIcon,
  AppAutoStart,
  AppIdle,
  Valid: Boolean;

  AppID,
  KeyID,
  AppVer,
  ReqMem,
  EngineVer,
  InputMode,
  FileType,
  SysFileMaxSize,
  AppPushID: DWord;

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

  Field,
  IMEI,
  Title,
  Vendor,
  Copyright,
  Version,
  Year: WideString;

  Value: DWord;

  ETitle: String;
  OutName: String;

  CalcHdrSum: String[8];
  CalcCkSum: String[4];
  Magic: String[6];

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
    104: WriteLn(DirInfo.Name, ' truncated by ', (VpxContentsSize - 24) - DirInfo.Size, ' bytes');
    105: WriteLn('Invalid VpxTagType ', DRes1);
    106: WriteLn('Invalid checksum size');
    107: WriteLn('Invalid compression method');
    108: WriteLn('Invalid compressed data');
    109: WriteLn('Magic value not found');
    110: WriteLn('Invalid compression method');
    111: WriteLn('Invalid compressed data');
  End;
  Valid := False;
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
  d_stream.avail_in := VpxChunkSize;

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

  If d_stream.total_out = VpxChunkUncompSize Then MyInflate := 0;
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

Function ParseFieldType(EVPXTagType: DWord): DWord;
Begin
  ParseFieldType := 0;
  WriteLn(EVPXTagType);
  Case EVPXTagType Of
    $00: ; // Null
    $01: Seek(I, FilePos(I) + DRes2); // Developer name
    $02: BlockRead(I, AppID, 4); // Application ID
    $03: BlockRead(I, KeyID, 4); // Key ID index
    $04: Seek(I, FilePos(I) + DRes2); // Application Name
    $05: BlockRead(I, AppVer, 4); // Application version
    $06: Seek(I, FilePos(I) + DRes2); // License issue date
    $07: Seek(I, FilePos(I) + DRes2); // License expiration date
    $08: Seek(I, FilePos(I) + DRes2); // VM_CE_INFO_PAY (billing)
    $09: Seek(I, FilePos(I) + DRes2); // VM_CE_INFO_PAY_NODE (billing)
    $0a: Seek(I, FilePos(I) + DRes2); // VM_CE_INFO_PRICE (billing)
    $0b: Seek(I, FilePos(I) + DRes2); // VM_CE_INFO_PAY_MODE (billing)
    $0c: Seek(I, FilePos(I) + DRes2); // VM_CE_INFO_PAY_PARAM (billing)
    $0d: Seek(I, FilePos(I) + DRes2); // VM_CE_INFO_APP_USE (billing)
    $0e: Seek(I, FilePos(I) + DRes2); // VM_CE_INFO_PAY_CHANNEL (billing)
    $0f: BlockRead(I, ReqMem, 4); // Required KB
    $10: Seek(I, FilePos(I) + DRes2); // Resolution
    $11: BlockRead(I, EngineVer, 4); // Engine version
    $12: Seek(I, FilePos(I) + DRes2); // IMSI
    $13: Seek(I, FilePos(I) + DRes2); // Permission list
    $14: Seek(I, FilePos(I) + DRes2); // VM_CE_INFO_TRIAL
    $15: Seek(I, FilePos(I) + DRes2); // VM_CE_INFO_COMPILER
    $16: BlockRead(I, InputMode, 4); // Input mode
    $17: Seek(I, FilePos(I) + DRes2); // Application description
    $18: Begin // Background run
           BlockRead(I, Value, 4);
           Background := (Value = 1);
         End;
    $19: Seek(I, FilePos(I) + DRes2); // Application name (multilanguage)
    $1a: Seek(I, FilePos(I) + DRes2); // Application description (multilanguage)
    $1b: Seek(I, FilePos(I) + DRes2); // Application name zimo (multilanguage)
    $1c: Begin // Rotation
           BlockRead(I, Value, 4);
           Rotation := (Value = 1);
         End;
    $1d: Seek(I, FilePos(I) + DRes2); // VM_CE_INFO_SM
    $1e: Seek(I, FilePos(I) + DRes2); // VM_CE_INFO_SM_TYPE
    $1f: Seek(I, FilePos(I) + DRes2); // VM_CE_INFO_SM_PRIVATE
    $20: Seek(I, FilePos(I) + DRes2); // VM_CE_INFO_SM_CRYPTEXT
    $21: BlockRead(I, FileType, 4); // File type and compiler
    $22: Begin // Compressed
           BlockRead(I, Value, 4);
           Compressed := (Value = 1);
         End;
    $23: Begin // Unicode
           BlockRead(I, Value, 4);
           Unicode := (Value = 1);
         End;
    $24: Begin // Venus support
           BlockRead(I, Value, 4);
           Venus := (Value = 1);
         End;
    $25: BlockRead(I, SysFileMaxSize, 4); // System file max size
    $26: Seek(I, FilePos(I) + DRes2); // VM_CE_INFO_MULTI_NAME_LIST
    $27: Seek(I, FilePos(I) + DRes2); // VM_CE_INFO_URL
    $28: Seek(I, FilePos(I) + DRes2); // VM_CE_INFO_UPDATE_INFO
    $29: Begin // No screen
           BlockRead(I, Value, 4);
           NoScreen := (Value = 1);
         End;
    $2a: Seek(I, FilePos(I) + DRes2); // VPP type
    $2b: Err(105); // (Unused)
    $2c: Begin // Push
           BlockRead(I, Value, 4);
           Push := (Value = 1);
         End;
    $2d: BlockRead(I, AppPushID, 4); // Push ID
    $2e: Seek(I, FilePos(I) + DRes2); // Push sender ID
    $2f: Begin // AB2 image
           BlockRead(I, Value, 4);
           AB2 := (Value = 1);
         End;
    $30: Seek(I, FilePos(I) + DRes2); // VM_CE_INFO_BUILD_ID
    $31: Begin // Advanced icon
           BlockRead(I, Value, 4);
           AppAdvIcon := (Value = 1);
         End;
    $32: Begin // Auto start
           BlockRead(I, Value, 4);
           AppAutoStart := (Value = 1);
         End;
    $33: Begin // Idle shortcut
           BlockRead(I, Value, 4);
           AppIdle := (Value = 1);
         End;
    Else Begin
      IOResult;
      Seek(I, FilePos(I) + DRes2);
      If IOResult <> 0 Then Err(103);
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
    If FileSize(I) >= 128 Then Begin
      Compressed := False;
      Unicode := False;
      Valid := True;
      Seek(I, FileSize(I) - 12);
      BlockRead(I, VpxMetaOffset, 4);
      If VpxMetaOffset > FileSize(I) Then Err(103) Else Begin
        Seek(I, FileSize(I) - 86);
        Magic[0] := #6;
        BlockRead(I, Magic[1], 6);
        If Magic <> #$b4'VDE10' Then Err(109) Else Begin
          Seek(I, VpxMetaOffset);
          Repeat
            BlockRead(I, DRes1, 4);
            BlockRead(I, DRes2, 4);
            ParseFieldType(DRes1);
          Until ((DRes1 = 0) AND (DRes2 = 0)) OR (Valid = False);
        End;
      End;
    End;

    If (Valid) AND (Compressed) Then Begin
(*
      FillChar(InBuf[0], 2097152, 0);
      BlockRead(I, InBuf[0], VpxControllerSize);
      WriteLn(VpxControllerUncompSize);
      If MyInflate <> 0 Then Err(111);
*)
    End;
    Close(I);

    If Valid Then Begin
      OutName := Title;
      If Version <> '' Then OutName := OutName + ' v' + Version;
      If Year = '' Then Year := '20xx';
      OutName := OutName + ' (' + Year + ')';
      If Vendor <> '' Then OutName := OutName + '(' + Vendor + ')'
      Else OutName := OutName + '(' + Copyright + ')';
      OutName := OutName + '.vpx';
      For Res1 := 1 To Length(OutName) Do If Pos(OutName[Res1], '":\/*?<>|`') > 0 Then OutName[Res1] := '_';
    End
    Else OutName := SourcePath + DirInfo.Name + '.notavpx';
    WriteLn(OutName);
(*
    If NOT FileExists(SourcePath + OutName) Then RenameFile(SourcePath + DirInfo.Name, SourcePath + OutName)
    Else WriteLn(OutName, ' already exists.');
    If IOresult <> 0 Then WriteLn('Error renaming!');
*)

  Until FindNext(DirInfo) <> 0;
  FindClose(DirInfo);
End.
