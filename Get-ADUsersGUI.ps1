#Requires -Modules ActiveDirectory

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="AD User Viewer" Height="620" Width="1000" MinHeight="400" MinWidth="700"
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
        <!-- Toolbar -->
        <Border DockPanel.Dock="Top" Background="#f0f0f0" BorderBrush="#dddddd"
                BorderThickness="0,0,0,1" Padding="10,8">
            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                <Label Content="Suche:" VerticalAlignment="Center" Padding="0,0,6,0"/>
                <TextBox x:Name="txtSearch" Width="250" VerticalAlignment="Center"/>
                <Button x:Name="btnLoad" Content="Laden" Margin="8,0,0,0"/>
                <Button x:Name="btnExport" Content="CSV Export" Margin="6,0,0,0" IsEnabled="False"/>
                <TextBlock x:Name="lblStatus" VerticalAlignment="Center" Margin="12,0,0,0"
                           Foreground="#666666"/>
            </StackPanel>
        </Border>
        <!-- Statusleiste -->
        <StatusBar DockPanel.Dock="Bottom" Background="#f0f0f0" BorderBrush="#dddddd"
                   BorderThickness="0,1,0,0">
            <TextBlock x:Name="lblStatusBar" Text="Bereit." Margin="4,0"/>
        </StatusBar>
        <!-- DataGrid -->
        <DataGrid x:Name="grid" Margin="10"
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
            <DataGrid.Columns>
                <DataGridTextColumn Header="Benutzername"  Binding="{Binding SamAccountName}" Width="130"/>
                <DataGridTextColumn Header="Anzeigename"   Binding="{Binding DisplayName}"    Width="160"/>
                <DataGridTextColumn Header="Vorname"       Binding="{Binding GivenName}"      Width="120"/>
                <DataGridTextColumn Header="Nachname"      Binding="{Binding Surname}"        Width="120"/>
                <DataGridTextColumn Header="Passwort geändert" Binding="{Binding PasswortGeaendert}" Width="150"/>
                <DataGridTextColumn Header="Aktiv"         Binding="{Binding Aktiv}"          Width="60"/>
                <DataGridTextColumn Header="Letzter Login" Binding="{Binding LetzterLogin}"   Width="130"/>
            </DataGrid.Columns>
        </DataGrid>
    </DockPanel>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

$txtSearch   = $window.FindName('txtSearch')
$btnLoad     = $window.FindName('btnLoad')
$btnExport   = $window.FindName('btnExport')
$lblStatus   = $window.FindName('lblStatus')
$lblStatusBar = $window.FindName('lblStatusBar')
$grid        = $window.FindName('grid')

function Load-ADUsers {
    param([string]$Filter = '*')

    $lblStatus.Text = 'Lade AD-Benutzer...'
    $window.Cursor = [System.Windows.Input.Cursors]::Wait
    $window.Dispatcher.Invoke([action]{}, 'Background')

    try {
        $users = Get-ADUser -Filter * `
            -Properties DisplayName, GivenName, Surname, Enabled, LastLogonDate, PasswordLastSet

        if ($Filter -ne '') {
            $users = $users | Where-Object {
                $_.SamAccountName -like "*$Filter*" -or
                $_.DisplayName    -like "*$Filter*"
            }
        }

        $users = $users | Sort-Object DisplayName

        $list = [System.Collections.ObjectModel.ObservableCollection[object]]::new()

        foreach ($u in $users) {
            $list.Add([PSCustomObject]@{
                SamAccountName    = $u.SamAccountName
                DisplayName       = $u.DisplayName
                GivenName         = $u.GivenName
                Surname           = $u.Surname
                Aktiv             = if ($u.Enabled) { 'Ja' } else { 'Nein' }
                LetzterLogin      = if ($u.LastLogonDate) { $u.LastLogonDate.ToString('dd.MM.yyyy HH:mm') } else { 'Nie' }
                PasswortGeaendert = if ($u.PasswordLastSet) { $u.PasswordLastSet.ToString('dd.MM.yyyy HH:mm') } else { 'Nie' }
            })
        }

        $grid.ItemsSource = $list
        $lblStatusBar.Text = "$($list.Count) Benutzer geladen."
        $lblStatus.Text = ''
        $btnExport.IsEnabled = ($list.Count -gt 0)
    }
    catch {
        [System.Windows.MessageBox]::Show(
            "Fehler beim Laden der AD-Benutzer:`n$($_.Exception.Message)",
            'Fehler', 'OK', 'Error')
        $lblStatusBar.Text = 'Fehler beim Laden.'
        $lblStatus.Text = ''
    }
    finally {
        $window.Cursor = $null
    }
}

$btnLoad.Add_Click({ Load-ADUsers -Filter $txtSearch.Text.Trim() })

$txtSearch.Add_KeyDown({
    if ($_.Key -eq 'Return') { Load-ADUsers -Filter $txtSearch.Text.Trim() }
})

$btnExport.Add_Click({
    $dlg = New-Object Microsoft.Win32.SaveFileDialog
    $dlg.Filter = 'CSV-Datei (*.csv)|*.csv'
    $dlg.FileName = "AD-Benutzer_$(Get-Date -Format 'yyyyMMdd_HHmm').csv"
    if ($dlg.ShowDialog()) {
        $grid.ItemsSource | Export-Csv -Path $dlg.FileName -Delimiter ';' -NoTypeInformation -Encoding UTF8
        $lblStatusBar.Text = "Exportiert: $($dlg.FileName)"
    }
})

$window.Add_Loaded({ Load-ADUsers })

$window.ShowDialog() | Out-Null
