#Requires -Modules ActiveDirectory

# --- Konfiguration laden ---
$scriptDir  = if ($PSScriptRoot) { $PSScriptRoot } else { $env:USERPROFILE }
$configPath = Join-Path $scriptDir 'config.json'

if (Test-Path $configPath) {
    try   { $config = Get-Content $configPath -Raw | ConvertFrom-Json }
    catch { $config = $null }
}

if (-not $config) {
    $config = [PSCustomObject]@{ Title = 'AD User Viewer'; OUs = @() }
}
if (-not $config.PSObject.Properties['Title']) {
    $config | Add-Member -NotePropertyName 'Title' -NotePropertyValue 'AD User Viewer'
}
if (-not $config.PSObject.Properties['OUs'] -or $null -eq $config.OUs) {
    $config | Add-Member -NotePropertyName 'OUs' -NotePropertyValue @() -Force
}

# --- Desktop-Verknüpfung prüfen und ggf. anlegen (nur Windows) ---
if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)) {
    $shortcutPath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'AD User Viewer.lnk'
    if (-not (Test-Path $shortcutPath)) {
        $pwshPath = (Get-Process -Id $PID).Path
        $wsh      = New-Object -ComObject WScript.Shell
        $lnk      = $wsh.CreateShortcut($shortcutPath)
        $lnk.TargetPath       = $pwshPath
        $lnk.Arguments        = '-NoProfile -WindowStyle Hidden -Command "irm ''https://raw.githubusercontent.com/dakazanak/Get-ADUsersGUI/master/Get-ADUsersGUI.ps1'' | iex"'
        $lnk.Description      = 'AD User Viewer'
        $lnk.WorkingDirectory = [Environment]::GetFolderPath('UserProfile')
        $lnk.Save()
    }
}

function Save-Config {
    $config | ConvertTo-Json -Depth 5 | Set-Content -Path $configPath -Encoding UTF8
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# OU-Klasse mit INotifyPropertyChanged für korrekte WPF-Checkbox-Bindung
if (-not ([System.Management.Automation.PSTypeName]'OUItem').Type) { Add-Type @'
using System;
using System.ComponentModel;
public class OUItem : INotifyPropertyChanged {
    public event PropertyChangedEventHandler PropertyChanged;
    private bool _visible;
    public string DN    { get; set; }
    public string Label { get; set; }
    public bool Visible {
        get { return _visible; }
        set {
            if (_visible != value) {
                _visible = value;
                if (PropertyChanged != null)
                    PropertyChanged(this, new PropertyChangedEventArgs("Visible"));
            }
        }
    }
}
'@ }

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="AD User Viewer" Height="620" Width="1250" MinHeight="400" MinWidth="750"
        WindowStartupLocation="CenterScreen" FontFamily="Segoe UI" FontSize="13">
    <Window.Resources>
        <Style TargetType="Button">
            <Setter Property="Background" Value="#336699"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="Padding" Value="12,5"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" CornerRadius="3"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="#1a4d80"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Background" Value="#aaaaaa"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="TextBox">
            <Setter Property="Padding" Value="6,4"/>
            <Setter Property="BorderBrush" Value="#cccccc"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
        </Style>
        <Style TargetType="DataGrid">
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="BorderBrush" Value="#cccccc"/>
            <Setter Property="RowBackground" Value="White"/>
            <Setter Property="AlternatingRowBackground" Value="#f5f5f5"/>
            <Setter Property="HorizontalGridLinesBrush" Value="#e0e0e0"/>
            <Setter Property="VerticalGridLinesBrush" Value="#e0e0e0"/>
        </Style>
        <Style TargetType="DataGridColumnHeader">
            <Setter Property="Background" Value="#336699"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="FontWeight" Value="Bold"/>
            <Setter Property="Padding" Value="8,6"/>
            <Setter Property="BorderThickness" Value="0,0,1,0"/>
            <Setter Property="BorderBrush" Value="#1a4d80"/>
        </Style>
    </Window.Resources>
    <DockPanel>
        <!-- Statusleiste -->
        <Border DockPanel.Dock="Bottom" Background="#f0f0f0" BorderBrush="#dddddd"
                BorderThickness="0,1,0,0" Padding="4,3">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <TextBlock x:Name="lblStatusBar" Text="Bereit." VerticalAlignment="Center"/>
                <Button x:Name="btnRefresh" Content="Ansicht aktualisieren" Grid.Column="1"
                        Padding="10,3"/>
            </Grid>
        </Border>
        <!-- Hauptbereich: OU-Panel links + DataGrid rechts -->
        <Grid>
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="220" MinWidth="150"/>
                <ColumnDefinition Width="4"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <!-- OU-Panel -->
            <Border Grid.Column="0" BorderBrush="#dddddd" BorderThickness="0,0,1,0"
                    Background="#fafafa">
                <DockPanel>
                    <Border DockPanel.Dock="Top" Background="#336699" Padding="8,6">
                        <TextBlock Text="Organisationseinheiten" Foreground="White"
                                   FontWeight="Bold" TextWrapping="Wrap"/>
                    </Border>
                    <ScrollViewer VerticalScrollBarVisibility="Auto">
                        <ItemsControl x:Name="ouPanel" Margin="6,6,6,6">
                            <ItemsControl.ItemTemplate>
                                <DataTemplate>
                                    <CheckBox Content="{Binding Label}"
                                              IsChecked="{Binding Visible, Mode=TwoWay}"
                                              Margin="2,3" ToolTip="{Binding DN}"
                                              x:Name="ouCheckBox"/>
                                </DataTemplate>
                            </ItemsControl.ItemTemplate>
                        </ItemsControl>
                    </ScrollViewer>
                </DockPanel>
            </Border>
            <!-- Splitter -->
            <GridSplitter Grid.Column="1" Width="4" HorizontalAlignment="Stretch"
                          Background="#dddddd"/>
            <!-- DataGrid -->
            <DataGrid x:Name="grid" Grid.Column="2" Margin="10"
                      AutoGenerateColumns="False"
                      IsReadOnly="True"
                      SelectionMode="Single"
                      SelectionUnit="FullRow"
                      CanUserAddRows="False"
                      CanUserDeleteRows="False"
                      CanUserReorderColumns="True"
                      CanUserResizeColumns="True"
                      CanUserSortColumns="True"
                      ColumnWidth="*">
                <DataGrid.RowStyle>
                    <Style TargetType="DataGridRow">
                        <Style.Triggers>
                            <DataTrigger Binding="{Binding Aktiv}" Value="Nein">
                                <Setter Property="Background" Value="#bdbdbd"/>
                                <Setter Property="Foreground" Value="#424242"/>
                            </DataTrigger>
                        </Style.Triggers>
                    </Style>
                </DataGrid.RowStyle>
                <DataGrid.Columns>
                    <DataGridTextColumn Header="Benutzername"     Binding="{Binding SamAccountName}"    Width="130"/>
                    <DataGridTextColumn Header="Anzeigename"      Binding="{Binding DisplayName}"       Width="160"/>
                    <DataGridTextColumn Header="Vorname"          Binding="{Binding GivenName}"         Width="110"/>
                    <DataGridTextColumn Header="Nachname"         Binding="{Binding Surname}"           Width="110"/>
                    <DataGridTextColumn Header="Passwort geändert" Binding="{Binding PasswortGeaendert}" Width="140"/>
                    <DataGridTextColumn Header="Läuft nie ab"     Binding="{Binding PasswortLaeuftNieAb}" Width="100">
                        <DataGridTextColumn.ElementStyle>
                            <Style TargetType="TextBlock">
                                <Style.Triggers>
                                    <DataTrigger Binding="{Binding PasswortLaeuftNieAb}" Value="Ja">
                                        <Setter Property="Background" Value="#ffcdd2"/>
                                        <Setter Property="Foreground" Value="#b71c1c"/>
                                        <Setter Property="FontWeight" Value="SemiBold"/>
                                    </DataTrigger>
                                </Style.Triggers>
                            </Style>
                        </DataGridTextColumn.ElementStyle>
                    </DataGridTextColumn>
                    <DataGridTextColumn Header="Läuft ab am"      Binding="{Binding PasswortLaeuftAb}"  Width="130">
                        <DataGridTextColumn.ElementStyle>
                            <Style TargetType="TextBlock">
                                <Style.Triggers>
                                    <DataTrigger Binding="{Binding PasswortStatus}" Value="Abgelaufen">
                                        <Setter Property="Background" Value="#ffcdd2"/>
                                        <Setter Property="Foreground" Value="#b71c1c"/>
                                        <Setter Property="FontWeight" Value="SemiBold"/>
                                    </DataTrigger>
                                    <DataTrigger Binding="{Binding PasswortStatus}" Value="BaldAbgelaufen">
                                        <Setter Property="Background" Value="#fff9c4"/>
                                        <Setter Property="Foreground" Value="#e65100"/>
                                        <Setter Property="FontWeight" Value="SemiBold"/>
                                    </DataTrigger>
                                </Style.Triggers>
                            </Style>
                        </DataGridTextColumn.ElementStyle>
                    </DataGridTextColumn>
                    <DataGridTextColumn Header="Aktiv"            Binding="{Binding Aktiv}"             Width="60"/>
                    <DataGridTextColumn Header="Gesperrt"         Binding="{Binding Gesperrt}"          Width="80">
                        <DataGridTextColumn.ElementStyle>
                            <Style TargetType="TextBlock">
                                <Style.Triggers>
                                    <DataTrigger Binding="{Binding Gesperrt}" Value="Ja">
                                        <Setter Property="Background" Value="#ffcdd2"/>
                                        <Setter Property="Foreground" Value="#b71c1c"/>
                                        <Setter Property="FontWeight" Value="Bold"/>
                                    </DataTrigger>
                                </Style.Triggers>
                            </Style>
                        </DataGridTextColumn.ElementStyle>
                    </DataGridTextColumn>
                    <DataGridTextColumn Header="Letzter Login"    Binding="{Binding LetzterLogin}"      Width="130"/>
                </DataGrid.Columns>
            </DataGrid>
        </Grid>
    </DockPanel>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

$lblStatusBar = $window.FindName('lblStatusBar')
$btnRefresh   = $window.FindName('btnRefresh')
$grid         = $window.FindName('grid')
$ouPanel      = $window.FindName('ouPanel')

# Alle AD-User (gecacht, damit OU-Filter ohne AD-Abfrage arbeitet)
$script:allUsers = @()
# OU-Objekte für Binding
$script:ouItems = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
$ouPanel.ItemsSource = $script:ouItems

function Get-OULabel {
    param([string]$DN)
    # Alle OU=-Komponenten extrahieren und von oben nach unten darstellen
    $parts = [System.Text.RegularExpressions.Regex]::Matches($DN, '(?i)OU=([^,]+)') |
             ForEach-Object { $_.Groups[1].Value }
    if ($parts) { return ($parts[-1..-($parts.Count)] -join ' > ') }
    return $DN
}

function Sync-OUsWithConfig {
    param([string[]]$LiveDNs)

    $configOUs = @{}
    foreach ($entry in $config.OUs) {
        $configOUs[$entry.DN] = $entry.Visible
    }

    # Neue OUs (nicht in Config) → sichtbar setzen
    foreach ($dn in $LiveDNs) {
        if (-not $configOUs.ContainsKey($dn)) {
            $configOUs[$dn] = $true
        }
    }

    # Veraltete OUs (nicht mehr im AD) aus Config entfernen
    $toRemove = $configOUs.Keys | Where-Object { $_ -notin $LiveDNs }
    foreach ($dn in $toRemove) { $configOUs.Remove($dn) }

    # Config-OUs aktualisieren
    $config.OUs = @($LiveDNs | ForEach-Object {
        [PSCustomObject]@{ DN = $_; Visible = $configOUs[$_] }
    })
    Save-Config

    return $configOUs
}

function Update-GridView {
    $visibleDNs = $script:ouItems | Where-Object { $_.Visible } | ForEach-Object { $_.DN }
    $filtered   = $script:allUsers | Where-Object { $_.OU -in $visibleDNs }

    $list = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
    foreach ($u in $filtered | Sort-Object DisplayName) { $list.Add($u) }

    $grid.ItemsSource = $list
    $lblStatusBar.Text = "$($list.Count) Benutzer angezeigt."
}

function Load-ADUsers {
    $window.Cursor = [System.Windows.Input.Cursors]::Wait
    $window.Dispatcher.Invoke([action]{}, 'Background')

    try {
        $maxAge = (Get-ADDefaultDomainPasswordPolicy).MaxPasswordAge

        $adUsers = Get-ADUser -Filter * `
            -Properties DisplayName, GivenName, Surname, Enabled, LastLogonDate, PasswordLastSet, PasswordNeverExpires, LockedOut

        # OU je User ermitteln (direkt übergeordnete OU aus DN)
        $script:allUsers = $adUsers | ForEach-Object {
            $dn = $_.DistinguishedName
            $ou = ($dn -split ',', 2)[1]

            if ($_.PasswordNeverExpires -or -not $_.PasswordLastSet -or $maxAge.TotalDays -eq 0) {
                $ablauf  = 'Nie'
                $pwStatus = 'NieAbgelaufend'
            } else {
                $ablaufDt = $_.PasswordLastSet + $maxAge
                $ablauf   = $ablaufDt.ToString('dd.MM.yyyy HH:mm')
                $pwStatus = if ($ablaufDt -lt (Get-Date)) { 'Abgelaufen' }
                            elseif ($ablaufDt -lt (Get-Date).AddDays(14)) { 'BaldAbgelaufen' }
                            else { 'OK' }
            }

            [PSCustomObject]@{
                SamAccountName      = $_.SamAccountName
                DisplayName         = $_.DisplayName
                GivenName           = $_.GivenName
                Surname             = $_.Surname
                Aktiv               = if ($_.Enabled) { 'Ja' } else { 'Nein' }
                Gesperrt            = if ($_.LockedOut) { 'Ja' } else { 'Nein' }
                LetzterLogin        = if ($_.LastLogonDate) { $_.LastLogonDate.ToString('dd.MM.yyyy HH:mm') } else { 'Nie' }
                PasswortGeaendert   = if ($_.PasswordLastSet) { $_.PasswordLastSet.ToString('dd.MM.yyyy HH:mm') } else { 'Nie' }
                PasswortLaeuftNieAb = if ($_.PasswordNeverExpires) { 'Ja' } else { 'Nein' }
                PasswortLaeuftAb    = $ablauf
                PasswortStatus      = $pwStatus
                OU                  = $ou
            }
        }

        # Eindeutige OUs ermitteln
        $liveDNs = $script:allUsers | ForEach-Object { $_.OU } | Sort-Object -Unique

        # Config abgleichen
        $ouVisibility = Sync-OUsWithConfig -LiveDNs $liveDNs

        # OU-Panel befüllen
        $script:ouItems.Clear()
        foreach ($dn in $liveDNs) {
            $item = New-Object OUItem
            $item.DN      = $dn
            $item.Label   = Get-OULabel -DN $dn
            $item.Visible = [bool]$ouVisibility[$dn]

            # Checkbox-Änderung: Grid neu filtern + Config speichern
            $item.add_PropertyChanged({
                param($sender, $e)
                if ($e.PropertyName -eq 'Visible') {
                    $ou = $config.OUs | Where-Object { $_.DN -eq $sender.DN }
                    if ($ou) { $ou.Visible = $sender.Visible }
                    Save-Config
                    Update-GridView
                }
            })
            $script:ouItems.Add($item)
        }

        Update-GridView
    }
    catch {
        [System.Windows.MessageBox]::Show(
            "Fehler beim Laden der AD-Benutzer:`n$($_.Exception.Message)",
            'Fehler', 'OK', 'Error')
        $lblStatusBar.Text = 'Fehler beim Laden.'
    }
    finally {
        $window.Cursor = $null
    }
}

$btnRefresh.Add_Click({ Load-ADUsers })

$window.Title = $config.Title
$window.Add_Loaded({ Load-ADUsers })

$window.ShowDialog() | Out-Null
