$ErrorActionPreference='Stop'
$taskRoot=$PSScriptRoot
$matlabExe='C:\Program Files (x86)\MATLAB\R2022a\bin\win64\MATLAB.exe'
$out=Join-Path $taskRoot 'results\q2_strategy_scenarios'
New-Item -ItemType Directory -Force -Path $out | Out-Null
$statusPath=Join-Path $out 'run_status.txt'
$logPath=Join-Path $out 'matlab.log'
if(Test-Path -LiteralPath $statusPath){Remove-Item -LiteralPath $statusPath}
$rootM=$taskRoot.Replace('\','/').Replace("'","''")
$statusM=$statusPath.Replace('\','/').Replace("'","''")
$expr="cd('$rootM');addpath('q2','common','utils');try,run_q2_strategy_scenarios('$rootM',30);f=fopen('$statusM','w');fprintf(f,'0');fclose(f);exit(0);catch ME,disp(getReport(ME,'extended'));f=fopen('$statusM','w');fprintf(f,'1');fclose(f);exit(1);end;"
$p=Start-Process -FilePath $matlabExe -ArgumentList @('-nosplash','-nodesktop','-logfile',('"'+$logPath+'"'),'-r',('"'+$expr+'"')) -WindowStyle Hidden -PassThru
$p.WaitForExit()
if(-not(Test-Path -LiteralPath $statusPath)){throw "MATLAB did not write strategy status"}
if((Get-Content -LiteralPath $statusPath -Raw).Trim() -ne '0'){Get-Content -LiteralPath $logPath;throw "Strategy experiment failed $logPath"}
Write-Output "Q2 strategy experiments passed; exit $($p.ExitCode)."
