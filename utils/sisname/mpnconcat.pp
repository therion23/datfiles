Program Mophun_Concatenator;

Uses
  DOS,
  SysUtils;

Var
  buf: Array[0..4194303] Of Byte;
  nr: UInt32;

  i,
  o: File;

  s1,
  s2: String;

  c: Char;

Begin
  s1 := ParamStr(1);
  If (s1[1] < '1') Or (s1[1] > '9') Or (s1[3] < '1') Or (s1[3] > '9') Then Begin
    WriteLn('Invalid naming scheme');
    Halt(2);
  End;
  s2 := s1;
  For c := '1' to s1[3] Do Begin
    s2[1] := c;
    WriteLn(s2);
    If Not FileExists(s2) Then Begin
      WriteLn('Incomplete set');
      Halt(3);
    End;
  End;
  Delete(s2, 1, 4);
  Assign(o, s2);
  Rewrite(o, 1);
  s2 := s1;
  For c := '1' to s1[3] Do Begin
    s1[1] := c;
    Assign(i, s1);
    Reset(i, 1);
    BlockRead(i, buf[0], 4194304, nr);
    BlockWrite(o, buf[0], nr);
    Close(i);
  End;
  Close(o);
End.
