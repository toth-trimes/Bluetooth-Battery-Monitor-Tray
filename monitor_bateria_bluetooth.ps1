#requires -version 5.1
param(
    [switch]$Quiet,
    [string]$Mac = "",
    [string]$Name = ""
)

<#
===============================================================================
  Monitor de Bateria de Dispositivos Bluetooth na Bandeja do Windows (System Tray)
  Desenvolvido para Suporte Técnico / Dell G3 3579 (Windows 11)
  Suporta execução de múltiplas instâncias para monitorar dispositivos simultâneos!
===============================================================================
#>

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# -----------------------------------------------------------------------------
# Declarações Win32 para controle de janelas e liberação de recursos GDI
# -----------------------------------------------------------------------------
$win32Type = Add-Type -MemberDefinition @'
[DllImport("user32.dll")]
public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
[DllImport("user32.dll")]
public static extern bool SetForegroundWindow(IntPtr hWnd);
[DllImport("user32.dll")]
public static extern bool DestroyIcon(IntPtr hIcon);
[DllImport("kernel32.dll")]
public static extern IntPtr GetConsoleWindow();
'@ -Name "Win32TrayHelper" -Namespace "BluetoothMonitor" -PassThru -ErrorAction SilentlyContinue

if (-not $win32Type) {
    $win32Type = [BluetoothMonitor.Win32TrayHelper]
}

# Caminho do arquivo de configuração
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigFile = Join-Path $ScriptDir "bt_battery_config.json"

# Estado global da aplicação
$global:CurrentHIcon = [IntPtr]::Zero
$global:LastAlertedBattery = -1
$global:SelectedMac = ""
$global:SelectedName = ""
$global:UpdateIntervalSec = 120
$global:DisplayMode = "Numero"   # "Numero", "Icone", "Alternar"
$global:DeviceIcon = "auto"       # "auto", "fone", "caixa", "mouse", "celular", "microfone"
$global:AnimToggle = $false
$global:CachedBattery = $null
$global:CachedConnected = $false
$global:ConsoleHwnd = $win32Type::GetConsoleWindow()

# Caminho da pasta de Inicialização do Windows (Autostart sem elevação)
$StartupFolder = [Environment]::GetFolderPath('Startup')

# Limpa atalho genérico legado se existir para evitar ambiguidades
$legacyLnk = Join-Path $StartupFolder "Monitor de Bateria Bluetooth.lnk"
if (Test-Path -LiteralPath $legacyLnk) {
    Remove-Item -LiteralPath $legacyLnk -Force -ErrorAction SilentlyContinue
}

function Get-DeviceStartupLnkPath ([string]$deviceName) {
    $cleanName = ($deviceName -replace '[\\/:*?"<>|]', '_').Trim()
    if ([string]::IsNullOrWhiteSpace($cleanName)) { $cleanName = "Dispositivo" }
    return Join-Path $StartupFolder "Monitor de Bateria ($cleanName).lnk"
}

function Test-DeviceAutostart ([string]$deviceName) {
    if ([string]::IsNullOrWhiteSpace($deviceName)) { return $false }
    $lnk = Get-DeviceStartupLnkPath $deviceName
    return (Test-Path -LiteralPath $lnk)
}

function Set-DeviceAutostart ([string]$mac, [string]$deviceName, [bool]$enable) {
    try {
        $lnkPath = Get-DeviceStartupLnkPath $deviceName
        if ($enable) {
            $wsh = New-Object -ComObject WScript.Shell
            $lnk = $wsh.CreateShortcut($lnkPath)
            $lnk.TargetPath = "powershell.exe"
            $lnk.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptDir\monitor_bateria_bluetooth.ps1`" -Mac `"$mac`" -Quiet"
            $lnk.WorkingDirectory = $ScriptDir
            $lnk.Description = "Monitor de Bateria Bluetooth - $deviceName"
            $iconPath = "$env:SystemRoot\System32\bthprops.cpl"
            if (Test-Path $iconPath) {
                $lnk.IconLocation = "$iconPath, 0"
            } else {
                $lnk.IconLocation = "shell32.dll, 25"
            }
            $lnk.Save()
            return $true
        } else {
            if (Test-Path -LiteralPath $lnkPath) {
                Remove-Item -LiteralPath $lnkPath -Force -ErrorAction SilentlyContinue
            }
            return $false
        }
    } catch {
        return $false
    }
}

# -----------------------------------------------------------------------------
# Funções de Configuração (Por dispositivo com fallback para compatibilidade)
# -----------------------------------------------------------------------------
function Load-Config ([string]$mac = "") {
    if ([string]::IsNullOrWhiteSpace($mac) -and -not [string]::IsNullOrWhiteSpace($global:SelectedMac)) {
        $mac = $global:SelectedMac
    }

    # 1. Tenta carregar arquivo específico do dispositivo
    if (-not [string]::IsNullOrWhiteSpace($mac)) {
        $devCfgFile = Join-Path $ScriptDir "bt_config_$mac.json"
        if (Test-Path $devCfgFile) {
            try {
                return (Get-Content -Path $devCfgFile -Raw -Encoding UTF8 | ConvertFrom-Json)
            } catch {}
        }
    }

    # 2. Fallback: arquivo geral de configuração
    if (Test-Path $ConfigFile) {
        try {
            $json = Get-Content -Path $ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ([string]::IsNullOrWhiteSpace($mac) -or $json.LastMac -eq $mac) {
                return $json
            }
        } catch {}
    }
    return $null
}

function Save-Config {
    if ([string]::IsNullOrWhiteSpace($global:SelectedMac)) { return }

    try {
        $cfg = [ordered]@{
            Mac            = $global:SelectedMac
            Name           = $global:SelectedName
            UpdateInterval = $global:UpdateIntervalSec
            DisplayMode    = $global:DisplayMode
            DeviceIcon     = $global:DeviceIcon
            LastUpdated    = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        }

        # Salva o arquivo exclusivo do dispositivo
        $devCfgFile = Join-Path $ScriptDir "bt_config_$($global:SelectedMac).json"
        $cfg | ConvertTo-Json -Depth 3 | Set-Content -Path $devCfgFile -Encoding UTF8

        # Atualiza também o arquivo geral para apontar o último dispositivo acessado
        $general = [ordered]@{
            LastMac        = $global:SelectedMac
            LastName       = $global:SelectedName
            UpdateInterval = $global:UpdateIntervalSec
            DisplayMode    = $global:DisplayMode
            DeviceIcon     = $global:DeviceIcon
            LastUpdated    = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        }
        $general | ConvertTo-Json -Depth 3 | Set-Content -Path $ConfigFile -Encoding UTF8
    } catch {}
}

# -----------------------------------------------------------------------------
# Detecção Automática do Tipo de Ícone por Nome
# -----------------------------------------------------------------------------
function Get-ResolvedDeviceIconType {
    if ($global:DeviceIcon -ne "auto") {
        return $global:DeviceIcon
    }
    $n = $global:SelectedName
    if ($n -match "Mouse") {
        return "mouse"
    } elseif ($n -match "Charge|Speaker|Caixa|Sound|Audio|TUNE FLEX|DOT") {
        return "caixa"
    } elseif ($n -match "Note|Galaxy|Phone|iPhone|Smartphone|Celular") {
        return "celular"
    } elseif ($n -match "Mic|Microphone") {
        return "microfone"
    } else {
        return "fone"
    }
}

# -----------------------------------------------------------------------------
# Descoberta de Dispositivos e Coleta de Bateria
# -----------------------------------------------------------------------------
function Get-BluetoothDevices {
    $raw = Get-PnpDevice -Class 'Bluetooth' -ErrorAction SilentlyContinue |
           Where-Object { $_.InstanceId -match '^BTH(ENUM|LE)\\DEV_([0-9A-F]{12})' }

    $devices = @()
    $seenMacs = @{}

    foreach ($dev in $raw) {
        if ($dev.InstanceId -match '^BTH(ENUM|LE)\\DEV_([0-9A-F]{12})') {
            $mac = $matches[2]
            if (-not $seenMacs.ContainsKey($mac)) {
                $seenMacs[$mac] = $true
                $devices += [PSCustomObject]@{
                    FriendlyName = $dev.FriendlyName
                    MacAddress   = $mac
                    Status       = $dev.Status
                    Present      = $dev.Present
                }
            }
        }
    }
    return $devices
}

function Get-DeviceBattery ([string]$mac) {
    $nodes = Get-PnpDevice | Where-Object { $_.InstanceId -like "*$mac*" } -ErrorAction SilentlyContinue
    $battery = $null
    $isConnected = $false

    # Verifica se há nós com IsConnected = True ({83da6326-97a6-4088-9453-a1923f573b29} 15)
    foreach ($node in $nodes) {
        $isConn = Get-PnpDeviceProperty -InstanceId $node.InstanceId -KeyName '{83da6326-97a6-4088-9453-a1923f573b29} 15' -ErrorAction SilentlyContinue
        if ($isConn -and $isConn.Data -eq $true) {
            $isConnected = $true
            break
        }
    }

    # Se conectado em tempo real, obtém a carga do nó correspondente
    if ($isConnected) {
        foreach ($node in $nodes) {
            $prop = Get-PnpDeviceProperty -InstanceId $node.InstanceId -KeyName '{104EA319-6EE2-4701-BD47-8DDBF425BBE5} 2' -ErrorAction SilentlyContinue |
                    Where-Object { $_.Type -ne 'Empty' } | Select-Object -ExpandProperty Data
            if ($null -ne $prop) {
                $battery = [int]$prop
                break
            }
        }
    }

    return [PSCustomObject]@{
        Battery   = $battery
        Connected = $isConnected
    }
}

# -----------------------------------------------------------------------------
# Detecção da Cor da Barra de Tarefas (Tema Claro / Escuro / Cor de Destaque)
# -----------------------------------------------------------------------------
function Get-TaskbarBackgroundColor {
    try {
        $reg = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -ErrorAction Stop
        $isLight = $reg.SystemUsesLightTheme -eq 1
        $hasAccent = $reg.ColorPrevalence -eq 1

        if ($hasAccent) {
            $dwm = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\DWM' -ErrorAction SilentlyContinue
            if ($dwm -and $dwm.AccentColor) {
                $c = [uint32]$dwm.AccentColor
                $r = $c -band 0xFF
                $g = ($c -shr 8) -band 0xFF
                $b = ($c -shr 16) -band 0xFF
                return [System.Drawing.Color]::FromArgb(255, $r, $g, $b)
            }
        }

        if ($isLight) {
            return [System.Drawing.Color]::FromArgb(255, 243, 243, 243)
        } else {
            return [System.Drawing.Color]::FromArgb(255, 32, 32, 32)
        }
    } catch {
        return [System.Drawing.Color]::FromArgb(255, 32, 32, 32)
    }
}

# -----------------------------------------------------------------------------
# Renderização dos Ícones da Bandeja (Número ou Glifo com Traço Reforçado e Fundo da Barra)
# -----------------------------------------------------------------------------
function Render-BatteryNumberIcon ([object]$val, [bool]$connected) {
    $bmp = New-Object System.Drawing.Bitmap 32, 32
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

    $bgColor = Get-TaskbarBackgroundColor
    $isLight = ($bgColor.R -gt 150 -and $bgColor.G -gt 150 -and $bgColor.B -gt 150)
    $g.Clear($bgColor)

    $format = New-Object System.Drawing.StringFormat
    $format.Alignment = [System.Drawing.StringAlignment]::Center
    $format.LineAlignment = [System.Drawing.StringAlignment]::Center

    if (-not $connected -or $null -eq $val) {
        $text = "--"
        $fontSize = 20
        $color = if ($isLight) { [System.Drawing.Color]::FromArgb(255, 100, 100, 100) } else { [System.Drawing.Color]::FromArgb(255, 190, 190, 190) }
    } else {
        $intVal = [int]$val
        $text = "$intVal"
        $fontSize = if ($intVal -ge 100) { 15 } else { 19 }

        if ($isLight) {
            $color = if ($intVal -le 20) {
                [System.Drawing.Color]::FromArgb(255, 215, 35, 35)
            } elseif ($intVal -le 40) {
                [System.Drawing.Color]::FromArgb(255, 220, 120, 0)
            } else {
                [System.Drawing.Color]::FromArgb(255, 0, 165, 60)
            }
        } else {
            $color = if ($intVal -le 20) {
                [System.Drawing.Color]::FromArgb(255, 255, 65, 65)
            } elseif ($intVal -le 40) {
                [System.Drawing.Color]::FromArgb(255, 255, 175, 30)
            } else {
                [System.Drawing.Color]::FromArgb(255, 45, 235, 105)
            }
        }
    }

    $font = New-Object System.Drawing.Font("Bahnschrift", $fontSize, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $brush = New-Object System.Drawing.SolidBrush $color

    # Espessamento do traço para máxima legibilidade
    $offsets = @(
        [System.Drawing.PointF]::new(-0.5, 0),
        [System.Drawing.PointF]::new(0.5, 0),
        [System.Drawing.PointF]::new(0, -0.5),
        [System.Drawing.PointF]::new(0, 0.5),
        [System.Drawing.PointF]::new(0, 0)
    )
    foreach ($pt in $offsets) {
        $rect = New-Object System.Drawing.RectangleF $pt.X, $pt.Y, 32, 32
        $g.DrawString($text, $font, $brush, $rect, $format)
    }

    $hIcon = $bmp.GetHicon()
    $icon = [System.Drawing.Icon]::FromHandle($hIcon)

    $g.Dispose()
    $bmp.Dispose()
    $brush.Dispose()
    $font.Dispose()
    $format.Dispose()

    return @{ Icon = $icon; HIcon = $hIcon }
}

function Render-DeviceGlyphIcon ([string]$iconType, [object]$val, [bool]$connected) {
    $bmp = New-Object System.Drawing.Bitmap 32, 32
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

    $bgColor = Get-TaskbarBackgroundColor
    $isLight = ($bgColor.R -gt 150 -and $bgColor.G -gt 150 -and $bgColor.B -gt 150)
    $g.Clear($bgColor)

    $format = New-Object System.Drawing.StringFormat
    $format.Alignment = [System.Drawing.StringAlignment]::Center
    $format.LineAlignment = [System.Drawing.StringAlignment]::Center

    $charHex = switch ($iconType.ToLower()) {
        "fone"      { "E7F6" }
        "caixa"     { "E7F5" }
        "mouse"     { "E962" }
        "celular"   { "E8EA" }
        "microfone" { "E720" }
        default     { "E7F6" }
    }

    $fontName = "Segoe Fluent Icons"
    $testFont = New-Object System.Drawing.Font($fontName, 22, [System.Drawing.GraphicsUnit]::Pixel)
    if ($testFont.Name -ne $fontName) {
        $fontName = "Segoe MDL2 Assets"
    }
    $font = New-Object System.Drawing.Font($fontName, 22, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $char = [char][convert]::ToInt32($charHex, 16)

    if (-not $connected -or $null -eq $val) {
        $color = if ($isLight) { [System.Drawing.Color]::FromArgb(255, 100, 100, 100) } else { [System.Drawing.Color]::FromArgb(255, 190, 190, 190) }
    } else {
        $intVal = [int]$val
        if ($isLight) {
            $color = if ($intVal -le 20) {
                [System.Drawing.Color]::FromArgb(255, 215, 35, 35)
            } elseif ($intVal -le 40) {
                [System.Drawing.Color]::FromArgb(255, 220, 120, 0)
            } else {
                [System.Drawing.Color]::FromArgb(255, 0, 165, 60)
            }
        } else {
            $color = if ($intVal -le 20) {
                [System.Drawing.Color]::FromArgb(255, 255, 65, 65)
            } elseif ($intVal -le 40) {
                [System.Drawing.Color]::FromArgb(255, 255, 175, 30)
            } else {
                [System.Drawing.Color]::FromArgb(255, 45, 235, 105)
            }
        }
    }

    $brush = New-Object System.Drawing.SolidBrush $color

    # Espessamento do traço em cruz para engrossar linhas finas
    $offsets = @(
        [System.Drawing.PointF]::new(-0.8, 0),
        [System.Drawing.PointF]::new(0.8, 0),
        [System.Drawing.PointF]::new(0, -0.8),
        [System.Drawing.PointF]::new(0, 0.8),
        [System.Drawing.PointF]::new(0, 0)
    )

    foreach ($pt in $offsets) {
        $rect = New-Object System.Drawing.RectangleF $pt.X, $pt.Y, 32, 32
        $g.DrawString($char, $font, $brush, $rect, $format)
    }

    $hIcon = $bmp.GetHicon()
    $icon = [System.Drawing.Icon]::FromHandle($hIcon)

    $g.Dispose()
    $bmp.Dispose()
    $brush.Dispose()
    $font.Dispose()
    $format.Dispose()

    return @{ Icon = $icon; HIcon = $hIcon }
}

# -----------------------------------------------------------------------------
# Interface de Seleção do Dispositivo
# -----------------------------------------------------------------------------
function Show-DeviceSelectionMenu {
    Clear-Host
    Write-Host "=======================================================================" -ForegroundColor Cyan
    Write-Host "         MONITOR DE BATERIA BLUETOOTH NA BANDEJA DO SISTEMA           " -ForegroundColor Cyan
    Write-Host "=======================================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Buscando dispositivos Bluetooth emparelhados, aguarde..." -ForegroundColor Yellow

    # 1 única chamada em lote para listar dispositivos Bluetooth principais
    $allBth = Get-PnpDevice -Class 'Bluetooth' -ErrorAction SilentlyContinue |
              Where-Object { $_.InstanceId -match '^BTH(ENUM|LE)\\DEV_([0-9A-F]{12})' }

    if (-not $allBth -or $allBth.Count -eq 0) {
        Write-Host "Nenhum dispositivo Bluetooth emparelhado foi encontrado." -ForegroundColor Red
        Write-Host "Certifique-se de que o Bluetooth esta ativado nas Configuracoes do Windows." -ForegroundColor Gray
        Write-Host ""
        Read-Host "Pressione ENTER para fechar"
        exit
    }

    # Consulta em lote de conectividade em tempo real (ultra-rápida)
    $connProps = $allBth | Get-PnpDeviceProperty -KeyName '{83da6326-97a6-4088-9453-a1923f573b29} 15' -ErrorAction SilentlyContinue
    $connMap = @{}
    foreach ($cp in $connProps) {
        if ($cp.InstanceId -match 'DEV_([0-9A-F]{12})') {
            if ($cp.Data -eq $true) {
                $connMap[$matches[1]] = $true
            }
        }
    }

    $rawDevices = @()
    $seenMacs = @{}
    foreach ($d in $allBth) {
        if ($d.InstanceId -match 'DEV_([0-9A-F]{12})') {
            $mac = $matches[1]
            if (-not $seenMacs.ContainsKey($mac)) {
                $seenMacs[$mac] = $true
                $rawDevices += [PSCustomObject]@{
                    FriendlyName = $d.FriendlyName
                    MacAddress   = $mac
                    Connected    = $connMap.ContainsKey($mac)
                }
            }
        }
    }

    # Identifica dispositivos já monitorados em instâncias ativas
    $runningMacs = @{}
    foreach ($d in $devices) {
        $mTestName = "Local\BluetoothBatteryMonitor_Mutex_$($d.MacAddress)"
        try {
            $testM = [System.Threading.Mutex]::OpenExisting($mTestName)
            $runningMacs[$d.MacAddress.ToUpper()] = $true
            $testM.Dispose()
        } catch {}
    }

    # Ordenar: Conectados no topo
    $devices = $rawDevices | Sort-Object @{Expression="Connected"; Descending=$true}, FriendlyName

    $cfg = Load-Config
    $defaultIndex = 1

    Write-Host ""
    Write-Host "Dispositivos encontrados:" -ForegroundColor Cyan
    Write-Host "-----------------------------------------------------------------------" -ForegroundColor DarkGray

    $hasConnectedHeader = $false
    $hasDisconnectedHeader = $false
    $foundNonRunningDefault = $false

    for ($i = 0; $i -lt $devices.Count; $i++) {
        $dev = $devices[$i]
        $num = $i + 1
        $isRunning = $runningMacs.ContainsKey($dev.MacAddress.ToUpper())
        $runningTag = if ($isRunning) { " [Já ativo na bandeja]" } else { "" }
        
        if ($dev.Connected) {
            if (-not $hasConnectedHeader) {
                Write-Host "  DISPOSITIVOS CONECTADOS AGORA:" -ForegroundColor Green
                $hasConnectedHeader = $true
            }
            if ($isRunning) {
                Write-Host ("   [{0}] {1,-28} (Conectado){2}" -f $num, $dev.FriendlyName, $runningTag) -ForegroundColor DarkCyan
            } else {
                Write-Host ("   [{0}] {1,-28} (Conectado)" -f $num, $dev.FriendlyName) -ForegroundColor White
            }
        } else {
            if (-not $hasDisconnectedHeader) {
                if ($hasConnectedHeader) { Write-Host "" }
                Write-Host "  OUTROS APARELHOS (DESCONECTADOS):" -ForegroundColor DarkGray
                $hasDisconnectedHeader = $true
            }
            if ($isRunning) {
                Write-Host ("   [{0}] {1,-28} (Desconectado){2}" -f $num, $dev.FriendlyName, $runningTag) -ForegroundColor DarkCyan
            } else {
                Write-Host ("   [{0}] {1,-28} (Desconectado)" -f $num, $dev.FriendlyName) -ForegroundColor DarkGray
            }
        }

        # Seleciona como padrão o último MAC ou o primeiro conectado que ainda não esteja rodando
        if (-not $foundNonRunningDefault) {
            if ($cfg -and $cfg.LastMac -eq $dev.MacAddress -and -not $isRunning) {
                $defaultIndex = $num
                $foundNonRunningDefault = $true
            } elseif ($dev.Connected -and -not $isRunning -and $defaultIndex -eq 1) {
                $defaultIndex = $num
            }
        }
    }

    Write-Host "-----------------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""

    $defaultDevice = $devices[$defaultIndex - 1]
    Write-Host "Escolha o numero do dispositivo que deseja monitorar (1-$($devices.Count))" -ForegroundColor Cyan
    $promptMsg = "Pressione ENTER para selecionar [{0}] {1}: " -f $defaultIndex, $defaultDevice.FriendlyName
    $choice = Read-Host $promptMsg

    $selectedIndex = $defaultIndex - 1
    if (-not [string]::IsNullOrWhiteSpace($choice)) {
        $parsed = 0
        if ([int]::TryParse($choice, [ref]$parsed)) {
            $selectedIndex = $parsed - 1
        }
    }

    if ($selectedIndex -lt 0 -or $selectedIndex -ge $devices.Count) {
        $selectedIndex = 0
    }

    $chosen = $devices[$selectedIndex]

    # Valida se já não está ativo
    if ($runningMacs.ContainsKey($chosen.MacAddress.ToUpper())) {
        Write-Host ""
        Write-Host "Aviso: O dispositivo '$($chosen.FriendlyName)' já está ativo na bandeja do sistema." -ForegroundColor Yellow
        Write-Host "Para monitorar múltiplos aparelhos, selecione um dispositivo que não esteja em execução." -ForegroundColor Gray
        Write-Host ""
        Read-Host "Pressione ENTER para fechar"
        exit
    }

    $global:SelectedMac = $chosen.MacAddress
    $global:SelectedName = $chosen.FriendlyName

    # Carrega preferências do dispositivo escolhido
    $devCfg = Load-Config $global:SelectedMac
    if ($devCfg) {
        if ($devCfg.UpdateInterval) { $global:UpdateIntervalSec = [int]$devCfg.UpdateInterval }
        if ($devCfg.DisplayMode)    { $global:DisplayMode = [string]$devCfg.DisplayMode }
        if ($devCfg.DeviceIcon)     { $global:DeviceIcon = [string]$devCfg.DeviceIcon }
    }

    Save-Config

    Write-Host ""
    Write-Host "Dispositivo selecionado: $($chosen.FriendlyName)" -ForegroundColor Green
    Write-Host "Iniciando monitoramento na bandeja do sistema..." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Dica: Clique com o botao direito no icone da bandeja para:" -ForegroundColor Cyan
    Write-Host "  - Ativar 'Iniciar com o Windows' (especifico deste dispositivo)"
    Write-Host "  - Alternar entre icone e porcentagem (ou modo animado a cada 1s)"
    Write-Host "  - Escolher o tipo de icone (fone, mouse, celular, caixa de som)"
    Write-Host "  - Ajustar intervalo (padrao: 2 min, acelerado para 1 min em bateria baixa)"
    Write-Host "  - Executar novamente este script para monitorar outros aparelhos simultaneos"
    Write-Host ""
    Write-Host "A janela do console sera ocultada em instantes..." -ForegroundColor Gray
    Start-Sleep -Seconds 2
}

# -----------------------------------------------------------------------------
# Aplicação Principal e NotifyIcon
# -----------------------------------------------------------------------------
function Start-TrayApp {
    param(
        [switch]$Quiet,
        [string]$TargetMac = "",
        [string]$TargetName = ""
    )

    if (-not [string]::IsNullOrWhiteSpace($TargetMac)) {
        # Inicialização direcionada (ex: atalho de autoinicialização do Windows para este dispositivo)
        $global:SelectedMac = $TargetMac
        if (-not [string]::IsNullOrWhiteSpace($TargetName)) {
            $global:SelectedName = $TargetName
        } else {
            $pnpDev = Get-PnpDevice -Class 'Bluetooth' -ErrorAction SilentlyContinue |
                      Where-Object { $_.InstanceId -like "*$TargetMac*" } | Select-Object -First 1
            if ($pnpDev -and $pnpDev.FriendlyName) {
                $global:SelectedName = $pnpDev.FriendlyName
            } else {
                $global:SelectedName = "Bluetooth $TargetMac"
            }
        }

        # Carrega configurações salvas para esse dispositivo
        $cfg = Load-Config $TargetMac
        if ($cfg) {
            if ($cfg.Name -and [string]::IsNullOrWhiteSpace($global:SelectedName)) { $global:SelectedName = $cfg.Name }
            if ($cfg.UpdateInterval) { $global:UpdateIntervalSec = [int]$cfg.UpdateInterval }
            if ($cfg.DisplayMode)    { $global:DisplayMode = [string]$cfg.DisplayMode }
            if ($cfg.DeviceIcon)     { $global:DeviceIcon = [string]$cfg.DeviceIcon }
        }
    } else {
        # Inicialização manual/interativa
        $cfg = Load-Config
        if ($cfg -and -not [string]::IsNullOrWhiteSpace($cfg.LastMac) -and $Quiet) {
            $global:SelectedMac = $cfg.LastMac
            $global:SelectedName = $cfg.LastName
            if ($cfg.UpdateInterval) { $global:UpdateIntervalSec = [int]$cfg.UpdateInterval }
            if ($cfg.DisplayMode)    { $global:DisplayMode = [string]$cfg.DisplayMode }
            if ($cfg.DeviceIcon)     { $global:DeviceIcon = [string]$cfg.DeviceIcon }
        } else {
            if ($cfg) {
                if ($cfg.DisplayMode) { $global:DisplayMode = [string]$cfg.DisplayMode }
                if ($cfg.DeviceIcon)  { $global:DeviceIcon = [string]$cfg.DeviceIcon }
                if ($cfg.UpdateInterval) { $global:UpdateIntervalSec = [int]$cfg.UpdateInterval }
            }
            Show-DeviceSelectionMenu
        }
    }

    # Mutex exclusivo por dispositivo (permite monitorar múltiplos dispositivos distintos ao mesmo tempo)
    $mutexName = "Local\BluetoothBatteryMonitor_Mutex_$($global:SelectedMac)"
    $script:createdMutex = $false
    $script:appMutex = New-Object System.Threading.Mutex($true, $mutexName, [ref]$script:createdMutex)
    if (-not $script:createdMutex) {
        if (-not $Quiet) {
            [System.Windows.Forms.MessageBox]::Show(
                "O dispositivo '$($global:SelectedName)' já está sendo monitorado em outra instância na bandeja do sistema.",
                "Monitor de Bateria Bluetooth",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
        }
        exit
    }

    if ($global:ConsoleHwnd -ne [IntPtr]::Zero) {
        $win32Type::ShowWindowAsync($global:ConsoleHwnd, 0) | Out-Null
    }

    $appContext = New-Object System.Windows.Forms.ApplicationContext
    $notifyIcon = New-Object System.Windows.Forms.NotifyIcon
    $contextMenu = New-Object System.Windows.Forms.ContextMenuStrip

    # Header Informativo
    $headerItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $headerItem.Text = "$($global:SelectedName) (Carregando...)"
    $headerItem.Enabled = $false
    $headerItem.Font = New-Object System.Drawing.Font($headerItem.Font, [System.Drawing.FontStyle]::Bold)
    $contextMenu.Items.Add($headerItem) | Out-Null

    $contextMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null

    # Atualizar Agora
    $refreshItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $refreshItem.Text = "Atualizar Agora"
    $contextMenu.Items.Add($refreshItem) | Out-Null

    # Trocar Dispositivo
    $changeDevItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $changeDevItem.Text = "Trocar Dispositivo..."
    $contextMenu.Items.Add($changeDevItem) | Out-Null

    $contextMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null

    # Submenu: Modo de Exibição
    $displayModeMenu = New-Object System.Windows.Forms.ToolStripMenuItem
    $displayModeMenu.Text = "Modo de Exibição"

    $displayModes = @(
        @{ Label = "Apenas Valor (Porcentagem)"; Mode = "Numero" },
        @{ Label = "Apenas Ícone do Dispositivo"; Mode = "Icone" },
        @{ Label = "Alternar a cada 1s (Ícone e Valor)"; Mode = "Alternar" }
    )
    $displayMenuItems = @()
    foreach ($dm in $displayModes) {
        $subM = New-Object System.Windows.Forms.ToolStripMenuItem
        $subM.Text = $dm.Label
        $subM.Tag = $dm.Mode
        $subM.Checked = ($dm.Mode -eq $global:DisplayMode)
        $displayModeMenu.DropDownItems.Add($subM) | Out-Null
        $displayMenuItems += $subM
    }
    $contextMenu.Items.Add($displayModeMenu) | Out-Null

    # Submenu: Ícone do Dispositivo
    $iconTypeMenu = New-Object System.Windows.Forms.ToolStripMenuItem
    $iconTypeMenu.Text = "Ícone do Dispositivo"

    $iconTypes = @(
        @{ Label = "Automático (Detectar pelo nome)"; Type = "auto" },
        @{ Label = "Fone de Ouvido";                  Type = "fone" },
        @{ Label = "Caixa de Som / Alto-falante";     Type = "caixa" },
        @{ Label = "Mouse";                           Type = "mouse" },
        @{ Label = "Celular";                         Type = "celular" },
        @{ Label = "Microfone";                       Type = "microfone" }
    )
    $iconMenuItems = @()
    foreach ($it in $iconTypes) {
        $subI = New-Object System.Windows.Forms.ToolStripMenuItem
        $subI.Text = $it.Label
        $subI.Tag = $it.Type
        $subI.Checked = ($it.Type -eq $global:DeviceIcon)
        $iconTypeMenu.DropDownItems.Add($subI) | Out-Null
        $iconMenuItems += $subI
    }
    $contextMenu.Items.Add($iconTypeMenu) | Out-Null

    # Submenu: Intervalo de Verificação
    $intervalMenu = New-Object System.Windows.Forms.ToolStripMenuItem
    $intervalMenu.Text = "Intervalo de Verificação"
    $intervals = @(
        @{ Label = "30 segundos";        Seconds = 30 },
        @{ Label = "1 minuto";           Seconds = 60 },
        @{ Label = "2 minutos (Padrão)"; Seconds = 120 },
        @{ Label = "5 minutos";          Seconds = 300 }
    )
    $intervalMenuItems = @()
    foreach ($opt in $intervals) {
        $subItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $subItem.Text = $opt.Label
        $subItem.Tag = $opt.Seconds
        $subItem.Checked = ($opt.Seconds -eq $global:UpdateIntervalSec)
        $intervalMenu.DropDownItems.Add($subItem) | Out-Null
        $intervalMenuItems += $subItem
    }
    $contextMenu.Items.Add($intervalMenu) | Out-Null

    # Iniciar com o Windows (Inicialização automática deste dispositivo no logon do usuário)
    $autostartItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $autostartItem.Text = "Iniciar com o Windows"
    $autostartItem.Checked = (Test-DeviceAutostart $global:SelectedName)
    $autostartItem.Add_Click({
        param($sender, $e)
        $newState = -not $sender.Checked
        $ok = Set-DeviceAutostart $global:SelectedMac $global:SelectedName $newState
        if ($ok -or -not $newState) {
            $sender.Checked = (Test-DeviceAutostart $global:SelectedName)
            if ($sender.Checked) {
                $notifyIcon.BalloonTipTitle = "Iniciar com o Windows"
                $notifyIcon.BalloonTipText = "Ativado: $($global:SelectedName) iniciará automaticamente na bandeja ao ligar o computador."
                $notifyIcon.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info
                $notifyIcon.ShowBalloonTip(2500)
            } else {
                $notifyIcon.BalloonTipTitle = "Iniciar com o Windows"
                $notifyIcon.BalloonTipText = "Desativado: $($global:SelectedName) não iniciará mais automaticamente."
                $notifyIcon.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info
                $notifyIcon.ShowBalloonTip(2500)
            }
        }
    })
    $contextMenu.Items.Add($autostartItem) | Out-Null

    $contextMenu.Add_Opening({
        $autostartItem.Checked = (Test-DeviceAutostart $global:SelectedName)
    })

    $contextMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null

    # Sair
    $exitItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $exitItem.Text = "Sair"
    $contextMenu.Items.Add($exitItem) | Out-Null

    $notifyIcon.ContextMenuStrip = $contextMenu
    $notifyIcon.Visible = $true

    # Rotina para desenhar o ícone de acordo com o modo atual
    $Script:DrawCurrentIcon = {
        param([bool]$forceGlyph = $false)

        $resolvedIcon = Get-ResolvedDeviceIconType
        $render = $null

        if ($global:DisplayMode -eq "Icone" -or $forceGlyph) {
            $render = Render-DeviceGlyphIcon $resolvedIcon $global:CachedBattery $global:CachedConnected
        } else {
            $render = Render-BatteryNumberIcon $global:CachedBattery $global:CachedConnected
        }

        if ($global:CurrentHIcon -ne [IntPtr]::Zero) {
            $win32Type::DestroyIcon($global:CurrentHIcon) | Out-Null
        }
        $global:CurrentHIcon = $render.HIcon
        $notifyIcon.Icon = $render.Icon
    }

    # Rotina de consulta e atualização do status de hardware
    $Script:UpdateTrayStatus = {
        try {
            $info = Get-DeviceBattery $global:SelectedMac
            $global:CachedBattery = $info.Battery
            $global:CachedConnected = $info.Connected

            $bat = $global:CachedBattery
            $conn = $global:CachedConnected

            # Regra de atualização adaptativa:
            # Se conectado e com bateria baixa (<= 20%), força o ciclo a atualizar a cada 1 minuto (60s)
            $isLowBattery = ($conn -and $null -ne $bat -and $bat -le 20)
            $effectiveIntervalSec = if ($isLowBattery) { 60 } else { $global:UpdateIntervalSec }
            $targetMs = $effectiveIntervalSec * 1000
            if ($timer.Interval -ne $targetMs) {
                $timer.Interval = $targetMs
            }

            # Renderiza ícone atual
            if ($global:DisplayMode -eq "Alternar") {
                & $Script:DrawCurrentIcon -forceGlyph:$global:AnimToggle
            } else {
                & $Script:DrawCurrentIcon
            }

            # Atualização de textos e tooltips
            $hora = (Get-Date).ToString("HH:mm:ss")
            $nl = [Environment]::NewLine
            if ($conn -and $null -ne $bat) {
                $statusText = "$($global:SelectedName): $bat%$nl" + "Status: Conectado$nl" + "Atualizado: $hora"
                $headerSuffix = if ($isLowBattery) { " ⚠️ (Atualizando a cada 1 min)" } else { "" }
                $headerItem.Text = "$($global:SelectedName) - $bat%$headerSuffix"

                if ($bat -le 20 -and $global:LastAlertedBattery -ne $bat) {
                    $notifyIcon.BalloonTipTitle = "Bateria Baixa - $($global:SelectedName)"
                    $notifyIcon.BalloonTipText = "A bateria atingiu $bat%. Verificação acelerada para 1 min. Conecte o carregador."
                    $notifyIcon.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Warning
                    $notifyIcon.ShowBalloonTip(3000)
                    $global:LastAlertedBattery = $bat
                } elseif ($bat -gt 20) {
                    $global:LastAlertedBattery = -1
                }
            } else {
                $statusText = "$($global:SelectedName)$nl" + "Status: Desconectado$nl" + "Atualizado: $hora"
                $headerItem.Text = "$($global:SelectedName) - Desconectado"
            }

            if ($statusText.Length -gt 63) {
                $batLabel = if ($conn -and $null -ne $bat) { "$bat%" } else { "--" }
                $notifyIcon.Text = "$($global:SelectedName): $batLabel"
            } else {
                $notifyIcon.Text = $statusText
            }

        } catch {
            $headerItem.Text = "$($global:SelectedName) - Erro na leitura"
        }
    }

    # Timer Periódico de Hardware (Bateria)
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = $global:UpdateIntervalSec * 1000
    $timer.Add_Tick({
        & $Script:UpdateTrayStatus
    })

    # Timer de Animação de 1 Segundo (Alternância)
    $animTimer = New-Object System.Windows.Forms.Timer
    $animTimer.Interval = 1000
    $animTimer.Add_Tick({
        if ($global:DisplayMode -eq "Alternar") {
            $global:AnimToggle = -not $global:AnimToggle
            & $Script:DrawCurrentIcon -forceGlyph:$global:AnimToggle
        }
    })

    # Gerenciamento de ativação do timer de animação
    $Script:ConfigureAnimationTimer = {
        if ($global:DisplayMode -eq "Alternar") {
            if (-not $animTimer.Enabled) { $animTimer.Start() }
        } else {
            if ($animTimer.Enabled) { $animTimer.Stop() }
            & $Script:DrawCurrentIcon
        }
    }

    # Ação: Atualizar Agora
    $refreshItem.Add_Click({
        & $Script:UpdateTrayStatus
    })

    # Ação: Trocar de Dispositivo
    $changeDevItem.Add_Click({
        $timer.Stop()
        $animTimer.Stop()
        if ($global:ConsoleHwnd -ne [IntPtr]::Zero) {
            $win32Type::ShowWindowAsync($global:ConsoleHwnd, 9) | Out-Null
            $win32Type::ShowWindowAsync($global:ConsoleHwnd, 5) | Out-Null
            $win32Type::SetForegroundWindow($global:ConsoleHwnd) | Out-Null
        }
        $oldMac = $global:SelectedMac
        $oldName = $global:SelectedName
        $wasAutostart = Test-DeviceAutostart $oldName

        Show-DeviceSelectionMenu

        if ($global:ConsoleHwnd -ne [IntPtr]::Zero) {
            $win32Type::ShowWindowAsync($global:ConsoleHwnd, 0) | Out-Null
        }

        # Se trocou de dispositivo, migra o mutex e o atalho de autoinicialização
        if ($global:SelectedMac -ne $oldMac) {
            if ($script:appMutex) {
                try { $script:appMutex.ReleaseMutex() } catch {}
                $script:appMutex.Dispose()
            }
            $mutexName = "Local\BluetoothBatteryMonitor_Mutex_$($global:SelectedMac)"
            $script:createdMutex = $false
            $script:appMutex = New-Object System.Threading.Mutex($true, $mutexName, [ref]$script:createdMutex)

            if ($wasAutostart) {
                Set-DeviceAutostart $oldMac $oldName $false | Out-Null
                Set-DeviceAutostart $global:SelectedMac $global:SelectedName $true | Out-Null
            }
        }

        $headerItem.Text = "$($global:SelectedName) (Atualizando...)"
        & $Script:UpdateTrayStatus
        & $Script:ConfigureAnimationTimer
        $timer.Start()
    })

    # Ação: Seleção de Modo de Exibição
    foreach ($dmItem in $displayMenuItems) {
        $dmItem.Add_Click({
            param($sender, $e)
            foreach ($sub in $displayMenuItems) { $sub.Checked = $false }
            $sender.Checked = $true
            $global:DisplayMode = [string]$sender.Tag
            Save-Config
            & $Script:ConfigureAnimationTimer
        })
    }

    # Ação: Seleção de Ícone do Dispositivo
    foreach ($icItem in $iconMenuItems) {
        $icItem.Add_Click({
            param($sender, $e)
            foreach ($sub in $iconMenuItems) { $sub.Checked = $false }
            $sender.Checked = $true
            $global:DeviceIcon = [string]$sender.Tag
            Save-Config
            & $Script:DrawCurrentIcon
        })
    }

    # Ação: Troca de Intervalo de Verificação
    foreach ($mItem in $intervalMenuItems) {
        $mItem.Add_Click({
            param($sender, $e)
            foreach ($sub in $intervalMenuItems) { $sub.Checked = $false }
            $sender.Checked = $true
            $global:UpdateIntervalSec = [int]$sender.Tag
            $isLow = ($global:CachedConnected -and $null -ne $global:CachedBattery -and $global:CachedBattery -le 20)
            $effSec = if ($isLow) { 60 } else { $global:UpdateIntervalSec }
            $timer.Interval = $effSec * 1000
            Save-Config
        })
    }

    # Ação: Sair
    $exitItem.Add_Click({
        $animTimer.Stop()
        $animTimer.Dispose()
        $timer.Stop()
        $timer.Dispose()
        $notifyIcon.Visible = $false
        $notifyIcon.Dispose()
        if ($global:CurrentHIcon -ne [IntPtr]::Zero) {
            $win32Type::DestroyIcon($global:CurrentHIcon) | Out-Null
        }
        if ($script:appMutex) {
            try { $script:appMutex.ReleaseMutex() } catch {}
            $script:appMutex.Dispose()
        }
        $appContext.ExitThread()
        [System.Windows.Forms.Application]::Exit()
    })

    # Duplo clique no ícone atualiza imediatamente
    $notifyIcon.Add_DoubleClick({
        & $Script:UpdateTrayStatus
    })

    # Inicialização
    & $Script:UpdateTrayStatus
    & $Script:ConfigureAnimationTimer
    $timer.Start()

    [System.Windows.Forms.Application]::Run($appContext)
}

try {
    Start-TrayApp -Quiet:$Quiet -TargetMac $Mac -TargetName $Name
} catch {
    Write-Host ""
    Write-Host "Erro inesperado ao executar o monitor de bateria:" -ForegroundColor Red
    Write-Host $_.Exception.ToString() -ForegroundColor Yellow
    Write-Host ""
    Read-Host "Pressione ENTER para fechar"
}
