#Requires -Modules ActiveDirectory

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

# --- Hauptfenster ---
$form = New-Object System.Windows.Forms.Form
$form.Text = 'AD User Viewer'
$form.Size = New-Object System.Drawing.Size(1000, 620)
$form.StartPosition = 'CenterScreen'
$form.MinimumSize = New-Object System.Drawing.Size(700, 400)

# --- Toolbar-Panel (oben) ---
$panelTop = New-Object System.Windows.Forms.Panel
$panelTop.Dock = 'Top'
$panelTop.Height = 45
$panelTop.Padding = New-Object System.Windows.Forms.Padding(8, 8, 8, 0)
$form.Controls.Add($panelTop)

$lblSearch = New-Object System.Windows.Forms.Label
$lblSearch.Text = 'Suche:'
$lblSearch.Location = New-Object System.Drawing.Point(8, 12)
$lblSearch.AutoSize = $true
$panelTop.Controls.Add($lblSearch)

$txtSearch = New-Object System.Windows.Forms.TextBox
$txtSearch.Location = New-Object System.Drawing.Point(55, 9)
$txtSearch.Width = 250
$panelTop.Controls.Add($txtSearch)

$btnLoad = New-Object System.Windows.Forms.Button
$btnLoad.Text = 'Laden'
$btnLoad.Location = New-Object System.Drawing.Point(315, 7)
$btnLoad.Width = 80
$panelTop.Controls.Add($btnLoad)

$btnExport = New-Object System.Windows.Forms.Button
$btnExport.Text = 'CSV Export'
$btnExport.Location = New-Object System.Drawing.Point(405, 7)
$btnExport.Width = 90
$btnExport.Enabled = $false
$panelTop.Controls.Add($btnExport)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Location = New-Object System.Drawing.Point(510, 12)
$lblStatus.AutoSize = $true
$lblStatus.ForeColor = [System.Drawing.Color]::Gray
$panelTop.Controls.Add($lblStatus)

# --- DataGridView ---
$grid = New-Object System.Windows.Forms.DataGridView
$grid.Dock = 'Fill'
$grid.ReadOnly = $true
$grid.AllowUserToAddRows = $false
$grid.AllowUserToDeleteRows = $false
$grid.MultiSelect = $false
$grid.SelectionMode = 'FullRowSelect'
$grid.AutoSizeColumnsMode = 'Fill'
$grid.RowHeadersVisible = $false
$grid.ColumnHeadersVisible = $true
$grid.EnableHeadersVisualStyles = $false
$grid.ColumnHeadersHeightSizeMode = 'DisableResizing'
$grid.ColumnHeadersHeight = 36
$grid.ColumnHeadersDefaultCellStyle.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$grid.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(51, 102, 153)
$grid.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.Color]::White
$grid.ColumnHeadersDefaultCellStyle.Alignment = 'MiddleLeft'
$grid.BackgroundColor = [System.Drawing.Color]::White
$grid.BorderStyle = 'Fixed3D'
$grid.AlternatingRowsDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
$form.Controls.Add($grid)

# --- Statusleiste (unten) ---
$statusBar = New-Object System.Windows.Forms.StatusStrip
$statusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
$statusLabel.Text = 'Bereit.'
$statusBar.Items.Add($statusLabel) | Out-Null
$form.Controls.Add($statusBar)

# --- Hilfsfunktion: AD-User laden ---
function Load-ADUsers {
    param([string]$Filter = '*')

    $lblStatus.Text = 'Lade AD-Benutzer...'
    $lblStatus.ForeColor = [System.Drawing.Color]::DarkBlue
    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    $form.Refresh()

    try {
        $properties = @('SamAccountName','DisplayName','GivenName','Surname',
                        'EmailAddress','Department','Title','Enabled','LastLogonDate')

        $ldapFilter = if ($Filter -eq '*') {
            '*'
        } else {
            "*$Filter*"
        }

        $users = Get-ADUser -Filter {
            (SamAccountName -like $ldapFilter) -or
            (DisplayName    -like $ldapFilter) -or
            (EmailAddress   -like $ldapFilter)
        } -Properties $properties |
            Select-Object SamAccountName, DisplayName, GivenName, Surname,
                          EmailAddress, Department, Title,
                          @{N='Aktiv'; E={ if ($_.Enabled) { 'Ja' } else { 'Nein' } }},
                          @{N='Letzter Login'; E={
                              if ($_.LastLogonDate) { $_.LastLogonDate.ToString('dd.MM.yyyy HH:mm') }
                              else { 'Nie' }
                          }} |
            Sort-Object DisplayName

        # DataTable befüllen
        $table = New-Object System.Data.DataTable
        $null = $table.Columns.Add('Benutzername')
        $null = $table.Columns.Add('Anzeigename')
        $null = $table.Columns.Add('Vorname')
        $null = $table.Columns.Add('Nachname')
        $null = $table.Columns.Add('E-Mail')
        $null = $table.Columns.Add('Abteilung')
        $null = $table.Columns.Add('Position')
        $null = $table.Columns.Add('Aktiv')
        $null = $table.Columns.Add('Letzter Login')

        foreach ($u in $users) {
            $row = $table.NewRow()
            $row['Benutzername']  = $u.SamAccountName
            $row['Anzeigename']   = $u.DisplayName
            $row['Vorname']       = $u.GivenName
            $row['Nachname']      = $u.Surname
            $row['E-Mail']        = $u.EmailAddress
            $row['Abteilung']     = $u.Department
            $row['Position']      = $u.Title
            $row['Aktiv']         = $u.'Aktiv'
            $row['Letzter Login'] = $u.'Letzter Login'
            $table.Rows.Add($row)
        }

        $grid.DataSource = $table
        $grid.Columns['Aktiv'].AutoSizeMode = 'AllCells'
        $grid.Columns['Letzter Login'].AutoSizeMode = 'AllCells'

        $count = $table.Rows.Count
        $statusLabel.Text = "$count Benutzer geladen."
        $lblStatus.Text = ''
        $btnExport.Enabled = ($count -gt 0)
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Fehler beim Laden der AD-Benutzer:`n$($_.Exception.Message)",
            'Fehler', 'OK', 'Error') | Out-Null
        $statusLabel.Text = 'Fehler beim Laden.'
        $lblStatus.Text = ''
    }
    finally {
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
    }
}

# --- Events ---
$btnLoad.Add_Click({
    Load-ADUsers -Filter $txtSearch.Text.Trim()
})

$txtSearch.Add_KeyDown({
    if ($_.KeyCode -eq 'Return') { Load-ADUsers -Filter $txtSearch.Text.Trim() }
})

$btnExport.Add_Click({
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.Filter = 'CSV-Datei (*.csv)|*.csv'
    $dlg.FileName = "AD-Benutzer_$(Get-Date -Format 'yyyyMMdd_HHmm').csv"
    if ($dlg.ShowDialog() -eq 'OK') {
        ($grid.DataSource).Rows |
            ForEach-Object { $_.ItemArray -join ';' } |
            Out-File -FilePath $dlg.FileName -Encoding UTF8 -Append
        # Header voranstellen
        $header = ($grid.DataSource).Columns | ForEach-Object { $_.ColumnName }
        $content = ($grid.DataSource).Rows | ForEach-Object { $_.ItemArray -join ';' }
        ($header -join ';'), $content | Set-Content -Path $dlg.FileName -Encoding UTF8
        $statusLabel.Text = "Exportiert: $($dlg.FileName)"
    }
})

# --- Start: direkt laden ---
$form.Add_Shown({ Load-ADUsers })

[void]$form.ShowDialog()
