# Powershell.exe -executionpolicy remotesigned -File

# TODO:
# проверяем чтоб этот раздел был ventoy
# парсим ventoy.json
# проверяем есть ли файл ventoy.json.reload
# если да, то
# - удаляем ventoy.json и переименуем ventoy.json.reload в ventoy.json
# - если в спарсеном объекте autostart был не пуст, то выполняем
# если нету, то
# - проверяем в спарсеном объекте есть http, если да, то получаем содержимое в переменную
# - если содержимое не пустое, то переименуем ventoy.json в ventoy.json.reload
# - сохраняем содержимое в ventoy.json
# - перезагрузка

$__dirname = Get-Location;

if (Test-Path ..\ventoy\ventoy.json) {
	$json = Get-Content ..\ventoy\ventoy.json -Raw | ConvertFrom-Json;
	if (Test-Path ..\ventoy\ventoy.json.reload) {
		Remove-Item -Path ..\ventoy\ventoy.json -Force;
		Rename-Item -Path ..\ventoy\ventoy.json.reload -NewName ventoy.json;
		if ($json.autostart) {
			# Start-Sleep -Seconds 3;
			$autostart = $json.autostart;
			Invoke-Expression "start $autostart";
		}
	}else{
		if ($json.api) {
			# $rowdata = Invoke-WebRequest '123/monitoring.json' -UseBasicParsing
			# $utf8_ready_data = [system.Text.Encoding]::UTF8.GetString($rowdata.RawContentStream.ToArray());
			$get = Invoke-WebRequest -Uri $json.api;
			# $get = Invoke-WebRequest -Uri "https://raw.githubusercontent.com/alex2844/template_release/master/package.json";
			if ($get.content) {
				Rename-Item -Path ..\ventoy\ventoy.json -NewName ventoy.json.reload;
				$json = ConvertFrom-Json $get.content;
				#$json | ConvertTo-Json -Depth 10 -Compress | % { [System.Text.RegularExpressions.Regex]::Unescape($_) } | Out-File test.json -Encoding Default;
				$json | ConvertTo-Json -Depth 10 -Compress | % { [System.Text.RegularExpressions.Regex]::Unescape($_) } | Out-File ..\ventoy\ventoy.json -Encoding Default;
				# $json | ConvertTo-Json -Depth 10 -Compress | % { [System.Text.RegularExpressions.Regex]::Unescape($_) } | Out-File ..\ventoy\ventoy.json;
				Restart-Computer;
			}
		}
	}
} else {
	echo '[ERROR] Ventoy not found';
}