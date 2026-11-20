# Converte um vídeo para MP4 (H.264 + AAC) com o conversor do próprio Windows.
# Sem programa novo: usa o Media Foundation do Windows (o ffmpeg não está instalado).
# Uso: powershell -ExecutionPolicy Bypass -File tests/tools/to_mp4.ps1 entrada.avi pasta_de_saida nome.mp4
param([string]$In, [string]$OutDir, [string]$Name)
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$methods = [System.WindowsRuntimeSystemExtensions].GetMethods()
$asTaskOp = $methods | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' } | Select-Object -First 1
$asTaskProg = $methods | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncActionWithProgress`1' } | Select-Object -First 1
function Wait-Op($op, [Type]$type) {
    $task = $asTaskOp.MakeGenericMethod($type).Invoke($null, @($op))
    $task.Wait(-1) | Out-Null
    $task.Result
}
[void][Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]
[void][Windows.Storage.StorageFolder, Windows.Storage, ContentType = WindowsRuntime]
[void][Windows.Media.Transcoding.MediaTranscoder, Windows.Media.Transcoding, ContentType = WindowsRuntime]
[void][Windows.Media.MediaProperties.MediaEncodingProfile, Windows.Media.MediaProperties, ContentType = WindowsRuntime]
$src = Wait-Op ([Windows.Storage.StorageFile]::GetFileFromPathAsync($In)) ([Windows.Storage.StorageFile])
$folder = Wait-Op ([Windows.Storage.StorageFolder]::GetFolderFromPathAsync($OutDir)) ([Windows.Storage.StorageFolder])
$dst = Wait-Op ($folder.CreateFileAsync($Name, [Windows.Storage.CreationCollisionOption]::ReplaceExisting)) ([Windows.Storage.StorageFile])
$profile = [Windows.Media.MediaProperties.MediaEncodingProfile]::CreateMp4([Windows.Media.MediaProperties.VideoEncodingQuality]::HD1080p)
$profile.Video.Width = 1920
$profile.Video.Height = 1080
$profile.Video.FrameRate.Numerator = 30
$profile.Video.FrameRate.Denominator = 1
$profile.Video.Bitrate = 8000000
$transcoder = New-Object Windows.Media.Transcoding.MediaTranscoder
$prep = Wait-Op ($transcoder.PrepareFileTranscodeAsync($src, $dst, $profile)) ([Windows.Media.Transcoding.PrepareTranscodeResult])
if (-not $prep.CanTranscode) {
    Write-Output "nao da para converter: $($prep.FailureReason)"
    exit 1
}
$task = $asTaskProg.MakeGenericMethod([double]).Invoke($null, @($prep.TranscodeAsync()))
$task.Wait(-1) | Out-Null
if ($task.IsFaulted) { Write-Output "falhou: $($task.Exception.InnerException.Message)"; exit 1 }
Write-Output "ok: $(Join-Path $OutDir $Name)"
