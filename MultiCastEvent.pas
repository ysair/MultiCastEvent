unit MultiCastEvent;

interface

uses
  System.SysUtils, System.Classes, System.ObjAuto, System.TypInfo,
  Generics.Collections;

type
  TMultiCastEvent = class
  strict private
    type TEvent = procedure of object;
  strict private
    FInternalDispatcher: TMethod; // this class needs to keep it's own reference for cleanup later
    procedure InternalInvoke(Params: PParameters; StackSize: Integer);
    procedure InternalInvokeAMethod(const aMethod: TMethod; const aParams:
        PParameters; aStackSize: Integer);
    procedure ReleaseInternalDispatcher;
    procedure SetDispatcher(var aMethod: TMethod; aTypeData: PTypeData);
  private
    FHandlers: TList<TMethod>;
  protected
    procedure InternalSetDispatcher;
  public
    constructor Create; virtual;
    destructor Destroy; override;
  end;

  TMultiCastEvent<T> = class(TMultiCastEvent)
  strict private
    FInvoke: T;
    procedure SetEventDispatcher(var ADispatcher: T; ATypeData: PTypeData);
  private
    function ConvertToMethod(var Value): TMethod;
  public
    constructor Create; overload; override;
    constructor Create(aEvents: array of T); reintroduce; overload;
    procedure Add(AMethod: T);
    procedure Remove(AMethod: T);
    property Invoke: T read FInvoke;
  end;

implementation

procedure TMultiCastEvent.SetDispatcher(var aMethod: TMethod; aTypeData:
    PTypeData);
begin
  ReleaseInternalDispatcher;
  FInternalDispatcher := CreateMethodPointer(InternalInvoke, aTypeData);
  aMethod := FInternalDispatcher;
end;

constructor TMultiCastEvent.Create;
begin
  inherited;
  FHandlers := TList<TMethod>.Create;
end;

destructor TMultiCastEvent.Destroy;
begin
  ReleaseMethodPointer(FInternalDispatcher);
  FHandlers.Free;
  inherited;
end;

(*procedure TMultiCastEvent.InternalAdd;
asm
{$ifdef Win32}
  xchg  [esp],eax
  pop   eax
  {$ifopt o-}pop   ecx{$ifend}
  pop   ebp
  jmp   Add
{$ifend}
{$ifdef Win64}
  xchg  [rsp],rax
  pop   rax
  lea   rsp,[rbp+$20]
  pop   rbp
  jmp   Add
{$ifend}
end;*)

{procedure TMultiCastEvent.InternalRemove;
asm
  XCHG  EAX,[ESP]
  POP   EAX
  POP   EBP
  JMP   Remove
end;//}

procedure TMultiCastEvent.InternalInvoke(Params: PParameters; StackSize:
    Integer);
var M: TMethod;
begin
  for M in FHandlers do
    if Assigned(M.Code) then
      InternalInvokeAMethod(M, Params, StackSize);
end;

procedure TMultiCastEvent.InternalInvokeAMethod(const aMethod: TMethod; const
    aParams: PParameters; aStackSize: Integer);
var Method_Code: Pointer;
    Method_Data: Pointer;
    Method_Params: PParameters;
    Params_StackSize: Integer;
{$ifdef Win32}
asm
  // store aMethod.Code
  mov eax, aMethod.Code
  mov Method_Code, eax

  // store aMethod.Data
  mov eax, aMethod.Data
  mov Method_Data, eax

  // store aParams
  mov eax, aParams
  mov Method_Params, eax

  // store aStackSize
  mov eax, aStackSize
  mov Params_StackSize, eax

  // Check to see if there is anything in the TParameters.Stack
  cmp Params_StackSize, 0
  jle @InvokeMethod

  // Parameters.Stack has data, allocate a space and move data over.
  // The data are parameters pass to event handler
  sub esp, Params_StackSize     // Allocate storage spaces
  mov eax, Method_Params        // source
  lea eax, [eax].TParameters.Stack
  mov edx, esp                  // destination
  mov ecx, Params_StackSize     // count
  call System.Move

@InvokeMethod:

  // Load parameters to rdx (1st), r8 (2nd) and r9 (3rd).
  // 4th parameters shall loaded in last step
  mov eax, Method_Params
  mov edx, [eax].TParameters.Registers.DWORD[0] // 1st parameter
  mov ecx, [eax].TParameters.Registers.DWORD[4] // 2nd parameter

  // EAX is always "Self", move TMethod.Data to the register
  mov eax, Method_Data

  // Call method
  call Method_Code
end;
{$ifend}

{$ifdef win64}
asm
  // store aMethod.Code
  mov rax, aMethod.Code
  mov Method_Code, rax

  // store aMethod.Data
  mov rax, aMethod.Data
  mov Method_Data, rax

  // store aParams
  mov rax, aParams
  mov Method_Params, rax

  // store aStackSize
  mov Params_StackSize, aStackSize

  // Check to see if there is anything in the TParameters.Stack
  cmp Params_StackSize, 0
  jle @InvokeMethod

  // Parameters.Stack has data, allocate a space and move data over.
  // The data are parameters pass to event handler
  sub esp, Params_StackSize   // Allocate storage spaces
  mov rcx, Method_Params      // source
  lea rcx, [rcx].TParameters.Stack
  mov rdx, rsp                // destination
  mov r8d, Params_StackSize   // count
  call System.Move

@InvokeMethod:

  // Load parameters to rdx (1st), r8 (2nd) and r9 (3rd).
  // 4th parameters shall loaded in last step
  mov rax, Method_Params
  mov rdx, [rax].TParameters.Stack.QWORD[$08]  // 1st parameter
  mov r8,  [rax].TParameters.Stack.QWORD[$10]  // 2nd parameter
  mov r9,  [rax].TParameters.Stack.QWORD[$18]  // 3rd parameter

  // RCX is always "Self", move TMethod.Data to the register
  mov rcx, Method_Data

  // Call method
  call Method_Code
end;
{$ifend}

procedure TMultiCastEvent.InternalSetDispatcher;
asm
{$ifdef Win32}
  xchg  [esp],eax
  pop   eax
  {$ifopt o-}mov esp,ebp{$ifend}
  pop   ebp
  jmp   SetDispatcher
{$ifend}
{$ifdef Win64}
  xchg  [rsp],rax
  pop   rax
  lea   rsp,[rbp+$20]
  pop   rbp
  jmp   SetDispatcher
{$ifend}
end;

procedure TMultiCastEvent.ReleaseInternalDispatcher;
begin
  if Assigned(FInternalDispatcher.Code) and Assigned(FInternalDispatcher.Data) then
    ReleaseMethodPointer(FInternalDispatcher);
end;

procedure TMultiCastEvent<T>.Add(AMethod: T);
var
  m: TMethod;
begin
  m := ConvertToMethod(AMethod);
  if FHandlers.IndexOf(m) < 0 then
    FHandlers.Add(m);
end;

procedure TMultiCastEvent<T>.Remove(AMethod: T);
begin
  FHandlers.Remove(ConvertToMethod(AMethod));
end;

constructor TMultiCastEvent<T>.Create;
var M: PTypeInfo;
    D: PTypeData;
begin
  inherited Create;
  M := TypeInfo(T);
  D := GetTypeData(M);
  Assert(M.Kind = tkMethod, 'T must be a method pointer type');
  SetEventDispatcher(FInvoke, D);
end;

function TMultiCastEvent<T>.ConvertToMethod(var Value): TMethod;
begin
  Result := TMethod(Value);
end;

constructor TMultiCastEvent<T>.Create(aEvents: array of T);
var E: T;
begin
  Create;
  for E in aEvents do Add(E);
end;

procedure TMultiCastEvent<T>.SetEventDispatcher(var ADispatcher: T; ATypeData:
    PTypeData);
begin
  InternalSetDispatcher;
end;

end.
