param()
$ErrorActionPreference='Stop'
$projectRoot=Split-Path $PSScriptRoot -Parent
Push-Location $projectRoot
try {
 if(!(Test-Path native/vendor/ffmpeg/bin/ffmpeg.exe)){throw '请先运行 native/prepare-decoder.ps1 下载并校验原生解码器'}
 $output=Join-Path $projectRoot 'dist/native'
 New-Item -ItemType Directory -Path "$output/assets" -Force | Out-Null
 foreach($kind in @('water','walk','eyes')){
  $source="src/renderer/assets/gugugaga-$kind-alpha.webm";$destination="$output/assets/$kind.webm"
  Copy-Item $source $destination -Force
  if((Get-FileHash $source).Hash -ne (Get-FileHash $destination).Hash){throw '视频完整性校验失败'}
 }
 Copy-Item native/vendor/ffmpeg/bin/ffmpeg.exe "$output/assets/" -Force
 Copy-Item native/vendor/ffmpeg/LICENSE "$output/assets/FFmpeg-LICENSE.txt" -Force
 Copy-Item native/vendor/ffmpeg/README.txt "$output/assets/FFmpeg-README.txt" -Force
 Copy-Item native/THIRD-PARTY-NOTICES.txt "$output/assets/" -Force
 # 仅删除此构建输出中已废弃的自定义动画，不包含用户文件。
 foreach($kind in @('water','walk','eyes')){Remove-Item -LiteralPath "$output/assets/$kind.guga" -Force -ErrorAction SilentlyContinue}
 Copy-Item src/renderer/fonts/ZCOOLKuaiLe-Regular.ttf "$output/assets/" -Force
 Copy-Item src/renderer/fonts/OFL.txt "$output/assets/" -Force
 Copy-Item src/desktop/icons/gugu.ico "$output/assets/" -Force
 $framework=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319'
 $wpf=Join-Path $framework 'WPF'
 $references=@('System.dll','System.Core.dll','System.Xaml.dll','System.Drawing.dll','System.Windows.Forms.dll','System.Web.Extensions.dll','System.IO.Compression.dll') | ForEach-Object {"/reference:$(Join-Path $framework $_)"}
 $references+=@('PresentationCore.dll','PresentationFramework.dll','WindowsBase.dll') | ForEach-Object {"/reference:$(Join-Path $wpf $_)"}
 & "$framework/csc.exe" /nologo /target:winexe /platform:x64 /optimize+ "/win32manifest:$PSScriptRoot\app.manifest" "/win32icon:$projectRoot\src\desktop\icons\gugu.ico" "/out:$output/GuguReminder.exe" @references "$PSScriptRoot\GuguReminder.cs"
 if($LASTEXITCODE -ne 0){throw '原生应用编译失败'}
 $test=Start-Process "$output/GuguReminder.exe" -ArgumentList '--self-test' -PassThru -Wait -WindowStyle Hidden
 if($test.ExitCode -ne 0){throw '原生程序自检失败，请查看 dist/native/self-test.txt'}
 $zip=Join-Path $projectRoot 'dist/Gugu-Reminder-Native-0.2.0-win-x64.zip'
 Compress-Archive -Path "$output/GuguReminder.exe","$output/assets" -DestinationPath $zip -Force
 Get-Item $zip | Select-Object FullName,@{Name='MB';Expression={[math]::Round($_.Length/1MB,2)}}
 $nsis=Get-Command makensis.exe -ErrorAction SilentlyContinue
 if($nsis){$compiler=$nsis.Source}else{
  $compiler=Get-ChildItem (Join-Path $env:LOCALAPPDATA 'electron-builder/Cache') -Recurse -Filter makensis.exe -ErrorAction SilentlyContinue | Where-Object {$_.Directory.Name -eq 'Bin'} | Select-Object -First 1 -ExpandProperty FullName
 }
 if(!$compiler){throw '请安装 NSIS 3 并把 makensis.exe 加入 PATH，以生成安装包；免安装 ZIP 已生成。'}
 & $compiler /V2 native/installer.nsi
 if($LASTEXITCODE -ne 0){throw '原生安装包构建失败'}
 Get-Item dist/Gugu-Reminder-Native-0.2.0-Setup.exe | Select-Object FullName,@{Name='MB';Expression={[math]::Round($_.Length/1MB,2)}}
} finally {Pop-Location}
