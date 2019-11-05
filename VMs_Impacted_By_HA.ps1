$Date = Get-Date
$HAVMrestartold = 1
Get-VIEvent -maxsamples 100000 -Start ($Date).AddDays(-$HAVMrestartold) -type warning | Where {$_.FullFormattedMessage -match "restarted"} |select CreatedTime,FullFormattedMessage |sort CreatedTime -Descending
