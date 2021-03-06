cls
###################################################################
# RVTools Queries
# Args usage = PSfile "path to spreadsheet" "path to save report with filename"
###################################################################

# Check for args
	if (-not $args[1])
		{
		throw "Incorrect format. Supply the path to spreadsheet and path to resulting filename as arguments. Example: query_rvtools_report.ps1 `"rvtools.xlsx`" `"results.csv`""
		exit		
		}

	$xlspath = $args[0]

# Excel import function
function Import-Excel
{
  param (
    [string]$FileName,
    [string]$WorksheetName,
    [bool]$DisplayProgress = $true
  )

  if ($FileName -eq "") {
    throw "Please provide path to the Excel file"
    Exit
  }

  if (-not (Test-Path $FileName)) {
    throw "Path '$FileName' does not exist."
    exit
  }

  $FileName = Resolve-Path $FileName
  $excel = New-Object -com "Excel.Application"
  $excel.Visible = $false
  $workbook = $excel.workbooks.open($FileName)

  if (-not $WorksheetName) {
    Write-Warning "Defaulting to the first worksheet in workbook."
    $sheet = $workbook.ActiveSheet
  } else {
    $sheet = $workbook.Sheets.Item($WorksheetName)
  }
  
  if (-not $sheet)
  {
    throw "Unable to open worksheet $WorksheetName"
    exit
  }
  
  $sheetName = $sheet.Name
  $columns = $sheet.UsedRange.Columns.Count
  $lines = $sheet.UsedRange.Rows.Count
  
  Write-Warning "Worksheet $sheetName contains $columns columns and $lines lines of data"
  
  $fields = @()
  
  for ($column = 1; $column -le $columns; $column ++) {
    $fieldName = $sheet.Cells.Item.Invoke(1, $column).Value2
    if ($fieldName -eq $null) {
      $fieldName = "Column" + $column.ToString()
    }
    $fields += $fieldName
  }
  
  $line = 2
  
  
  for ($line = 2; $line -le $lines; $line ++) {
    $values = New-Object object[] $columns
    for ($column = 1; $column -le $columns; $column++) {
      $values[$column - 1] = $sheet.Cells.Item.Invoke($line, $column).Value2
    }  
  
    $row = New-Object psobject
    $fields | foreach-object -begin {$i = 0} -process {
      $row | Add-Member -MemberType noteproperty -Name $fields[$i] -Value $values[$i]; $i++
    }
    $row
    $percents = [math]::round((($line/$lines) * 100), 0)
    if ($DisplayProgress) {
      Write-Progress -Activity:"Importing from Excel file $FileName" -Status:"Imported $line of total $lines lines ($percents%)" -PercentComplete:$percents
    }
  }
  $workbook.Close()
  $excel.Quit()
}

# Location of the worksheet in the spreadsheet
	$wkstname = "tabvHost"	

# Import tabs from RVTools, unless it's already imported (debug)
	if (-not $tabvhost) {$tabvhost = import-excel -FileName $xlspath -WorksheetName $wkstname}

###################################################################
# HOST Queries

# Group the clusters together by the cluster name
	$clusters = $tabvhost | Group {$_.Cluster}

	# Reporting setup
	$EndReport = @()

	# Break down into individual clusters
	foreach ($cluster in $clusters)
		{

		# Null out all of the counting vars, some just for when debugging code
		# Probably better if I stuck this in a function (blarg)
		$Report = {} | select DataCenter,ClusterName,HostQty,HostVendors,HostModels,Hypervisor,VMs,PCPU,LCPU,CPUUtil,RAM,RAMperHost,RAMUtil,Comments
		$VMs = $null
		$PCPU = $null
		$LCPU = $null
		$CPUUtil = $null
		$RAM = $null
		$RAMUtil = $null

		# Arrange the clusters into an array var because it makes things easier
		[array]$entries = $cluster.Group

		# Look at each host in the cluster and run various queries
		foreach ($entry in $entries)
			{			
			$PCPU += $entry.'# CPU' * $entry.'Cores per CPU'
			$LCPU += $entry.'# CPU' * $entry.'# Cores'
			$VMs += $entry.'# VMs'
			$CPUUtil += $entry.'CPU usage %'
			$RAM += $entry.'# Memory' / 1024
			$RAMUtil += $entry.'Memory usage %'
			}

		# Add values to the report
		$Report.DataCenter = $entry.Datacenter
		$Report.ClusterName = $cluster.Name 
		$Report.HostQty = $cluster.Count
		$Report.HostVendors = ($entries | ForEach-Object {$_.Vendor} | Select-Object -Unique) -join ','
		$Report.HostModels = ($entries | ForEach-Object {$_.Model} | Select-Object -Unique) -join ','
		$Report.Hypervisor = (($entries | ForEach-Object {$_.'ESX Version'} | Select-Object -Unique) -join ',') -replace 'VMware ',''
			If ($Report.HostVendors -match "," -or $Report.HostModels -match ",") {$Report.Comments += "Cluster contains mixed hardware. "}
			If ($Report.Hypervisor -match ",") {$Report.Comments += "Different versions of ESXi are present. "}
		$Report.VMs = $VMs
		$Report.PCPU = $PCPU
		$Report.LCPU = $LCPU
		$Report.CPUUtil = "{0:N2}" -f ($CPUUtil / $cluster.Count)
		$Report.RAM = "{0:N0}" -f $RAM
		[int]$Report.RAMperHost = "{0:N0}" -f ($RAM / $cluster.Count)
		$Report.RAMUtil = "{0:N2}" -f ($RAMUtil / $cluster.Count)
		If ($Report.RAMperHost -le 100) {$Report.Comments += "Hosts have a low quantity of RAM. "}
		$EndReport += $Report

		}

	# Export results to CSV
	$EndReport = $EndReport | Sort-Object DataCenter,ClusterName
	$EndReport | Export-Csv -Path $args[1] -NoTypeInformation