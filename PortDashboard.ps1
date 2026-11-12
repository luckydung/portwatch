#Requires -Version 5.1
# Port Dashboard - liet ke cac port dang mo tren may va cho phep dung ung dung chiem port.
# Chay bang file PortDashboard.bat (double-click).

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Data

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# ---------- Code doc du lieu: chay o luong nen (xem phan "Luong nen") ----------
$portDataInit = {
$knownPorts = @{
    21    = 'Truyền file (FTP)'
    22    = 'Điều khiển từ xa (SSH)'
    25    = 'Gửi email (SMTP)'
    53    = 'Phân giải tên miền (DNS)'
    80    = 'Web server (HTTP)'
    135   = 'Dịch vụ Windows (RPC)'
    139   = 'Chia sẻ file Windows (NetBIOS)'
    443   = 'Web server bảo mật (HTTPS)'
    445   = 'Chia sẻ file Windows (SMB)'
    1433  = 'Cơ sở dữ liệu SQL Server'
    1521  = 'Cơ sở dữ liệu Oracle'
    3000  = 'Web dev server (React / Node.js)'
    3306  = 'Cơ sở dữ liệu MySQL'
    3389  = 'Remote Desktop'
    4200  = 'Web dev server (Angular)'
    5000  = 'Web dev server (Flask / .NET)'
    5173  = 'Web dev server (Vite)'
    5432  = 'Cơ sở dữ liệu PostgreSQL'
    5672  = 'Hàng đợi tin nhắn RabbitMQ'
    6379  = 'Bộ nhớ đệm Redis'
    8000  = 'Web dev server'
    8080  = 'Web server (Tomcat / Spring Boot)'
    8081  = 'Web server / Metro (React Native)'
    8443  = 'Web server bảo mật (HTTPS phụ)'
    9000  = 'Web server / SonarQube'
    9092  = 'Kafka'
    9200  = 'Elasticsearch'
    27017 = 'Cơ sở dữ liệu MongoDB'
}

$systemNames = @('System', 'Idle', 'svchost', 'lsass', 'services', 'wininit',
                 'spoolsv', 'smss', 'csrss', 'winlogon', 'Registry', 'Memory Compression')

$script:descCache = @{}
}
$script:rows = @()

# ---------- Cai dat (luu o %APPDATA%\PortDashboard\settings.json) ----------
$settingsPath = Join-Path $env:APPDATA 'PortDashboard\settings.json'
$defaultSettings = [ordered]@{
    AutoRefresh     = $true    # tu dong lam moi
    RefreshSeconds  = 5        # chu ky lam moi (giay)
    ShowSystemPorts = $false   # hien port he thong
    ShowMachineInfo = $true    # hien nut "Thong tin may"
    AlwaysOnTop     = $false   # cua so luon nam tren
}
$minRefresh = 1
$maxRefresh = 3600

function Read-Settings {
    $s = [ordered]@{}
    foreach ($k in $defaultSettings.Keys) { $s[$k] = $defaultSettings[$k] }
    try {
        if (Test-Path -LiteralPath $settingsPath) {
            $json = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($k in $defaultSettings.Keys) {
                $prop = $json.PSObject.Properties[$k]
                if (-not $prop -or $null -eq $prop.Value) { continue }
                if ($defaultSettings[$k] -is [bool]) { $s[$k] = [bool]$prop.Value }
                else { $s[$k] = [int]$prop.Value }
            }
        }
    } catch { }   # file hong -> dung gia tri da doc duoc / mac dinh
    $s.RefreshSeconds = [Math]::Min($maxRefresh, [Math]::Max($minRefresh, [int]$s.RefreshSeconds))
    return $s
}

function Save-Settings {
    try {
        $dir = Split-Path -Parent $settingsPath
        if (-not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Path $dir -Force) }
        $script:settings | ConvertTo-Json | Set-Content -LiteralPath $settingsPath -Encoding UTF8
        return $true
    } catch {
        return $false
    }
}

$script:settings = Read-Settings

# ---------- Thong tin may (chay o luong nen) ----------
$infoInit = {
function Get-MachineInfo {
    $info = [ordered]@{
        'Tên máy'    = $env:COMPUTERNAME
        'Người dùng' = if ($env:USERDOMAIN) { "$env:USERDOMAIN\$env:USERNAME" } else { $env:USERNAME }
    }

    $os = $null
    try { $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop } catch { }
    if ($os) {
        $info['Hệ điều hành'] = ('{0} ({1})' -f ([string]$os.Caption).Replace('Microsoft ', '').Trim(), $os.Version)
    }

    $ips = @()
    try {
        foreach ($nic in [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
            if ($nic.OperationalStatus -ne 'Up' -or $nic.NetworkInterfaceType -eq 'Loopback') { continue }
            foreach ($ua in $nic.GetIPProperties().UnicastAddresses) {
                $a = $ua.Address
                if ($a.AddressFamily -eq 'InterNetwork' -and -not $a.ToString().StartsWith('169.254.')) { $ips += $a.ToString() }
            }
        }
    } catch { }
    $info['IP'] = if ($ips.Count) { ($ips | Sort-Object -Unique) -join ', ' } else { '(không có mạng)' }

    if (-not $script:cpuName) {
        try {
            $script:cpuName = ([string](Get-ItemProperty 'HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0' -ErrorAction Stop).ProcessorNameString).Trim() -replace '\s+', ' '
        } catch { $script:cpuName = '(không rõ)' }
    }
    $info['CPU'] = "$($script:cpuName) - $([Environment]::ProcessorCount) luồng"

    if ($os) {
        $totalGb = $os.TotalVisibleMemorySize / 1MB   # don vi goc la KB
        $usedGb  = ($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB
        if ($totalGb -gt 0) {
            $info['RAM'] = '{0:N1} / {1:N1} GB ({2:N0}%)' -f $usedGb, $totalGb, ($usedGb / $totalGb * 100)
        }
        $up = (Get-Date) - $os.LastBootUpTime
        $info['Đã bật'] = if ($up.TotalDays -ge 1) { '{0} ngày {1} giờ' -f [int][Math]::Floor($up.TotalDays), $up.Hours }
                          elseif ($up.TotalHours -ge 1) { '{0} giờ {1} phút' -f $up.Hours, $up.Minutes }
                          else { '{0} phút' -f $up.Minutes }
    }
    return $info
}
}

$portFuncInit = {
function Get-FriendlyName([string]$path) {
    if (-not $path) { return $null }
    if ($script:descCache.ContainsKey($path)) { return $script:descCache[$path] }
    $d = $null
    try { $d = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($path).FileDescription } catch { }
    if ($d) { $d = $d.Trim() }
    $script:descCache[$path] = $d
    return $d
}

function Get-PortRows {
    $procs = @{}
    try {
        Get-CimInstance Win32_Process -ErrorAction Stop | ForEach-Object { $procs[[int]$_.ProcessId] = $_ }
    } catch { }

    $conns = @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue)
    $result = foreach ($g in ($conns | Group-Object LocalPort, OwningProcess)) {
        $first  = $g.Group[0]
        $port   = [int]$first.LocalPort
        $procId = [int]$first.OwningProcess
        $p      = $procs[$procId]

        $exe  = if ($p) { [string]$p.Name } elseif ($procId -eq 0) { 'Idle' } else { '(không rõ)' }
        $path = if ($p -and $p.ExecutablePath) { [string]$p.ExecutablePath } else { '' }
        $base = $exe -replace '\.exe$', ''

        $friendly = Get-FriendlyName $path
        $app = if ($friendly -and $friendly -ne $base) { "$friendly ($exe)" } else { $exe }

        $addrs = @($g.Group | ForEach-Object { [string]$_.LocalAddress } | Sort-Object -Unique)
        $loop  = @($addrs | Where-Object { $_ -eq '127.0.0.1' -or $_ -eq '::1' })
        $scope = if ($addrs -contains '0.0.0.0' -or $addrs -contains '::') { 'Máy khác truy cập được' }
                 elseif ($loop.Count -eq $addrs.Count) { 'Chỉ máy này' }
                 else { $addrs -join ', ' }

        $isSystem = ($procId -le 4) -or ($systemNames -contains $base) -or
                    ($path -and $path.StartsWith($env:windir, [StringComparison]::OrdinalIgnoreCase))

        $desc = if ($knownPorts.ContainsKey($port)) { $knownPorts[$port] }
                elseif ($isSystem) { 'Dịch vụ hệ thống Windows' }
                else { '' }

        [pscustomobject]@{
            Port = $port; App = $app; Desc = $desc; Scope = $scope
            PID = $procId; Path = $path; IsSystem = [bool]$isSystem
        }
    }
    return @($result | Sort-Object Port, PID)
}
}

# ---------- Giao dien ----------
$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Port Dashboard" Width="1040" Height="640" MinWidth="760" MinHeight="420"
        WindowStartupLocation="CenterScreen" Background="#F4F6F9" FontFamily="Segoe UI" FontSize="13">
  <Window.Resources>
    <Style x:Key="Ico" TargetType="TextBlock">
      <Setter Property="FontFamily" Value="Segoe MDL2 Assets"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="Margin" Value="0,0,7,0"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
    </Style>
    <Style TargetType="Button">
      <Setter Property="Padding" Value="14,7"/>
      <Setter Property="Margin" Value="6,0,0,0"/>
      <Setter Property="Background" Value="White"/>
      <Setter Property="BorderBrush" Value="#C9D1DC"/>
      <Setter Property="Cursor" Value="Hand"/>
    </Style>
  </Window.Resources>
  <Grid Margin="16">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <DockPanel Grid.Row="0" Margin="0,0,0,12">
      <Image x:Name="imgLogo" DockPanel.Dock="Left" Width="40" Height="40" Margin="0,0,12,0" VerticalAlignment="Center"/>
      <Button x:Name="btnSettings" DockPanel.Dock="Right" VerticalAlignment="Center" ToolTip="Mở phần cài đặt">
        <StackPanel Orientation="Horizontal">
          <TextBlock Style="{StaticResource Ico}" Text="&#xE713;"/>
          <TextBlock Text="Cài đặt"/>
        </StackPanel>
      </Button>
      <Button x:Name="btnInfo" DockPanel.Dock="Right" VerticalAlignment="Center" ToolTip="Xem tên máy, IP, CPU, RAM...">
        <StackPanel Orientation="Horizontal">
          <TextBlock Style="{StaticResource Ico}" Text="&#xE7F8;"/>
          <TextBlock Text="Thông tin máy"/>
        </StackPanel>
      </Button>
      <StackPanel VerticalAlignment="Center">
      <TextBlock Text="Các port đang mở trên máy" FontSize="20" FontWeight="SemiBold" Foreground="#1F2937"/>
      <TextBlock Text="Mỗi dòng là một ứng dụng đang chiếm một port. Chọn dòng rồi bấm &quot;Dừng ứng dụng&quot; để giải phóng port."
                 Foreground="#6B7280" Margin="0,4,0,0"/>
      </StackPanel>
    </DockPanel>

    <DockPanel Grid.Row="2" Margin="0,0,0,10" LastChildFill="True">
      <Button x:Name="btnRefresh" DockPanel.Dock="Right">
        <StackPanel Orientation="Horizontal">
          <TextBlock Style="{StaticResource Ico}" Text="&#xE72C;"/>
          <TextBlock Text="Làm mới"/>
        </StackPanel>
      </Button>
      <CheckBox x:Name="chkAuto" DockPanel.Dock="Right" Content="Tự làm mới (5 giây)" IsChecked="True"
                VerticalAlignment="Center" Margin="14,0,0,0"/>
      <CheckBox x:Name="chkSystem" DockPanel.Dock="Right" Content="Hiện port hệ thống"
                VerticalAlignment="Center" Margin="14,0,0,0"/>
      <TextBlock DockPanel.Dock="Left" FontFamily="Segoe MDL2 Assets" Text="&#xE721;" FontSize="15" VerticalAlignment="Center" Margin="2,0,8,0" Foreground="#374151"/>
      <TextBox x:Name="txtSearch" Padding="6,5" VerticalContentAlignment="Center" BorderBrush="#C9D1DC"
               ToolTip="Gõ số port hoặc tên ứng dụng, ví dụ: 8080 hoặc java"/>
    </DockPanel>

    <DataGrid x:Name="grid" Grid.Row="3" AutoGenerateColumns="False" IsReadOnly="True" SelectionMode="Single"
              CanUserAddRows="False" CanUserDeleteRows="False" HeadersVisibility="Column"
              GridLinesVisibility="Horizontal" HorizontalGridLinesBrush="#E5E7EB"
              Background="White" BorderBrush="#D5DBE3" RowHeight="30" ColumnHeaderHeight="34"
              AlternatingRowBackground="#FAFBFC">
      <DataGrid.RowStyle>
        <Style TargetType="DataGridRow">
          <Style.Triggers>
            <DataTrigger Binding="{Binding IsSystem}" Value="True">
              <Setter Property="Foreground" Value="#9CA3AF"/>
            </DataTrigger>
          </Style.Triggers>
        </Style>
      </DataGrid.RowStyle>
      <DataGrid.CellStyle>
        <Style TargetType="DataGridCell">
          <Setter Property="BorderThickness" Value="0"/>
          <Setter Property="Padding" Value="8,0"/>
          <Setter Property="Template">
            <Setter.Value>
              <ControlTemplate TargetType="DataGridCell">
                <Border Padding="{TemplateBinding Padding}" Background="{TemplateBinding Background}">
                  <ContentPresenter VerticalAlignment="Center"/>
                </Border>
              </ControlTemplate>
            </Setter.Value>
          </Setter>
        </Style>
      </DataGrid.CellStyle>
      <DataGrid.Columns>
        <DataGridTextColumn Header="Port" Binding="{Binding Port}" Width="80" FontWeight="SemiBold"/>
        <DataGridTextColumn Header="Ứng dụng" Binding="{Binding App}" Width="250"/>
        <DataGridTextColumn Header="Dùng để làm gì" Binding="{Binding Desc}" Width="230"/>
        <DataGridTextColumn Header="Phạm vi" Binding="{Binding Scope}" Width="160"/>
        <DataGridTextColumn Header="PID" Binding="{Binding PID}" Width="70"/>
        <DataGridTextColumn Header="Đường dẫn" Binding="{Binding Path}" Width="*"/>
      </DataGrid.Columns>
    </DataGrid>

    <DockPanel Grid.Row="4" Margin="0,12,0,0" LastChildFill="True">
      <Button x:Name="btnKill" DockPanel.Dock="Right"
              Background="#DC2626" Foreground="White" BorderBrush="#B91C1C" FontWeight="SemiBold">
        <StackPanel Orientation="Horizontal">
          <TextBlock Style="{StaticResource Ico}" Text="&#xE71A;"/>
          <TextBlock Text="Dừng ứng dụng"/>
        </StackPanel>
      </Button>
      <Button x:Name="btnFolder" DockPanel.Dock="Right">
        <StackPanel Orientation="Horizontal">
          <TextBlock Style="{StaticResource Ico}" Text="&#xE838;"/>
          <TextBlock Text="Mở thư mục chứa"/>
        </StackPanel>
      </Button>
      <Button x:Name="btnAdmin" DockPanel.Dock="Right">
        <StackPanel Orientation="Horizontal">
          <TextBlock Style="{StaticResource Ico}" Text="&#xE7EF;"/>
          <TextBlock Text="Chạy lại với quyền Admin"/>
        </StackPanel>
      </Button>
      <TextBlock x:Name="txtStatus" VerticalAlignment="Center" Foreground="#6B7280" TextTrimming="CharacterEllipsis"/>
    </DockPanel>
  </Grid>
</Window>
'@

$window = [Windows.Markup.XamlReader]::Parse($xaml)
$grid      = $window.FindName('grid')
$txtSearch = $window.FindName('txtSearch')
$chkSystem = $window.FindName('chkSystem')
$chkAuto   = $window.FindName('chkAuto')
$btnRefresh = $window.FindName('btnRefresh')
$btnKill   = $window.FindName('btnKill')
$btnFolder = $window.FindName('btnFolder')
$btnAdmin  = $window.FindName('btnAdmin')
$txtStatus = $window.FindName('txtStatus')
$btnSettings = $window.FindName('btnSettings')
$btnInfo   = $window.FindName('btnInfo')

$settingsXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Cài đặt" Width="440" SizeToContent="Height" ResizeMode="NoResize" ShowInTaskbar="False"
        WindowStartupLocation="CenterOwner" Background="#F4F6F9" FontFamily="Segoe UI" FontSize="13">
  <Window.Resources>
    <Style TargetType="Button">
      <Setter Property="Padding" Value="16,7"/>
      <Setter Property="Margin" Value="6,0,0,0"/>
      <Setter Property="MinWidth" Value="80"/>
      <Setter Property="Background" Value="White"/>
      <Setter Property="BorderBrush" Value="#C9D1DC"/>
      <Setter Property="Cursor" Value="Hand"/>
    </Style>
    <Style x:Key="Head" TargetType="TextBlock">
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Foreground" Value="#1F2937"/>
      <Setter Property="Margin" Value="0,0,0,8"/>
    </Style>
    <Style TargetType="CheckBox">
      <Setter Property="Margin" Value="0,0,0,8"/>
    </Style>
  </Window.Resources>
  <StackPanel Margin="18">
    <Border Background="White" BorderBrush="#D5DBE3" BorderThickness="1" CornerRadius="4" Padding="14,12,14,6" Margin="0,0,0,10">
      <StackPanel>
        <TextBlock Style="{StaticResource Head}" Text="Làm mới dữ liệu"/>
        <CheckBox x:Name="chkSetAuto" Content="Tự động làm mới danh sách port"/>
        <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
          <TextBlock Text="Làm mới mỗi" VerticalAlignment="Center"/>
          <ComboBox x:Name="cboInterval" IsEditable="True" Width="76" Margin="8,0" VerticalContentAlignment="Center"
                    ToolTip="Chọn sẵn hoặc tự gõ số giây (1 - 3600)">
            <ComboBoxItem Content="2"/>
            <ComboBoxItem Content="5"/>
            <ComboBoxItem Content="10"/>
            <ComboBoxItem Content="30"/>
            <ComboBoxItem Content="60"/>
          </ComboBox>
          <TextBlock Text="giây" VerticalAlignment="Center"/>
        </StackPanel>
      </StackPanel>
    </Border>
    <Border Background="White" BorderBrush="#D5DBE3" BorderThickness="1" CornerRadius="4" Padding="14,12,14,6" Margin="0,0,0,10">
      <StackPanel>
        <TextBlock Style="{StaticResource Head}" Text="Hiển thị"/>
        <CheckBox x:Name="chkSetInfo" Content="Hiện nút &quot;Thông tin máy&quot; (tên máy, IP, CPU, RAM...)"/>
        <CheckBox x:Name="chkSetSystem" Content="Hiện port hệ thống của Windows"/>
        <CheckBox x:Name="chkSetTop" Content="Cửa sổ luôn nằm trên các cửa sổ khác"/>
      </StackPanel>
    </Border>
    <DockPanel LastChildFill="False" Margin="0,4,0,0">
      <Button x:Name="btnSetDefault" DockPanel.Dock="Left" Margin="0" Content="Về mặc định"/>
      <Button x:Name="btnSetCancel" DockPanel.Dock="Right" Content="Hủy" IsCancel="True"/>
      <Button x:Name="btnSetSave" DockPanel.Dock="Right" Content="Lưu" IsDefault="True"
              Background="#2563EB" Foreground="White" BorderBrush="#1D4ED8" FontWeight="SemiBold"/>
    </DockPanel>
  </StackPanel>
</Window>
'@

function New-AppIcon {
    # Ve icon bang code: nen xanh bo goc, 3 dong trang voi cham trang thai
    $size = 64
    $blue  = New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(37, 99, 235))
    $green = New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(74, 222, 128))
    $white = [Windows.Media.Brushes]::White
    $dv = New-Object Windows.Media.DrawingVisual
    $dc = $dv.RenderOpen()
    $dc.DrawRoundedRectangle($blue, $null, [Windows.Rect]::new(0, 0, $size, $size), 14, 14)
    foreach ($i in 0..2) {
        $y = 15 + $i * 13
        $dot = if ($i -eq 0) { $green } else { $white }
        $dc.DrawEllipse($dot, $null, [Windows.Point]::new(17, $y + 4), 4, 4)
        $dc.DrawRoundedRectangle($white, $null, [Windows.Rect]::new(26, $y, 25, 8), 4, 4)
    }
    $dc.Close()
    $bmp = New-Object Windows.Media.Imaging.RenderTargetBitmap $size, $size, 96, 96, ([Windows.Media.PixelFormats]::Pbgra32)
    $bmp.Render($dv)
    $bmp.Freeze()
    return $bmp
}

try {
    $appIcon = New-AppIcon
    $window.Icon = $appIcon
    $window.FindName('imgLogo').Source = $appIcon
} catch { }

if ($isAdmin) {
    $window.Title = 'Port Dashboard (Administrator)'
    $btnAdmin.Visibility = 'Collapsed'
}

$table = New-Object System.Data.DataTable
[void]$table.Columns.Add('Port', [int])
[void]$table.Columns.Add('App', [string])
[void]$table.Columns.Add('Desc', [string])
[void]$table.Columns.Add('Scope', [string])
[void]$table.Columns.Add('PID', [int])
[void]$table.Columns.Add('Path', [string])
[void]$table.Columns.Add('IsSystem', [bool])
$grid.ItemsSource = $table.DefaultView

function Update-Grid {
    $keep = $null
    if ($grid.SelectedItem) { $keep = '{0}|{1}' -f $grid.SelectedItem['Port'], $grid.SelectedItem['PID'] }

    $table.Rows.Clear()
    $q = $txtSearch.Text.Trim()
    $showSystem = [bool]$chkSystem.IsChecked
    $hidden = 0
    foreach ($r in $script:rows) {
        if ($r.IsSystem -and -not $showSystem) { $hidden++; continue }
        if ($q) {
            $hay = "$($r.Port) $($r.App) $($r.Desc) $($r.PID) $($r.Path)"
            if ($hay.IndexOf($q, [StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
        }
        [void]$table.Rows.Add($r.Port, $r.App, $r.Desc, $r.Scope, $r.PID, $r.Path, $r.IsSystem)
    }

    if ($keep) {
        foreach ($v in $table.DefaultView) {
            if (('{0}|{1}' -f $v['Port'], $v['PID']) -eq $keep) { $grid.SelectedItem = $v; break }
        }
    }

    $status = "Đang hiện $($table.Rows.Count) port"
    if ($hidden -gt 0) { $status += " - đã ẩn $hidden port hệ thống" }
    $status += " - cập nhật lúc $(Get-Date -Format 'HH:mm:ss')"
    if (-not $isAdmin) { $status += ' - chưa có quyền Admin' }
    if ($script:statusOverride) { $status = $script:statusOverride; $script:statusOverride = $null }
    $txtStatus.Text = $status
}

$infoXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Thông tin máy" Width="520" SizeToContent="Height" ResizeMode="NoResize" ShowInTaskbar="False"
        WindowStartupLocation="CenterOwner" Background="#F4F6F9" FontFamily="Segoe UI" FontSize="13">
  <Window.Resources>
    <Style TargetType="Button">
      <Setter Property="Padding" Value="16,7"/>
      <Setter Property="Margin" Value="6,0,0,0"/>
      <Setter Property="MinWidth" Value="80"/>
      <Setter Property="Background" Value="White"/>
      <Setter Property="BorderBrush" Value="#C9D1DC"/>
      <Setter Property="Cursor" Value="Hand"/>
    </Style>
  </Window.Resources>
  <StackPanel Margin="18">
    <Border Background="White" BorderBrush="#D5DBE3" BorderThickness="1" CornerRadius="4" Padding="14,8" Margin="0,0,0,12">
      <Grid x:Name="gridInfo">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>
      </Grid>
    </Border>
    <DockPanel LastChildFill="True">
      <Button x:Name="btnInfoClose" DockPanel.Dock="Right" Content="Đóng" IsCancel="True"/>
      <Button x:Name="btnInfoCopy" DockPanel.Dock="Right" Content="Sao chép"/>
      <TextBlock x:Name="txtInfoNote" VerticalAlignment="Center" Foreground="#6B7280"/>
    </DockPanel>
  </StackPanel>
</Window>
'@

function Show-InfoDialog {
    $dlg = [Windows.Markup.XamlReader]::Parse($infoXaml)
    $dlg.Owner = $window
    if ($window.Icon) { $dlg.Icon = $window.Icon }
    $script:infoUi = @{
        Grid = $dlg.FindName('gridInfo'); Note = $dlg.FindName('txtInfoNote')
        Values = @{}; Info = $null; Loading = $true
    }
    $script:infoUi.Note.Text = 'Đang đọc thông tin...'
    Start-InfoRefresh

    # RAM / IP / thoi gian bat may thay doi lien tuc -> cap nhat khi dialog dang mo
    $infoTimer = New-Object Windows.Threading.DispatcherTimer
    $infoTimer.Interval = [TimeSpan]::FromSeconds(3)
    $infoTimer.Add_Tick({ Start-InfoRefresh })
    $infoTimer.Start()

    $dlg.FindName('btnInfoCopy').Add_Click({
        $ui = $script:infoUi
        if (-not $ui -or -not $ui.Info) { return }
        $text = ($ui.Info.GetEnumerator() | ForEach-Object { "$($_.Key): $($_.Value)" }) -join "`r`n"
        try {
            [Windows.Clipboard]::SetText($text)
            $ui.Note.Text = 'Đã sao chép vào clipboard.'
        } catch {
            $ui.Note.Text = 'Không sao chép được, thử lại.'
        }
    })

    try { [void]$dlg.ShowDialog() } finally { $infoTimer.Stop(); $script:infoUi = $null }
}

$infoLabelBrush = New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(107, 114, 128))
$infoValueBrush = New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(31, 41, 55))

# Do ket qua tu luong nen vao dialog (bo qua neu dialog da dong)
function Update-InfoDialog($info) {
    $ui = $script:infoUi
    if (-not $ui -or -not $info) { return }
    $ui.Info = $info
    if ($ui.Loading) { $ui.Loading = $false; $ui.Note.Text = '' }
    foreach ($k in $info.Keys) {
        if (-not $ui.Values.ContainsKey($k)) {
            $row = $ui.Grid.RowDefinitions.Count
            $rd = New-Object Windows.Controls.RowDefinition
            $rd.Height = [Windows.GridLength]::Auto
            $ui.Grid.RowDefinitions.Add($rd)

            $lbl = New-Object Windows.Controls.TextBlock
            $lbl.Text = $k
            $lbl.Foreground = $infoLabelBrush
            $lbl.Margin = [Windows.Thickness]::new(0, 5, 20, 5)
            [Windows.Controls.Grid]::SetRow($lbl, $row)
            [Windows.Controls.Grid]::SetColumn($lbl, 0)

            $val = New-Object Windows.Controls.TextBlock
            $val.FontWeight = 'SemiBold'
            $val.Foreground = $infoValueBrush
            $val.TextWrapping = 'Wrap'
            $val.Margin = [Windows.Thickness]::new(0, 5, 0, 5)
            [Windows.Controls.Grid]::SetRow($val, $row)
            [Windows.Controls.Grid]::SetColumn($val, 1)

            [void]$ui.Grid.Children.Add($lbl)
            [void]$ui.Grid.Children.Add($val)
            $ui.Values[$k] = $val
        }
        $ui.Values[$k].Text = [string]$info[$k]
    }
}

function Start-InfoRefresh {
    [void](Start-Work $infoWorker 'Get-MachineInfo' {
        param($res, $err)
        if (-not $err -and $res -and $res.Count) { Update-InfoDialog $res[0] }
    })
}

# ---------- Luong nen ----------
# Cac lenh doc port / tien trinh / thong tin may mat 0.5 - 2 giay. Chay chung trong runspace rieng
# de cua so khong bi dung; luong giao dien chi nhan ket qua qua $pollTimer.
function New-Worker([scriptblock[]]$init) {
    $rs = [runspacefactory]::CreateRunspace()
    $rs.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    foreach ($sb in $init) {
        [void]$ps.AddScript($sb.ToString()).Invoke()
        $ps.Commands.Clear()
    }
    return @{ PS = $ps; RS = $rs; Pending = $null; OnDone = $null }
}

$portWorker = New-Worker $portDataInit, $portFuncInit
$infoWorker = New-Worker $infoInit
$workers = @($portWorker, $infoWorker)

$pollTimer = New-Object Windows.Threading.DispatcherTimer
$pollTimer.Interval = [TimeSpan]::FromMilliseconds(100)
$pollTimer.Add_Tick({
    $busy = $false
    foreach ($w in $workers) {
        if (-not $w.Pending) { continue }
        if (-not $w.Pending.IsCompleted) { $busy = $true; continue }
        $handle = $w.Pending; $done = $w.OnDone
        $res = $null; $err = $null
        try { $res = $w.PS.EndInvoke($handle) } catch { $err = $_ }
        $w.PS.Streams.Error.Clear()
        $w.Pending = $null; $w.OnDone = $null
        & $done $res $err
        if ($w.Pending) { $busy = $true }   # callback vua giao viec moi
    }
    if (-not $busy) { $pollTimer.Stop() }
})

# Giao viec cho luong nen; $onDone($res, $err) duoc goi tren luong giao dien khi xong.
function Start-Work($worker, [string]$command, [scriptblock]$onDone) {
    if ($worker.Pending) { return $false }
    $worker.PS.Commands.Clear()
    [void]$worker.PS.AddScript($command)
    $worker.OnDone = $onDone
    $worker.Pending = $worker.PS.BeginInvoke()
    $pollTimer.Start()
    return $true
}

$script:refreshAgain = $false
$script:statusOverride = $null

function Update-Data {
    # Dang doc do -> danh dau de doc lai ngay khi xong (du lieu dang doc co the da cu)
    if ($portWorker.Pending) { $script:refreshAgain = $true; return }
    [void](Start-Work $portWorker 'Get-PortRows' {
        param($res, $err)
        if ($err) {
            $txtStatus.Text = "Lỗi khi đọc danh sách port: $($err.Exception.Message)"
        } else {
            $script:rows = @($res)
            Update-Grid
        }
        if ($script:refreshAgain) { $script:refreshAgain = $false; Update-Data }
    })
}

$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Add_Tick({ if (-not $portWorker.Pending) { Update-Data } })

# Sau khi dung ung dung: doi 0.4 giay cho Windows giai phong port roi moi doc lai
$script:killMsg = $null
$killTimer = New-Object Windows.Threading.DispatcherTimer
$killTimer.Interval = [TimeSpan]::FromMilliseconds(400)
$killTimer.Add_Tick({
    $killTimer.Stop()
    $script:statusOverride = $script:killMsg
    Update-Data
})

# Ap cac gia tri trong $script:settings len giao dien
function Update-FromSettings {
    $s = $script:settings
    $timer.Stop()
    $timer.Interval = [TimeSpan]::FromSeconds($s.RefreshSeconds)
    $chkAuto.Content = "Tự làm mới ($($s.RefreshSeconds) giây)"
    $chkAuto.IsChecked = $s.AutoRefresh
    if ($s.AutoRefresh) { $timer.Start() }

    $chkSystem.IsChecked = $s.ShowSystemPorts
    $window.Topmost = $s.AlwaysOnTop
    $btnInfo.Visibility = if ($s.ShowMachineInfo) { 'Visible' } else { 'Collapsed' }
    Update-Grid
}

function Show-SettingsDialog {
    $dlg = [Windows.Markup.XamlReader]::Parse($settingsXaml)
    $dlg.Owner = $window
    if ($window.Icon) { $dlg.Icon = $window.Icon }
    $cAuto   = $dlg.FindName('chkSetAuto')
    $cboInt  = $dlg.FindName('cboInterval')
    $cInfo   = $dlg.FindName('chkSetInfo')
    $cSystem = $dlg.FindName('chkSetSystem')
    $cTop    = $dlg.FindName('chkSetTop')

    $fill = {
        param($s)
        $cAuto.IsChecked   = $s.AutoRefresh
        $cboInt.Text       = [string]$s.RefreshSeconds
        $cboInt.IsEnabled  = [bool]$s.AutoRefresh
        $cInfo.IsChecked   = $s.ShowMachineInfo
        $cSystem.IsChecked = $s.ShowSystemPorts
        $cTop.IsChecked    = $s.AlwaysOnTop
    }
    & $fill $script:settings

    $cAuto.Add_Click({ $cboInt.IsEnabled = [bool]$cAuto.IsChecked })
    $dlg.FindName('btnSetDefault').Add_Click({ & $fill $defaultSettings })

    $dlg.FindName('btnSetSave').Add_Click({
        $sec = 0
        $ok = [int]::TryParse($cboInt.Text.Trim(), [ref]$sec)
        if (-not $ok -or $sec -lt $minRefresh -or $sec -gt $maxRefresh) {
            [void][Windows.MessageBox]::Show($dlg, "Thời gian làm mới phải là số nguyên từ $minRefresh đến $maxRefresh giây.", 'Cài đặt', 'OK', 'Warning')
            $cboInt.Focus()
            return
        }
        $script:settings.AutoRefresh     = [bool]$cAuto.IsChecked
        $script:settings.RefreshSeconds  = $sec
        $script:settings.ShowMachineInfo = [bool]$cInfo.IsChecked
        $script:settings.ShowSystemPorts = [bool]$cSystem.IsChecked
        $script:settings.AlwaysOnTop     = [bool]$cTop.IsChecked
        $dlg.DialogResult = $true
    })

    if ($dlg.ShowDialog()) {
        $saved = Save-Settings
        Update-FromSettings
        if (-not $saved) {
            $txtStatus.Text = "Đã áp dụng cài đặt nhưng không lưu được vào $settingsPath"
        }
    }
}

# ---------- Su kien ----------
$btnRefresh.Add_Click({ Update-Data })
$btnSettings.Add_Click({ Show-SettingsDialog })
$btnInfo.Add_Click({ Show-InfoDialog })
$txtSearch.Add_TextChanged({ Update-Grid })
$chkSystem.Add_Click({
    $script:settings.ShowSystemPorts = [bool]$chkSystem.IsChecked
    [void](Save-Settings)
    Update-Grid
})
$chkAuto.Add_Click({
    $script:settings.AutoRefresh = [bool]$chkAuto.IsChecked
    [void](Save-Settings)
    if ($chkAuto.IsChecked) { $timer.Start() } else { $timer.Stop() }
})

$btnKill.Add_Click({
    $sel = $grid.SelectedItem
    if (-not $sel) {
        [void][Windows.MessageBox]::Show($window, 'Hãy chọn một dòng trong bảng trước.', 'Port Dashboard', 'OK', 'Information')
        return
    }
    $procId = [int]$sel['PID']
    $port   = $sel['Port']
    $app    = $sel['App']

    if ($procId -le 4) {
        [void][Windows.MessageBox]::Show($window, 'Đây là tiến trình lõi của Windows, không thể dừng.', 'Port Dashboard', 'OK', 'Warning')
        return
    }

    $msg = "Dừng ứng dụng này?`n`n$app`nPort: $port   PID: $procId`n`nDữ liệu chưa lưu trong ứng dụng sẽ bị mất."
    if ($sel['IsSystem']) {
        $msg = "CẢNH BÁO: đây là dịch vụ hệ thống. Dừng nó có thể làm Windows hoạt động không ổn định.`n`n" + $msg
    }
    $ans = [Windows.MessageBox]::Show($window, $msg, 'Xác nhận dừng ứng dụng', 'YesNo', 'Warning')
    if ($ans -ne 'Yes') { return }

    try {
        Stop-Process -Id $procId -Force -ErrorAction Stop
        $script:killMsg = "Đã dừng $app - port $port đã được giải phóng."
        $txtStatus.Text = $script:killMsg
        $killTimer.Stop()
        $killTimer.Start()
    } catch {
        $hint = if ($isAdmin) { '' } else { "`n`nThử bấm ""Chạy lại với quyền Admin"" rồi dừng lại lần nữa." }
        [void][Windows.MessageBox]::Show($window, "Không dừng được ứng dụng.`n$($_.Exception.Message)$hint", 'Port Dashboard', 'OK', 'Error')
    }
})

$btnFolder.Add_Click({
    $sel = $grid.SelectedItem
    if (-not $sel) { return }
    $path = [string]$sel['Path']
    if ($path -and (Test-Path -LiteralPath $path)) {
        Start-Process explorer.exe -ArgumentList "/select,`"$path`""
    } else {
        [void][Windows.MessageBox]::Show($window, 'Không xác định được đường dẫn của ứng dụng này (có thể cần quyền Admin).', 'Port Dashboard', 'OK', 'Information')
    }
})

$btnAdmin.Add_Click({
    try {
        Start-Process powershell.exe -Verb RunAs -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-WindowStyle', 'Hidden',
            '-File', "`"$PSCommandPath`"")
        $window.Close()
    } catch {
        # Nguoi dung bam "No" o hop thoai UAC - khong lam gi ca.
    }
})

Update-FromSettings
$window.Add_Loaded({ $txtStatus.Text = 'Đang đọc danh sách port...'; Update-Data })
$window.Add_Closed({
    $timer.Stop(); $killTimer.Stop(); $pollTimer.Stop()
    foreach ($w in $workers) { try { [void]$w.PS.BeginStop($null, $null) } catch { } }
})
[void]$window.ShowDialog()
