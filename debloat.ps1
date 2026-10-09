#requires -Version 5.1

<#
===========================================================================
 Aplicador de Políticas - Windows 10 / Windows 11
 --------------------------------------------------------------------------
 - Menu para seleção da versão do Windows
 - Detecção da versão instalada
 - Backup das chaves de política antes das alterações
 - Gravação das políticas na Política de Grupo Local (Registry.pol), como o gpedit.msc
 - Verificação individual após cada alteração
 - Status visual:
       [OK]       = valor gravado e conferido
       [AVISO]    = política aplicada, mas dependente de versão/ADMX
       [FALHOU]   = não foi possível gravar/conferir
       [IGNORADO] = incompatível com a versão selecionada
 - Não desabilita serviços nem remove componentes do Windows.
===========================================================================

 ATENÇÃO:
 Algumas políticas do Windows são ADMX-backed. Nesses casos, a Microsoft
 pode alterar o suporte entre builds. O script grava o mapeamento de
 Registro conhecido, mas não promete que uma política obsoleta terá efeito
 em uma build que não a suporta.

 Recomenda-se reiniciar o Windows ao terminar.
#>

# -------------------------------------------------------------------------
# CODIFICAÇÃO (UTF-8)
# -------------------------------------------------------------------------
# O Windows PowerShell 5.1 lê arquivos .ps1 SEM BOM como ANSI (Windows-1252),
# o que corrompe acentos. Este arquivo deve ser salvo como "UTF-8 com BOM".
# A guarda abaixo usa só ASCII na mensagem para ser legível mesmo se falhar.
$__encProbe = 'ç'
if ($__encProbe.Length -ne 1) {
    Write-Host ""
    Write-Host "ERRO: este arquivo foi lido com a codificacao errada." -ForegroundColor Red
    Write-Host "Salve o .ps1 como 'UTF-8 com BOM' (UTF-8 with BOM) e execute novamente." -ForegroundColor Yellow
    Read-Host "Pressione ENTER para sair"
    exit 1
}
Remove-Variable __encProbe

try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding           = [System.Text.Encoding]::UTF8
}
catch {
    # Hosts sem console (ex.: ISE) podem recusar; a exibição segue com o padrão.
}

# -------------------------------------------------------------------------
# CONFIGURAÇÃO VISUAL
# -------------------------------------------------------------------------

$ErrorActionPreference = "Stop"

trap {
    Write-Host ""
    Write-Host "ERRO FATAL: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.InvocationInfo) {
        Write-Host "Linha $($_.InvocationInfo.ScriptLineNumber): $($_.InvocationInfo.Line.Trim())" -ForegroundColor DarkRed
    }
    Read-Host "Pressione ENTER para sair"
    exit 1
}

function Write-Header {
    Clear-Host
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "       APLICADOR DE POLÍTICAS - WINDOWS 10 / 11" -ForegroundColor White
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Status {
    param(
        [ValidateSet("OK","WARN","FAIL","SKIP","INFO")]
        [string]$Status,
        [string]$Message
    )

    switch ($Status) {
        "OK"   {
            Write-Host "[OK]       $Message" -ForegroundColor Green
        }
        "WARN" {
            Write-Host "[AVISO]    $Message" -ForegroundColor Yellow
        }
        "FAIL" {
            Write-Host "[FALHOU]   $Message" -ForegroundColor Red
        }
        "SKIP" {
            Write-Host "[IGNORADO] $Message" -ForegroundColor DarkGray
        }
        "INFO" {
            Write-Host "[INFO]     $Message" -ForegroundColor Cyan
        }
    }
}

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)

    return $principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}

# -------------------------------------------------------------------------
# ELEVAÇÃO
# -------------------------------------------------------------------------

if (-not (Test-Administrator)) {

    Write-Host ""
    Write-Host "Este script precisa ser executado como Administrador." -ForegroundColor Yellow
    Write-Host "Tentando solicitar elevação..." -ForegroundColor Yellow
    Write-Host ""

    if ([string]::IsNullOrWhiteSpace($PSCommandPath)) {
        Write-Host "Salve o script em um arquivo .ps1 e execute-o a partir dele (ou abra o PowerShell como Administrador)." -ForegroundColor Red
        Read-Host "Pressione ENTER para sair"
        exit 1
    }

    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""

    try {
        Start-Process powershell.exe `
            -Verb RunAs `
            -ArgumentList $arguments

        exit
    }
    catch {
        Write-Host "Não foi possível solicitar elevação." -ForegroundColor Red
        Read-Host "Pressione ENTER para sair"
        exit 1
    }
}

# -------------------------------------------------------------------------
# DETECÇÃO DO WINDOWS
# -------------------------------------------------------------------------

$os = Get-CimInstance Win32_OperatingSystem

$ActualBuild = [int]$os.BuildNumber
$ActualCaption = $os.Caption
$ActualVersion = $os.Version

Write-Header

Write-Host "Windows detectado:" -ForegroundColor Cyan
Write-Host "  Produto : $ActualCaption"
Write-Host "  Versão  : $ActualVersion"
Write-Host "  Build   : $ActualBuild"
Write-Host ""

# -------------------------------------------------------------------------
# MENU
# -------------------------------------------------------------------------

Write-Host "Selecione a versão que será utilizada como referência:" -ForegroundColor White
Write-Host ""
Write-Host "  [1] Windows 10 - 21H2 / 22H2"
Write-Host "  [2] Windows 11 - 21H2"
Write-Host "  [3] Windows 11 - 22H2"
Write-Host "  [4] Windows 11 - 23H2"
Write-Host "  [5] Windows 11 - 24H2"
Write-Host "  [6] Windows 11 - 25H2"
Write-Host "  [7] Detectar automaticamente"
Write-Host ""

$choice = Read-Host "Escolha"

switch ($choice) {

    "1" {
        $TargetWindows = "Windows 10"
        $TargetBuildMin = 19044
    }

    "2" {
        $TargetWindows = "Windows 11 21H2"
        $TargetBuildMin = 22000
    }

    "3" {
        $TargetWindows = "Windows 11 22H2"
        $TargetBuildMin = 22621
    }

    "4" {
        $TargetWindows = "Windows 11 23H2"
        $TargetBuildMin = 22631
    }

    "5" {
        $TargetWindows = "Windows 11 24H2"
        $TargetBuildMin = 26100
    }

    "6" {
        $TargetWindows = "Windows 11 25H2"
        # Build base esperada para 25H2.
        # O script não depende exclusivamente deste número.
        $TargetBuildMin = 26200
    }

    "7" {
        if ($ActualBuild -ge 26200) {
            $TargetWindows = "Windows 11 25H2"
            $TargetBuildMin = 26200
        }
        elseif ($ActualBuild -ge 26100) {
            $TargetWindows = "Windows 11 24H2"
            $TargetBuildMin = 26100
        }
        elseif ($ActualBuild -ge 22631) {
            $TargetWindows = "Windows 11 23H2"
            $TargetBuildMin = 22631
        }
        elseif ($ActualBuild -ge 22621) {
            $TargetWindows = "Windows 11 22H2"
            $TargetBuildMin = 22621
        }
        elseif ($ActualBuild -ge 22000) {
            $TargetWindows = "Windows 11 21H2"
            $TargetBuildMin = 22000
        }
        else {
            $TargetWindows = "Windows 10"
            $TargetBuildMin = 19044
        }
    }

    default {
        Write-Host "Opção inválida." -ForegroundColor Red
        Read-Host "Pressione ENTER para sair"
        exit 1
    }
}

Write-Host ""
Write-Status INFO "Perfil selecionado: $TargetWindows"
Write-Host ""

if ($ActualBuild -lt $TargetBuildMin) {
    Write-Status WARN "A build instalada ($ActualBuild) é inferior à build de referência ($TargetBuildMin)."
    Write-Status WARN "Algumas políticas poderão ser ignoradas."
    Write-Host ""
}

# -------------------------------------------------------------------------
# CONFIRMAÇÃO
# -------------------------------------------------------------------------

Write-Host "As políticas serão gravadas na Política de Grupo Local (o que o gpedit.msc exibe):" -ForegroundColor Yellow
Write-Host "  %SystemRoot%\System32\GroupPolicy\Machine\Registry.pol"
Write-Host "  %SystemRoot%\System32\GroupPolicy\User\Registry.pol"
Write-Host ""
Write-Host "Será criado um backup antes das alterações." -ForegroundColor Yellow
Write-Host ""

$confirm = Read-Host "Continuar? [S/N]"

if ($confirm -notmatch "^[SsYy]$") {
    Write-Host "Operação cancelada." -ForegroundColor Yellow
    exit
}

# -------------------------------------------------------------------------
# DIRETÓRIO DE BACKUP
# -------------------------------------------------------------------------

$DesktopDir = [Environment]::GetFolderPath("Desktop")

if ([string]::IsNullOrWhiteSpace($DesktopDir)) {
    $DesktopDir = Join-Path $env:USERPROFILE "Desktop"
}

$BackupDir = Join-Path $DesktopDir "Backup-Politicas-Windows"

if (-not (Test-Path $BackupDir)) {
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
}

$Timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"

Write-Status INFO "Criando backup..."

# Todas as chaves que o script altera. Se a chave ainda não existir,
# não há o que salvar (o reg.exe retorna erro, tratado abaixo).
$BackupKeys = @(
    @{ Key = "HKLM\SOFTWARE\Policies\Microsoft";                                  Tag = "HKLM-Policies-Microsoft" },
    @{ Key = "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"; Tag = "HKLM-Policies-Explorer" },
    @{ Key = "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"; Tag = "HKCU-Policies-Explorer" }
)

foreach ($item in $BackupKeys) {

    $file = Join-Path $BackupDir ("{0}-{1}.reg" -f $item.Tag, $Timestamp)

    try {
        # Start-Process evita que o stderr do reg.exe vire erro fatal
        # com $ErrorActionPreference = "Stop".
        $p = Start-Process -FilePath "reg.exe" `
            -ArgumentList @("export", "`"$($item.Key)`"", "`"$file`"", "/y") `
            -Wait -PassThru -WindowStyle Hidden

        if ($p.ExitCode -eq 0 -and (Test-Path $file)) {
            Write-Status OK "Backup criado: $file"
        }
        else {
            Write-Status INFO "Chave ainda não existe (nada a salvar): $($item.Key)"
        }
    }
    catch {
        Write-Status WARN "Não foi possível exportar: $($item.Key)"
    }
}

# -------------------------------------------------------------------------
# BACKUP DA POLÍTICA LOCAL (Registry.pol / gpt.ini)
# -------------------------------------------------------------------------

$GroupPolicyDir = Join-Path (Join-Path $env:SystemRoot "System32") "GroupPolicy"

$PolFiles = @{
    Machine = Join-Path (Join-Path $GroupPolicyDir "Machine") "Registry.pol"
    User    = Join-Path (Join-Path $GroupPolicyDir "User") "Registry.pol"
}

$GptIniFile = Join-Path $GroupPolicyDir "gpt.ini"

foreach ($src in @($PolFiles.Machine, $PolFiles.User, $GptIniFile)) {

    if (Test-Path -LiteralPath $src -PathType Leaf) {

        $tag = (Split-Path $src -Parent | Split-Path -Leaf) + "-" + (Split-Path $src -Leaf)
        $dst = Join-Path $BackupDir ("GroupPolicy-{0}-{1}.bak" -f $tag, $Timestamp)

        try {
            Copy-Item -LiteralPath $src -Destination $dst -Force
            Write-Status OK "Backup criado: $dst"
        }
        catch {
            Write-Status WARN "Não foi possível copiar: $src"
        }
    }
}

# -------------------------------------------------------------------------
# MOTOR DE POLÍTICA LOCAL (Registry.pol + ADMX)
# -------------------------------------------------------------------------
# Por que não gravar direto em HKLM\SOFTWARE\Policies?
#  - O gpedit.msc só exibe o que está no Registry.pol da política local.
#  - O "gpupdate /force" recria as chaves de política a partir do Registry.pol
#    e APAGA o que foi gravado direto no registro.
# Por isso as políticas são gravadas no Registry.pol. A codificação de
# Habilitada/Desabilitada é lida dos ADMX do próprio Windows, exatamente
# como o gpedit faz.

$PolicyDefinitionsDir = Join-Path $env:SystemRoot "PolicyDefinitions"

$Results = New-Object System.Collections.Generic.List[object]

function Add-Result {
    param(
        [string]$Policy,
        [string]$Status,
        [string]$Registry,
        $Value,
        [string]$Observation
    )

    $Results.Add([PSCustomObject]@{
        Politica   = $Policy
        Status     = $Status
        Registro   = $Registry
        Valor      = $Value
        Observacao = $Observation
    })
}

function ConvertTo-NormalKey {
    param([string]$Key)
    return $Key.Trim("\").ToLowerInvariant()
}

# --- Leitura dos ADMX ----------------------------------------------------

function ConvertFrom-AdmxValue {
    param($Node)

    if ($null -eq $Node) { return $null }

    $n = $Node.SelectSingleNode("*[local-name()='decimal']")
    if ($n) { return @{ Kind = "dword"; Value = [uint32]$n.GetAttribute("value") } }

    $n = $Node.SelectSingleNode("*[local-name()='longDecimal']")
    if ($n) { return @{ Kind = "qword"; Value = [uint64]$n.GetAttribute("value") } }

    $n = $Node.SelectSingleNode("*[local-name()='string']")
    if ($n) { return @{ Kind = "string"; Value = [string]$n.InnerText } }

    $n = $Node.SelectSingleNode("*[local-name()='delete']")
    if ($n) { return @{ Kind = "delete"; Value = $null } }

    return $null
}

function ConvertFrom-AdmxList {
    param($Node, [string]$DefaultKey)

    $items = @()

    if ($null -ne $Node) {
        foreach ($i in $Node.SelectNodes("*[local-name()='item']")) {

            $k = $i.GetAttribute("key")
            if ([string]::IsNullOrEmpty($k)) { $k = $DefaultKey }

            $items += [PSCustomObject]@{
                Key       = $k
                ValueName = $i.GetAttribute("valueName")
                Value     = (ConvertFrom-AdmxValue $i.SelectSingleNode("*[local-name()='value']"))
            }
        }
    }

    return ,$items
}

function Get-AdmxPolicies {
    param([string[]]$Keys)

    $wanted = @{}
    foreach ($k in $Keys) { $wanted[(ConvertTo-NormalKey $k)] = $true }

    $found = New-Object System.Collections.Generic.List[object]

    if (-not (Test-Path -LiteralPath $PolicyDefinitionsDir)) { return ,$found }

    foreach ($file in Get-ChildItem -LiteralPath $PolicyDefinitionsDir -Filter "*.admx" -File) {

        $xml = New-Object System.Xml.XmlDocument

        try { $xml.Load($file.FullName) }
        catch { continue }

        foreach ($p in $xml.SelectNodes("//*[local-name()='policy']")) {

            $key = $p.GetAttribute("key")

            if (-not $wanted.ContainsKey((ConvertTo-NormalKey $key))) { continue }

            $elements = @()

            foreach ($e in $p.SelectNodes("*[local-name()='elements']/*")) {

                $ek = $e.GetAttribute("key")
                if ([string]::IsNullOrEmpty($ek)) { $ek = $key }

                $elements += [PSCustomObject]@{
                    Type       = $e.LocalName
                    Id         = $e.GetAttribute("id")
                    ValueName  = $e.GetAttribute("valueName")
                    Key        = $ek
                    TrueValue  = (ConvertFrom-AdmxValue $e.SelectSingleNode("*[local-name()='trueValue']"))
                    FalseValue = (ConvertFrom-AdmxValue $e.SelectSingleNode("*[local-name()='falseValue']"))
                }
            }

            $found.Add([PSCustomObject]@{
                File         = $file.Name
                Name         = $p.GetAttribute("name")
                Class        = $p.GetAttribute("class")
                Key          = $key
                ValueName    = $p.GetAttribute("valueName")
                Enabled      = (ConvertFrom-AdmxValue $p.SelectSingleNode("*[local-name()='enabledValue']"))
                Disabled     = (ConvertFrom-AdmxValue $p.SelectSingleNode("*[local-name()='disabledValue']"))
                EnabledList  = (ConvertFrom-AdmxList $p.SelectSingleNode("*[local-name()='enabledList']") $key)
                DisabledList = (ConvertFrom-AdmxList $p.SelectSingleNode("*[local-name()='disabledList']") $key)
                Elements     = $elements
            })
        }
    }

    return ,$found
}

function Find-AdmxPolicy {
    param($Spec, $Index)

    $nk = ConvertTo-NormalKey $Spec.Key

    $sameKey = New-Object System.Collections.Generic.List[object]

    foreach ($pol in $Index) {
        if ((ConvertTo-NormalKey $pol.Key) -ne $nk) { continue }
        if ($pol.Class -ne $Spec.Class -and $pol.Class -ne "Both") { continue }
        $sameKey.Add($pol)
    }

    $hits = New-Object System.Collections.Generic.List[object]

    foreach ($pol in $sameKey) {

        $match = ($pol.ValueName -ieq $Spec.ValueName)

        if (-not $match) {
            foreach ($el in $pol.Elements) {
                if ($el.ValueName -ieq $Spec.ValueName) { $match = $true; break }
            }
        }

        if ($match) { $hits.Add($pol) }
    }

    # Alternativa: procura por trecho do nome quando o valor exato não existe.
    if ($hits.Count -eq 0 -and $Spec.ContainsKey("ValueLike")) {
        foreach ($pol in $sameKey) {
            if (($pol.Name -match $Spec.ValueLike) -or ($pol.ValueName -match $Spec.ValueLike)) {
                $hits.Add($pol)
            }
        }
    }

    $chosen = $null

    if ($hits.Count -ge 1) {
        $chosen = $hits[0]
        foreach ($h in $hits) {
            if ($h.Class -eq $Spec.Class) { $chosen = $h; break }
        }
    }

    return [PSCustomObject]@{
        Policy  = $chosen
        SameKey = $sameKey
        Hits    = $hits.Count
    }
}

# --- Geração das entradas (igual ao gpedit) ------------------------------

function New-Entry {
    param([string]$Key, [string]$Name, $Val)

    return [PSCustomObject]@{
        Key   = $Key
        Name  = $Name
        Kind  = $Val.Kind
        Value = $Val.Value
    }
}

function New-PolicyEntries {
    param($Policy, $Spec)

    $entries = New-Object System.Collections.Generic.List[object]

    if ($Spec.State -eq "Enabled") {

        if (-not [string]::IsNullOrEmpty($Policy.ValueName)) {

            $v = $Policy.Enabled
            if ($null -eq $v) { $v = @{ Kind = "dword"; Value = [uint32]1 } }

            $entries.Add((New-Entry $Policy.Key $Policy.ValueName $v))
        }

        foreach ($it in $Policy.EnabledList) {
            if ($null -ne $it.Value) {
                $entries.Add((New-Entry $it.Key $it.ValueName $it.Value))
            }
        }

        if ($Spec.Elements -is [hashtable]) {

            foreach ($name in @($Spec.Elements.Keys)) {

                $el = $null

                foreach ($candidate in $Policy.Elements) {
                    if (($candidate.ValueName -ieq $name) -or ($candidate.Id -ieq $name)) {
                        $el = $candidate
                        break
                    }
                }

                if ($null -eq $el) {
                    throw "O elemento '$name' não existe na política '$($Policy.Name)'."
                }

                $raw = $Spec.Elements[$name]

                if ($raw -is [bool]) {
                    if ($raw) { $val = $el.TrueValue } else { $val = $el.FalseValue }
                    if ($null -eq $val) { $val = @{ Kind = "dword"; Value = [uint32]([int]$raw) } }
                }
                elseif ($raw -is [string]) {
                    $val = @{ Kind = "string"; Value = $raw }
                }
                else {
                    $val = @{ Kind = "dword"; Value = [uint32]$raw }
                }

                $entries.Add((New-Entry $el.Key $el.ValueName $val))
            }
        }
    }
    else {

        if (-not [string]::IsNullOrEmpty($Policy.ValueName)) {

            $v = $Policy.Disabled
            if ($null -eq $v) { $v = @{ Kind = "delete"; Value = $null } }

            $entries.Add((New-Entry $Policy.Key $Policy.ValueName $v))
        }

        foreach ($it in $Policy.DisabledList) {
            if ($null -ne $it.Value) {
                $entries.Add((New-Entry $it.Key $it.ValueName $it.Value))
            }
        }

        foreach ($el in $Policy.Elements) {
            if (-not [string]::IsNullOrEmpty($el.ValueName)) {
                $entries.Add((New-Entry $el.Key $el.ValueName @{ Kind = "delete"; Value = $null }))
            }
        }
    }

    return ,$entries
}

function Format-PolEntry {
    param($Entry)

    if ($Entry.Kind -eq "delete") {
        return "{0} = (removido; 'Não configurado' no registro)" -f $Entry.Name
    }

    return "{0} = {1}" -f $Entry.Name, $Entry.Value
}

# --- Formato Registry.pol (PReg) -----------------------------------------

function ConvertTo-PolRecord {
    param($Entry)

    $name = $Entry.Name

    switch ($Entry.Kind) {
        "dword"  { $type = 4;  $data = [BitConverter]::GetBytes([uint32]$Entry.Value) }
        "qword"  { $type = 11; $data = [BitConverter]::GetBytes([uint64]$Entry.Value) }
        "string" { $type = 1;  $data = [byte[]]([Text.Encoding]::Unicode.GetBytes([string]$Entry.Value) + [byte[]](0, 0)) }
        "delete" { $type = 1;  $name = "**del." + $Entry.Name; $data = [byte[]](0x20, 0x00, 0x00, 0x00) }
        default  { throw "Tipo de valor desconhecido: $($Entry.Kind)" }
    }

    return [PSCustomObject]@{
        Key   = $Entry.Key
        Value = $name
        Type  = [uint32]$type
        Data  = [byte[]]$data
    }
}

function Read-PolFile {
    param([string]$Path)

    $list = New-Object System.Collections.Generic.List[object]

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return ,$list }

    $b = [IO.File]::ReadAllBytes($Path)

    if ($b.Length -eq 0) { return ,$list }

    if ($b.Length -lt 8 -or [BitConverter]::ToUInt32($b, 0) -ne 0x67655250 -or [BitConverter]::ToUInt32($b, 4) -ne 1) {
        throw "Formato inesperado em $Path (não é um Registry.pol válido). Nada foi alterado."
    }

    $i = 8

    try {
        while ($i -lt $b.Length) {

            if ([BitConverter]::ToUInt16($b, $i) -ne 0x5B) { throw "esperado '['" }
            $i += 2

            $s = $i
            while ([BitConverter]::ToUInt16($b, $i) -ne 0) { $i += 2 }
            $key = [Text.Encoding]::Unicode.GetString($b, $s, $i - $s)
            $i += 2

            if ([BitConverter]::ToUInt16($b, $i) -ne 0x3B) { throw "esperado ';'" }
            $i += 2

            $s = $i
            while ([BitConverter]::ToUInt16($b, $i) -ne 0) { $i += 2 }
            $val = [Text.Encoding]::Unicode.GetString($b, $s, $i - $s)
            $i += 2

            if ([BitConverter]::ToUInt16($b, $i) -ne 0x3B) { throw "esperado ';'" }
            $i += 2

            $type = [BitConverter]::ToUInt32($b, $i)
            $i += 4

            if ([BitConverter]::ToUInt16($b, $i) -ne 0x3B) { throw "esperado ';'" }
            $i += 2

            $size = [BitConverter]::ToUInt32($b, $i)
            $i += 4

            if ([BitConverter]::ToUInt16($b, $i) -ne 0x3B) { throw "esperado ';'" }
            $i += 2

            if ($i + $size -gt $b.Length) { throw "tamanho de dados inválido" }

            $data = New-Object byte[] $size
            [Array]::Copy($b, $i, $data, 0, $size)
            $i += $size

            if ([BitConverter]::ToUInt16($b, $i) -ne 0x5D) { throw "esperado ']'" }
            $i += 2

            $list.Add([PSCustomObject]@{
                Key   = $key
                Value = $val
                Type  = [uint32]$type
                Data  = [byte[]]$data
            })
        }
    }
    catch {
        throw "Registry.pol corrompido ou em formato inesperado ($Path): $($_.Exception.Message). Nada foi alterado."
    }

    return ,$list
}

function Write-PolFile {
    param([string]$Path, $Records)

    $ms = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter($ms)

    $bw.Write([byte[]](0x50, 0x52, 0x65, 0x67))
    $bw.Write([uint32]1)

    foreach ($r in $Records) {

        $bw.Write([uint16]0x5B)
        $bw.Write([byte[]][Text.Encoding]::Unicode.GetBytes($r.Key))
        $bw.Write([uint16]0)
        $bw.Write([uint16]0x3B)
        $bw.Write([byte[]][Text.Encoding]::Unicode.GetBytes($r.Value))
        $bw.Write([uint16]0)
        $bw.Write([uint16]0x3B)
        $bw.Write([uint32]$r.Type)
        $bw.Write([uint16]0x3B)
        $bw.Write([uint32]$r.Data.Length)
        $bw.Write([uint16]0x3B)
        $bw.Write([byte[]]$r.Data)
        $bw.Write([uint16]0x5D)
    }

    $bw.Flush()
    $bytes = $ms.ToArray()
    $bw.Close()

    # Grava em arquivo temporário e só então substitui o original.
    $tmp = "$Path.tmp"
    [IO.File]::WriteAllBytes($tmp, $bytes)

    $attr = $null

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        $fi = Get-Item -LiteralPath $Path -Force
        $attr = $fi.Attributes
        $fi.Attributes = [IO.FileAttributes]::Normal
    }

    [IO.File]::Copy($tmp, $Path, $true)
    Remove-Item -LiteralPath $tmp -Force

    if ($null -ne $attr) {
        (Get-Item -LiteralPath $Path -Force).Attributes = $attr
    }
}

function Get-PolBaseName {
    param([string]$Name)

    if ($Name.StartsWith("**del.", [StringComparison]::OrdinalIgnoreCase)) {
        return $Name.Substring(6)
    }

    return $Name
}

function Merge-PolRecords {
    param($Existing, $New)

    $result = New-Object System.Collections.Generic.List[object]

    foreach ($r in $Existing) {

        $drop = $false

        foreach ($n in $New) {
            if (($r.Key -ieq $n.Key) -and ((Get-PolBaseName $r.Value) -ieq (Get-PolBaseName $n.Value))) {
                $drop = $true
                break
            }
        }

        if (-not $drop) { $result.Add($r) }
    }

    foreach ($n in $New) { $result.Add($n) }

    return ,$result
}

function Update-GptIni {
    param([bool]$MachineChanged, [bool]$UserChanged)

    $cse   = "{35378EAC-683F-11D2-A89A-00C04FBBCFA2}"
    $toolM = "{D02B1F72-3407-48AE-BA88-E8213C6761F1}"
    $toolU = "{D02B1F73-3407-48AE-BA88-E8213C6761F1}"

    $lines = New-Object System.Collections.Generic.List[string]

    if (Test-Path -LiteralPath $GptIniFile -PathType Leaf) {
        foreach ($l in [IO.File]::ReadAllLines($GptIniFile)) { $lines.Add($l) }
    }

    if ($lines.Count -eq 0) { $lines.Add("[General]") }

    $mIdx = -1
    $uIdx = -1

    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match "^\s*gPCMachineExtensionNames\s*=") { $mIdx = $i }
        elseif ($lines[$i] -match "^\s*gPCUserExtensionNames\s*=") { $uIdx = $i }
    }

    if ($MachineChanged) {
        if ($mIdx -ge 0) {
            if ($lines[$mIdx] -notmatch [regex]::Escape($cse)) {
                $lines[$mIdx] = $lines[$mIdx].TrimEnd() + "[" + $cse + $toolM + "]"
            }
        }
        else {
            $lines.Insert(1, "gPCMachineExtensionNames=[" + $cse + $toolM + "]")
            if ($uIdx -ge 0) { $uIdx++ }
        }
    }

    if ($UserChanged) {
        if ($uIdx -ge 0) {
            if ($lines[$uIdx] -notmatch [regex]::Escape($cse)) {
                $lines[$uIdx] = $lines[$uIdx].TrimEnd() + "[" + $cse + $toolU + "]"
            }
        }
        else {
            $lines.Insert(1, "gPCUserExtensionNames=[" + $cse + $toolU + "]")
        }
    }

    $version = [int64]0
    $vIdx = -1

    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match "^\s*Version\s*=\s*(\d+)") {
            $version = [int64]$Matches[1]
            $vIdx = $i
        }
    }

    $machine = [int]($version -band 0xFFFF)
    $user    = [int](($version -shr 16) -band 0xFFFF)

    if ($MachineChanged) { $machine = ($machine + 1) -band 0xFFFF }
    if ($UserChanged)    { $user    = ($user + 1) -band 0xFFFF }

    $newVersion = (([int64]$user) -shl 16) -bor ([int64]$machine)
    $verLine = "Version=$newVersion"

    if ($vIdx -ge 0) { $lines[$vIdx] = $verLine } else { $lines.Add($verLine) }

    $attr = $null

    if (Test-Path -LiteralPath $GptIniFile -PathType Leaf) {
        $fi = Get-Item -LiteralPath $GptIniFile -Force
        $attr = $fi.Attributes
        $fi.Attributes = [IO.FileAttributes]::Normal
    }

    [IO.File]::WriteAllLines($GptIniFile, $lines.ToArray(), [Text.Encoding]::ASCII)

    if ($null -ne $attr) {
        (Get-Item -LiteralPath $GptIniFile -Force).Attributes = $attr
    }
}

# -------------------------------------------------------------------------
# POLÍTICAS SOLICITADAS
# -------------------------------------------------------------------------
# State = "Enabled"  -> política "Habilitada" no gpedit
# State = "Disabled" -> política "Desabilitada" no gpedit
# Elements          -> valor de elementos (listas/caixas) da política

$W = "SOFTWARE\Policies\Microsoft\Windows"

$Specs = @(

    # 1. Coleta de Dados e Compilações de Visualização
    @{ Name = "Permitir pipeline de dados comerciais = Desabilitar"
       Class = "Machine"; Key = "$W\DataCollection"; ValueName = "AllowCommercialDataPipeline"; State = "Disabled"
       Note = "Política obsoleta: a Microsoft informa que não tem mais efeito nas builds atuais." },

    @{ Name = "Permitir dados de diagnóstico = Desabilitar"
       Class = "Machine"; Key = "$W\DataCollection"; ValueName = "AllowTelemetry"; State = "Disabled"
       Note = "'Desabilitada' equivale a 'Não configurada' na prática (coleta padrão). Para reduzir a coleta de fato seria 'Habilitada' + 'Diagnostic data off' (só Enterprise/Education)." },

    # 2. Compatibilidade de Aplicativos
    @{ Name = "Desativar Telemetria de Aplicativos = Habilitar"
       Class = "Machine"; Key = "$W\AppCompat"; ValueName = "AITEnable"; State = "Enabled" },

    @{ Name = "Desativar o Mecanismo de Compatibilidade de Aplicativos = Habilitar"
       Class = "Machine"; Key = "$W\AppCompat"; ValueName = "DisableEngine"; State = "Enabled"
       Note = "Pode reduzir a compatibilidade de aplicativos antigos." },

    @{ Name = "Desativar o Auxiliar de Compatibilidade de Programa = Habilitar"
       Class = "Machine"; Key = "$W\AppCompat"; ValueName = "DisablePCA"; State = "Enabled" },

    @{ Name = "Desativar o Coletor de Inventário = Habilitar"
       Class = "Machine"; Key = "$W\AppCompat"; ValueName = "DisableInventory"; State = "Enabled" },

    @{ Name = "Desativar o Mecanismo de Compatibilidade de SwitchBack = Habilitar"
       Class = "Machine"; Key = "$W\AppCompat"; ValueName = "SbEnable"; State = "Enabled" },

    @{ Name = "Desativar o Gravador de Passos = Habilitar"
       Class = "Machine"; Key = "$W\AppCompat"; ValueName = "DisableUAR"; State = "Enabled" },

    # 3. Conteúdo de Nuvem
    @{ Name = "Desativar o conteúdo otimizado em nuvem = Habilitar"
       Class = "Machine"; Key = "$W\CloudContent"; ValueName = "DisableCloudOptimizedContent"; State = "Enabled" },

    @{ Name = "Desligue o conteúdo do estado de conta do consumidor = Habilitar"
       Class = "Machine"; Key = "$W\CloudContent"; ValueName = "DisableConsumerAccountStateContent"; State = "Enabled" },

    @{ Name = "Desativar tela de fixação do Copilot = Habilitar"
       Class = "Machine"; Key = "$W\CloudContent"; ValueName = "DisableCopilotPinScreen"; ValueLike = "Copilot"; State = "Enabled" },

    @{ Name = "Não mostrar dicas do Windows = Habilitar"
       Class = "Machine"; Key = "$W\CloudContent"; ValueName = "DisableSoftLanding"; State = "Enabled" },

    @{ Name = "Desativar as experiências do cliente da Microsoft = Habilitar"
       Class = "Machine"; Key = "$W\CloudContent"; ValueName = "DisableWindowsConsumerFeatures"; State = "Enabled"
       Note = "Documentada pela Microsoft principalmente para Enterprise/Education." },

    # 4. Controle por voz
    @{ Name = "Permitir a Atualização Automática de Dados de Fala = Desabilitar"
       Class = "Machine"; Key = "SOFTWARE\Policies\Microsoft\Speech"; ValueName = "AllowSpeechModelUpdate"; State = "Disabled" },

    # 5. Local e sensores
    @{ Name = "Desativar local = Habilitar"
       Class = "Machine"; Key = "$W\LocationAndSensors"; ValueName = "DisableLocation"; State = "Enabled" },

    @{ Name = "Desativar sensores = Habilitar"
       Class = "Machine"; Key = "$W\LocationAndSensors"; ValueName = "DisableSensors"; State = "Enabled" },

    # 6. Microsoft Edge (legado)
    @{ Name = "Edge: iniciar e carregar a página Inicial e Nova Guia na inicialização = Desabilitar"
       Class = "Machine"; Key = "SOFTWARE\Policies\Microsoft\MicrosoftEdge\TabPreloader"; ValueName = "AllowTabPreloading"; State = "Disabled"
       Note = "Vale para o Edge legado (EdgeHTML); o Edge Chromium usa outras políticas." },

    @{ Name = "Edge: pré-inicialização do Microsoft Edge = Desabilitar"
       Class = "Machine"; Key = "SOFTWARE\Policies\Microsoft\MicrosoftEdge\Main"; ValueName = "AllowPrelaunch"; State = "Disabled"
       Note = "Vale para o Edge legado (EdgeHTML); o Edge Chromium usa outras políticas." },

    # 7. Pesquisar
    @{ Name = "Permitir Cortana = Desabilitar"
       Class = "Machine"; Key = "$W\Windows Search"; ValueName = "AllowCortana"; State = "Disabled" },

    @{ Name = "Permitir pesquisa na nuvem = Desabilitar"
       Class = "Machine"; Key = "$W\Windows Search"; ValueName = "AllowCloudSearch"; State = "Disabled" },

    @{ Name = "Permitir destaques de pesquisa = Desabilitar"
       Class = "Machine"; Key = "$W\Windows Search"; ValueName = "EnableDynamicContentInWSB"; State = "Disabled" },

    @{ Name = "Sempre usar a detecção automática de idioma = Desabilitar"
       Class = "Machine"; Key = "$W\Windows Search"; ValueName = "AlwaysUseAutoLangDetection"; State = "Disabled" },

    @{ Name = "Impedir a indexação ao utilizar a bateria = Habilitar"
       Class = "Machine"; Key = "$W\Windows Search"; ValueName = "PreventIndexOnBattery"; State = "Enabled" },

    # 8. Privacidade de Aplicativos
    @{ Name = "Aplicativos do Windows em segundo plano = Habilitar e forçar negação"
       Class = "Machine"; Key = "$W\AppPrivacy"; ValueName = "LetAppsRunInBackground"; State = "Enabled"
       Elements = @{ LetAppsRunInBackground = 2 } },

    # 9. Sincronizar suas configurações
    @{ Name = "Não sincronizar = Habilitar"
       Class = "Machine"; Key = "$W\SettingSync"; ValueName = "DisableSettingSync"; State = "Enabled"
       Elements = @{ DisableSettingSyncUserOverride = 1 }
       Note = "Valor 1 em DisableSettingSyncUserOverride impede o usuário de reativar a sincronização." },

    # 10. Menu Iniciar e Barra de Tarefas (Configuração do Computador)
    @{ Name = "Não manter histórico de documentos abertos recentemente = Habilitar"
       Class = "Machine"; Key = "SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"; ValueName = "NoRecentDocsHistory"; State = "Enabled" },

    # 11. Perfis de usuário
    @{ Name = "Desligar a ID de anúncio = Habilitar"
       Class = "Machine"; Key = "$W\AdvertisingInfo"; ValueName = "DisabledByGroupPolicy"; State = "Enabled" },

    # 12. Políticas de SO
    @{ Name = "Habilita feed de Atividades = Desabilitar"
       Class = "Machine"; Key = "$W\System"; ValueName = "EnableActivityFeed"; State = "Disabled" },

    @{ Name = "Permitir sincronização da Área de transferência entre dispositivos = Desabilitar"
       Class = "Machine"; Key = "$W\System"; ValueName = "AllowCrossDeviceClipboard"; State = "Disabled" },

    @{ Name = "Permitir publicação de atividades do usuário = Desabilitar"
       Class = "Machine"; Key = "$W\System"; ValueName = "PublishUserActivities"; State = "Disabled" }
)

# -------------------------------------------------------------------------
# ETAPA 1: localizar cada política nos ADMX e montar as entradas
# -------------------------------------------------------------------------

Write-Host ""
Write-Status INFO "Lendo os modelos administrativos (ADMX) do Windows..."

$AdmxKeys = @()
foreach ($s in $Specs) { $AdmxKeys += $s.Key }

$AdmxIndex = Get-AdmxPolicies -Keys $AdmxKeys

Write-Status INFO "$($AdmxIndex.Count) política(s) relevantes encontradas nos ADMX."

$Pending = New-Object System.Collections.Generic.List[object]

foreach ($spec in $Specs) {

    Write-Host ""
    Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host $spec.Name -ForegroundColor White

    $label = "{0}\{1}\{2}" -f $spec.Class, $spec.Key, $spec.ValueName

    $hit = Find-AdmxPolicy -Spec $spec -Index $AdmxIndex

    if ($null -eq $hit.Policy) {

        $cands = @()
        foreach ($c in $hit.SameKey) { $cands += "$($c.Name)[$($c.ValueName)]" }

        $obs = "Política não localizada nos ADMX desta build."
        if ($cands.Count -gt 0) { $obs += " Políticas existentes nesta chave: " + ($cands -join ", ") }

        Write-Status SKIP $obs
        Add-Result $spec.Name "IGNORADO" $label $spec.State $obs
        continue
    }

    try {
        $entries = New-PolicyEntries -Policy $hit.Policy -Spec $spec
    }
    catch {
        Write-Status FAIL "$($_.Exception.Message)"
        Add-Result $spec.Name "FALHOU" $label $spec.State $_.Exception.Message
        continue
    }

    Write-Host "ADMX     : $($hit.Policy.File) / $($hit.Policy.Name)  ->  $($spec.State)" -ForegroundColor DarkGray

    foreach ($e in $entries) {
        Write-Host ("Registro : {0}\{1}" -f $e.Key, (Format-PolEntry $e)) -ForegroundColor DarkGray
    }

    if ($spec.ContainsKey("Note") -and $spec.Note) {
        Write-Status INFO $spec.Note
    }

    $Pending.Add(@{ Spec = $spec; Policy = $hit.Policy; Entries = $entries; Label = $label })
}

# -------------------------------------------------------------------------
# ETAPA 2: gravar no Registry.pol (mesclando com o que já existe)
# -------------------------------------------------------------------------

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "             GRAVANDO NA POLÍTICA DE GRUPO LOCAL" -ForegroundColor White
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

$NewRecords = @{
    Machine = New-Object System.Collections.Generic.List[object]
    User    = New-Object System.Collections.Generic.List[object]
}

foreach ($p in $Pending) {
    foreach ($e in $p.Entries) {
        $NewRecords[$p.Spec.Class].Add((ConvertTo-PolRecord $e))
    }
}

$PolWritten = @{ Machine = $false; User = $false }
$PolError   = @{ Machine = ""; User = "" }

foreach ($scope in @("Machine", "User")) {

    if ($NewRecords[$scope].Count -eq 0) { continue }

    $path = $PolFiles[$scope]

    try {
        $dir = Split-Path $path -Parent

        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }

        $existing = Read-PolFile $path
        $merged   = Merge-PolRecords $existing $NewRecords[$scope]

        Write-PolFile $path $merged

        # Confere relendo o arquivo gravado.
        $check = Read-PolFile $path
        $missing = 0

        foreach ($n in $NewRecords[$scope]) {

            $found = $false

            foreach ($c in $check) {
                if (($c.Key -ieq $n.Key) -and ($c.Value -ieq $n.Value) -and ($c.Type -eq $n.Type) -and
                    ([BitConverter]::ToString($c.Data) -eq [BitConverter]::ToString($n.Data))) {
                    $found = $true
                    break
                }
            }

            if (-not $found) { $missing++ }
        }

        if ($missing -gt 0) { throw "$missing entrada(s) não conferem após a gravação." }

        $PolWritten[$scope] = $true
        Write-Status OK "Registry.pol ($scope) atualizado e conferido: $path"
    }
    catch {
        $PolError[$scope] = $_.Exception.Message
        Write-Status FAIL "Registry.pol ($scope): $($_.Exception.Message)"
    }
}

if ($PolWritten.Machine -or $PolWritten.User) {
    try {
        Update-GptIni -MachineChanged $PolWritten.Machine -UserChanged $PolWritten.User
        Write-Status OK "gpt.ini atualizado."
    }
    catch {
        Write-Status WARN "Não foi possível atualizar o gpt.ini: $($_.Exception.Message)"
    }
}

# -------------------------------------------------------------------------
# ETAPA 3: aplicar (gpupdate) e conferir o registro
# -------------------------------------------------------------------------

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "             ATUALIZANDO POLÍTICAS DO WINDOWS" -ForegroundColor White
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

try {

    $gp = Start-Process `
        -FilePath "gpupdate.exe" `
        -ArgumentList "/force" `
        -Wait `
        -PassThru `
        -NoNewWindow

    if ($gp.ExitCode -eq 0) {
        Write-Status OK "gpupdate /force concluído."
    }
    else {
        Write-Status WARN "gpupdate terminou com código $($gp.ExitCode)."
    }

}
catch {
    Write-Status WARN "Não foi possível executar gpupdate."
}

Write-Host ""
Write-Status INFO "Conferindo o resultado de cada política..."
Write-Host ""

foreach ($p in $Pending) {

    $spec  = $p.Spec
    $class = $spec.Class

    if (-not $PolWritten[$class]) {
        Write-Status FAIL "$($spec.Name) - não gravada no Registry.pol."
        Add-Result $spec.Name "FALHOU" $p.Label $spec.State $PolError[$class]
        continue
    }

    $hive = "HKLM"
    if ($class -eq "User") { $hive = "HKCU" }

    $problems = @()

    foreach ($e in $p.Entries) {

        $psPath = "{0}:\{1}" -f $hive, $e.Key
        $exists = $false
        $actual = $null

        try {
            if (Test-Path -LiteralPath $psPath) {
                $item = Get-ItemProperty -LiteralPath $psPath -ErrorAction Stop
                $prop = $item.PSObject.Properties[$e.Name]

                if ($null -ne $prop) {
                    $exists = $true
                    $actual = $prop.Value
                }
            }
        }
        catch { }

        if ($e.Kind -eq "delete") {
            if ($exists) { $problems += "$($e.Name) ainda existe no registro ($actual)" }
        }
        elseif (-not $exists) {
            $problems += "$($e.Name) ausente no registro"
        }
        elseif ([string]$actual -ne [string]$e.Value) {
            $problems += "$($e.Name) = $actual (esperado $($e.Value))"
        }
    }

    $note = ""
    if ($spec.ContainsKey("Note") -and $spec.Note) { $note = $spec.Note }

    if ($problems.Count -eq 0) {

        Write-Status OK "$($spec.Name)"
        Add-Result $spec.Name "OK" $p.Label $spec.State $note
    }
    else {

        $msg = "Gravada no Registry.pol (o gpedit mostrará), mas o registro ainda não reflete: " + ($problems -join "; ") + ". Reinicie/refaça logon e confira."
        Write-Status WARN "$($spec.Name) - $msg"
        Add-Result $spec.Name "AVISO" $p.Label $spec.State $msg
    }
}

# -------------------------------------------------------------------------
# RELATÓRIO
# -------------------------------------------------------------------------

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "                       RESULTADO" -ForegroundColor White
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

$OKCount   = @($Results | Where-Object Status -eq "OK").Count
$WarnCount = @($Results | Where-Object Status -eq "AVISO").Count
$FailCount = @($Results | Where-Object Status -eq "FALHOU").Count
$SkipCount = @($Results | Where-Object Status -eq "IGNORADO").Count

Write-Host "Aplicadas e conferidas : $OKCount" -ForegroundColor Green
Write-Host "Aplicadas com aviso    : $WarnCount" -ForegroundColor Yellow
Write-Host "Falharam               : $FailCount" -ForegroundColor Red
Write-Host "Ignoradas              : $SkipCount" -ForegroundColor DarkGray
Write-Host ""

# -------------------------------------------------------------------------
# EXPORTAÇÃO DO RELATÓRIO
# -------------------------------------------------------------------------

$ReportFile = Join-Path `
    $BackupDir `
    "Relatorio-Politicas-$Timestamp.csv"

try {

    $Results |
        Export-Csv `
            -Path $ReportFile `
            -NoTypeInformation `
            -Encoding UTF8

    Write-Status OK "Relatório salvo em:"
    Write-Host "           $ReportFile" -ForegroundColor Cyan

}
catch {
    Write-Status WARN "Não foi possível salvar o relatório CSV."
}

# -------------------------------------------------------------------------
# POLÍTICAS COM FALHA
# -------------------------------------------------------------------------

if ($FailCount -gt 0) {

    Write-Host ""
    Write-Host "POLÍTICAS QUE APRESENTARAM FALHA:" -ForegroundColor Red
    Write-Host ""

    $Results |
        Where-Object Status -eq "FALHOU" |
        ForEach-Object {
            Write-Host "  - $($_.Politica)" -ForegroundColor Red
            Write-Host "    $($_.Observacao)" -ForegroundColor DarkRed
        }
}

# -------------------------------------------------------------------------
# POLÍTICAS COM AVISO
# -------------------------------------------------------------------------

if ($WarnCount -gt 0) {

    Write-Host ""
    Write-Host "POLÍTICAS APLICADAS COM AVISO:" -ForegroundColor Yellow
    Write-Host ""

    $Results |
        Where-Object Status -eq "AVISO" |
        ForEach-Object {
            Write-Host "  - $($_.Politica)" -ForegroundColor Yellow
            if ($_.Observacao) {
                Write-Host "    $($_.Observacao)" -ForegroundColor DarkYellow
            }
        }
}

# -------------------------------------------------------------------------
# POLÍTICAS NÃO LOCALIZADAS NOS ADMX
# -------------------------------------------------------------------------

if ($SkipCount -gt 0) {

    Write-Host ""
    Write-Host "POLÍTICAS NÃO LOCALIZADAS NOS ADMX (IGNORADAS):" -ForegroundColor Gray
    Write-Host ""

    $Results |
        Where-Object Status -eq "IGNORADO" |
        ForEach-Object {
            Write-Host "  - $($_.Politica)" -ForegroundColor Gray
            Write-Host "    $($_.Observacao)" -ForegroundColor DarkGray
        }
}

# -------------------------------------------------------------------------
# FINAL
# -------------------------------------------------------------------------

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "                         CONCLUÍDO" -ForegroundColor White
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Backups   :" -NoNewline
Write-Host " $BackupDir" -ForegroundColor Cyan

Write-Host "Relatório:" -NoNewline
Write-Host " $ReportFile" -ForegroundColor Cyan

Write-Host ""
Write-Host "É recomendado REINICIAR o Windows para que todas as políticas"
Write-Host "e mecanismos de compatibilidade recarreguem suas configurações."
Write-Host ""

$restart = Read-Host "Deseja reiniciar agora? [S/N]"

if ($restart -match "^[SsYy]$") {

    Write-Host ""
    Write-Status INFO "O Windows será reiniciado em 10 segundos..."
    Start-Sleep -Seconds 10

    Restart-Computer -Force
}
else {

    Write-Host ""
    Write-Status INFO "Reinicialização cancelada. Reinicie manualmente quando conveniente."
}

Write-Host ""
Read-Host "Pressione ENTER para fechar"
