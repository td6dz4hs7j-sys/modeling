param([ValidateSet('full','minimal')][string]$Mode='full')
$ErrorActionPreference='Stop'
$moduleRoot=$PSScriptRoot
$repoRoot=Split-Path -Parent $moduleRoot
$matlabCandidates=@('C:\Program Files (x86)\MATLAB\R2022a\bin\win64\MATLAB.exe','C:\Program Files\MATLAB\R2022a\bin\matlab.exe')
$matlabCommand=Get-Command matlab -ErrorAction SilentlyContinue
if($matlabCommand){$matlabCandidates=@($matlabCommand.Source)+$matlabCandidates}
$matlabExe=$matlabCandidates | Where-Object {Test-Path -LiteralPath $_} | Select-Object -First 1
if(-not $matlabExe){throw 'MATLAB executable not found.'}
$resultDir=Join-Path $repoRoot 'results\q1_exact_dp'
New-Item -ItemType Directory -Force -Path $resultDir | Out-Null
$statusPath=Join-Path $resultDir "run_status_$Mode.txt"
if(Test-Path -LiteralPath $statusPath){Move-Item -LiteralPath $statusPath -Destination "$statusPath.previous" -Force}
$escapedModule=$moduleRoot.Replace('\','/').Replace("'","''")
$expr="cd('$escapedModule'); addpath('q1'); try, main_q1('$Mode'); f=fopen('$($statusPath.Replace('\','/'))','w'); fprintf(f,'0'); fclose(f); catch ME, diary('$($resultDir.Replace('\','/'))/error.log'); disp(getReport(ME,'extended')); diary off; f=fopen('$($statusPath.Replace('\','/'))','w'); fprintf(f,'1'); fclose(f); exit(1); end; exit(0);"
$process=Start-Process -FilePath $matlabExe -ArgumentList @('-nosplash','-nodesktop','-r',('"'+$expr+'"')) -WindowStyle Hidden -PassThru
$process.WaitForExit()
if(-not(Test-Path -LiteralPath $statusPath)){throw "MATLAB exited without completion status; process exit code $($process.ExitCode)"}
if((Get-Content -LiteralPath $statusPath -Raw).Trim() -ne '0'){throw 'MATLAB solve failed; see results/q1_exact_dp/error.log.'}
Write-Output 'MATLAB Q1 exact-DP completed successfully (status 0).'
