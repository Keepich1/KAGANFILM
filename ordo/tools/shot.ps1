# Кадр сцены в PNG на Windows — видеокартой ПК (на миг откроется окно игры). Тот же кадр, что tools/shot.sh.
#   tools\shot.cmd res://scenes/slice.tscn out.png [--at=6] [--cam=CamCamp] [--size=1920x1080] [--quality=low]
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\shot.ps1 …   (то же, без shot.cmd)
# Время сцены идёт ровно 1/30 с за кадр (--fixed-fps 30), поэтому кадр повторяем (пыль и дым — почти).
# Godot: $env:GODOT, иначе самый новый по имени файла Godot*.exe из C:\Godot\… и C:\ (консольный
# …_console.exe — в первую очередь, как в godot.sh), иначе godot из PATH.
# Предел ожидания — $env:SHOT_TIMEOUT секунд (900).
# Окно игры не бывает больше экрана: если кадр вышел меньше заказанного — это ошибка, а не «OK».
# Пути с & и ^ передавайте через shot.ps1, а не shot.cmd (их разбирает cmd).
# Код выхода: 0 — кадр есть и нужного размера, 1 — нет.
$ErrorActionPreference = 'Stop'

function Find-Godot {
	if ($env:GODOT) {
		if (Test-Path -LiteralPath $env:GODOT -PathType Leaf) { return $env:GODOT }
		throw "GODOT=$($env:GODOT): такого файла нет"
	}
	$found = @()
	if (Test-Path -LiteralPath 'C:\Godot' -PathType Container) {
		$found += @(Get-ChildItem -LiteralPath 'C:\Godot' -Recurse -Depth 1 -File -Filter 'Godot*.exe' -ErrorAction SilentlyContinue)
	}
	$found += @(Get-ChildItem -LiteralPath 'C:\' -File -Filter 'Godot*.exe' -ErrorAction SilentlyContinue)
	$console = @($found | Where-Object { $_.Name -like '*_console.exe' } | Sort-Object Name)
	if ($console.Count) { return $console[-1].FullName }
	$any = @($found | Sort-Object Name)
	if ($any.Count) { return $any[-1].FullName }
	$cmd = Get-Command godot -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
	if ($cmd) { return $cmd.Source }
	throw 'Godot не найден: положите его в C:\Godot (или файлом прямо в C:\) или задайте $env:GODOT = путь к exe'
}

# Аргумент скрипта как строка: при прямом вызове из PowerShell «a,b» приходит списком — склеиваем обратно
function ConvertFrom-PsArg($a) {
	if ($a -is [array]) { return (($a | ForEach-Object { [string]$_ }) -join ',') }
	return [string]$a
}

# Аргумент для командной строки Windows (правила CommandLineToArgvW): пробелы — в кавычках,
# обратные косые перед кавычкой удваиваются
function ConvertTo-CmdArg([string]$s) {
	if ($s -ne '' -and $s -notmatch '[\s"]') { return $s }
	$s = $s -replace '(\\*)"', '$1$1\"'
	$s = $s -replace '(\\+)$', '$1$1'
	return '"' + $s + '"'
}

# Остановить Godot со всеми дочерними процессами. Ответ taskkill гасит сам cmd: иначе при
# $ErrorActionPreference = 'Stop' его «процесс не найден» (Godot успел выйти сам) обрывает скрипт
function Stop-Tree([int]$id) {
	& cmd.exe /c "taskkill /PID $id /T /F >nul 2>&1"
}

# Ширина и высота PNG из заголовка (IHDR)
function Get-PngSize([string]$path) {
	$b = New-Object byte[] 24
	$fs = [IO.File]::OpenRead($path)
	try { $n = $fs.Read($b, 0, 24) } finally { $fs.Close() }
	if ($n -lt 24 -or $b[1] -ne 0x50 -or $b[2] -ne 0x4E -or $b[3] -ne 0x47) { return $null }
	$w = ([int]$b[16] -shl 24) -bor ([int]$b[17] -shl 16) -bor ([int]$b[18] -shl 8) -bor [int]$b[19]
	$h = ([int]$b[20] -shl 24) -bor ([int]$b[21] -shl 16) -bor ([int]$b[22] -shl 8) -bor [int]$b[23]
	return "${w}x${h}"
}

# Новые строки журнала Godot: без цветовых кодов и пустых строк; неполная строка ждёт конца
$script:tail = @{}
function Write-NewLines([IO.StreamReader]$reader, [string]$key, [bool]$final) {
	$text = $script:tail[$key] + $reader.ReadToEnd()
	$parts = $text -split "`n"
	if ($final) { $script:tail[$key] = '' } else { $script:tail[$key] = $parts[-1] }
	$last = if ($final) { $parts.Count - 1 } else { $parts.Count - 2 }
	for ($i = 0; $i -le $last; $i++) {
		$line = ($parts[$i] -replace '\x1b\[[0-9;]*m', '').TrimEnd()
		if ($line -ne '') { Write-Output $line }
	}
}

$encoding = [Console]::OutputEncoding
$tmp = $null
$p = $null
try {
	# Git Bash читает вывод как UTF-8, а консоль Windows передаёт его в своей кодировке (866):
	# переключаемся на UTF-8 только для Git Bash, иначе русские строки выходят «кракозябрами» у вызывающего
	if ($env:MSYSTEM) { [Console]::OutputEncoding = [Text.Encoding]::UTF8 }
	if ($args.Count -lt 2) {
		Write-Output 'Как вызывать: tools\shot.cmd res://scenes/X.tscn out.png [--at=6] [--cam=Имя] [--size=1920x1080]'
		exit 1
	}
	$root = Split-Path -Parent $PSScriptRoot
	# кадры проверки не импортируются в проект (файл могут одновременно создать два запуска — это не ошибка)
	$renders = Join-Path $root 'renders'
	[IO.Directory]::CreateDirectory($renders) | Out-Null
	$gdignore = Join-Path $renders '.gdignore'
	if (-not (Test-Path -LiteralPath $gdignore)) { New-Item -ItemType File -Path $gdignore -ErrorAction SilentlyContinue | Out-Null }

	$scene = ConvertFrom-PsArg $args[0]
	# путь кадра — от текущей папки PowerShell; Godot ждёт C:/… с прямыми косыми
	$out = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath((ConvertFrom-PsArg $args[1]))
	$size = '1920x1080'
	$extra = @()
	if ($args.Count -gt 2) {
		foreach ($a in $args[2..($args.Count - 1)]) {
			$a = ConvertFrom-PsArg $a
			if ($a -like '--size=*') { $size = $a.Substring(7) }
			# лишний «--» игре не нужен (PowerShell его и сам съедает при прямом вызове)
			elseif ($a -ne '--') { $extra += $a }
		}
	}
	if ($size -notmatch '^\d+x\d+$') { throw "--size=${size}: нужно ШИРИНАxВЫСОТА, например 1920x1080" }
	# CreateDirectory спокойно принимает и готовую папку, и корень диска (New-Item -Force на D:\ падает)
	[IO.Directory]::CreateDirectory((Split-Path -Parent $out)) | Out-Null
	# старый кадр с тем же именем не должен сойти за новый: запоминаем, когда он записан
	$before = $null
	if (Test-Path -LiteralPath $out -PathType Leaf) { $before = (Get-Item -LiteralPath $out).LastWriteTimeUtc }

	$godot = Find-Godot
	$gargs = @('--path', $root, '--resolution', $size, '--audio-driver', 'Dummy', '--fixed-fps', '30',
		$scene, '--', ('--shot=' + ($out -replace '\\', '/'))) + $extra
	$line = ($gargs | ForEach-Object { ConvertTo-CmdArg $_ }) -join ' '
	$timeout = 900
	if ($env:SHOT_TIMEOUT) { $timeout = [int]$env:SHOT_TIMEOUT }

	# журнал Godot — через временные файлы: так работает предел ожидания, а строки видны по ходу
	$tmp = Join-Path ([IO.Path]::GetTempPath()) ('ordo_shot_' + [guid]::NewGuid().ToString('N'))
	New-Item -ItemType Directory -Path $tmp | Out-Null
	$logOut = Join-Path $tmp 'out.txt'
	$logErr = Join-Path $tmp 'err.txt'
	$start = Get-Date
	$p = Start-Process -FilePath $godot -ArgumentList $line -NoNewWindow -PassThru `
		-RedirectStandardOutput $logOut -RedirectStandardError $logErr
	$null = $p.Handle   # без этого PowerShell 5 теряет код выхода
	$share = [IO.FileShare]'ReadWrite, Delete'
	$rOut = New-Object IO.StreamReader((New-Object IO.FileStream($logOut, 'Open', 'Read', $share)), [Text.Encoding]::UTF8)
	$rErr = New-Object IO.StreamReader((New-Object IO.FileStream($logErr, 'Open', 'Read', $share)), [Text.Encoding]::UTF8)
	$timedOut = $false
	while (-not $p.WaitForExit(250)) {
		Write-NewLines $rOut 'out' $false
		Write-NewLines $rErr 'err' $false
		if (((Get-Date) - $start).TotalSeconds -gt $timeout -and -not $p.HasExited) {
			$timedOut = $true
			Stop-Tree $p.Id
			$p.WaitForExit(10000) | Out-Null
			break
		}
	}
	Write-NewLines $rOut 'out' $true
	Write-NewLines $rErr 'err' $true
	$rOut.Close()
	$rErr.Close()
	if ($timedOut) { Write-Output "Godot не закончил за $timeout с, остановлен (предел: `$env:SHOT_TIMEOUT)" }

	$fresh = $false
	if (Test-Path -LiteralPath $out -PathType Leaf) {
		$fresh = ($null -eq $before) -or ((Get-Item -LiteralPath $out).LastWriteTimeUtc -ne $before)
	}
	if (-not $fresh) {
		Write-Output "НЕТ КАДРА $out"
		exit 1
	}
	$got = Get-PngSize $out
	if ($got -ne $size) {
		Write-Output "НЕ ТОТ РАЗМЕР $out - $got вместо ${size}: окно игры не поместилось на экран, снимайте размер поменьше"
		exit 1
	}
	Write-Output "OK $out"
	exit 0
} catch {
	Write-Output "Ошибка: $($_.Exception.Message)"
	exit 1
} finally {
	if ($p -and -not $p.HasExited) { Stop-Tree $p.Id }
	if ($tmp -and (Test-Path -LiteralPath $tmp)) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
	[Console]::OutputEncoding = $encoding
}
