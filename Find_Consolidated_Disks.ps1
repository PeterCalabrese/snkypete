Get-VM | Where-Object -Property Name -Like "*cma*" | Get-HardDisk | Where-Object -Property FileName -NotLike "*cma*" | Select-Object -Property Parent ,FileName 

#| Export-Csv H:\scripts\CHG0042328_Disk_Consolidation.csv -NoTypeInformation -UseCulture
