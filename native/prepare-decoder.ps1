$ErrorActionPreference='Stop'
$vendor=Join-Path $PSScriptRoot 'vendor'
New-Item -ItemType Directory -Path $vendor -Force | Out-Null
$archive=Join-Path $vendor 'ffmpeg.7z'
# 固定已审核二进制 SHA-256，防止上游 latest 更新后无意更换版本。
$expected='4705843ccaaf54257c16ad90f3e952ece33c17df964ecf7bfdbb0f49c7171077'
if(!(Test-Path $archive)){
 $ProgressPreference='SilentlyContinue'
 Invoke-WebRequest -Uri 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.7z' -OutFile $archive
}
if((Get-FileHash $archive -Algorithm SHA256).Hash.ToLower() -ne $expected){throw '下载的 FFmpeg 与固定版本不一致，请审核版本及校验值后再更新脚本。'}
if(Test-Path "$vendor/ffmpeg/bin/ffmpeg.exe"){Write-Output '已校验的 FFmpeg 已就绪';exit 0}
$command=Get-Command 7z.exe -ErrorAction SilentlyContinue
if($command){$seven=$command.Source}else{
 $seven=Get-ChildItem (Join-Path $env:LOCALAPPDATA 'electron-builder/Cache') -Recurse -Filter 7za.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
}
if(!$seven){throw '请安装 7-Zip 并将 7z.exe 加入 PATH，或先构建 Electron 版本以获取打包工具缓存。'}
& $seven x $archive "-o$vendor/extracted" -y
if($LASTEXITCODE -ne 0){throw '解压 FFmpeg 失败'}
$folder=Get-ChildItem "$vendor/extracted" -Directory | Select-Object -First 1
$sourcePath=[IO.Path]::GetFullPath($folder.FullName)
$allowedRoot=[IO.Path]::GetFullPath((Join-Path $vendor 'extracted'))+[IO.Path]::DirectorySeparatorChar
if(!$sourcePath.StartsWith($allowedRoot,[StringComparison]::OrdinalIgnoreCase)){throw '解压目录超出构建工作区'}
Move-Item -LiteralPath $sourcePath -Destination (Join-Path $vendor 'ffmpeg')
& "$vendor/ffmpeg/bin/ffmpeg.exe" -version | Select-Object -First 1
