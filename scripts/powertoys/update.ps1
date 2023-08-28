$RegistryObject = @()

function Expand-RegistryKey {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory,ValueFromPipeline)]
        [Object]
        $RegistryObjectKey,

        [Parameter()]
        [String]
        $ParentRoot = '',

        [Parameter()]
        [String]
        $ParentKey = ''
    )

    if ($ParentRoot) {
        $Root = $ParentRoot
    } else {
        $Root = $RegistryObjectKey.Root
    }

    if ($ParentKey) {
        $Key = "$ParentKey\$($RegistryObjectKey.Key)"
    } else {
        $Key = $RegistryObjectKey.Key
    }

    $RegistryObjectKey.RegistryValue `
    | ForEach-Object {
        if ($_.Root) {
            $_.Root = $Root
        } else {
            $_ `
            | Add-Member -NotePropertyName Root -NotePropertyValue $Root
        }

        if ($_.Key) {
            $_.Key = "$Key\$($_.Key)"
        } else {
            $_ `
            | Add-Member -NotePropertyName Key -NotePropertyValue $Key
        }

        $_
    }

    if ($RegistryObjectKey.RegistryKey) {
        $RegistryObjectKey.RegistryKey `
        | ForEach-Object {
            $_ | Expand-RegistryKey -ParentRoot $Root -ParentKey $Key
        }
    }
}

Get-ChildItem -Path $PSScriptRoot\..\..\..\..\microsoft\PowerToys\installer\PowerToysSetup\ -Filter '*.wxs' -File `
| ForEach-Object {
    [XML]$project = Get-Content $_.FullName

    $components = $project.Wix.Fragment `
    | ForEach-Object { $_.DirectoryRef `
        | ForEach-Object {
            $_.Component
        }
    }

    $RegistryObject += $components `
    | Select-Object -ErrorAction SilentlyContinue -ExpandProperty RegistryValue

    $RegistryObject += $components `
    | Select-Object -ErrorAction SilentlyContinue -ExpandProperty RegistryKey `
    | ForEach-Object {
        $_ | Expand-RegistryKey
    }
}

function Format-String {
    [CmdletBinding()]
    param (
        [Parameter()]
        [String]
        $Value
    )

    $Value.
        Replace('HKLM', 'HKEY_CURRENT_USER').
        Replace('HKCR', 'HKEY_CURRENT_USER\Software\Classes').
        Replace('HKCU', 'HKEY_CURRENT_USER').
        Replace('[Manufacturer]', 'Microsoft').
        Replace('[ProductName]', 'PowerToys').
        Replace('[INSTALLFOLDER]', "{{scoop_dir}}\\").
        Replace('[FileLocksmithInstallFolder]', "{{scoop_dir}}\\modules\\FileLocksmith\\").
        Replace('[ImageResizerInstallFolder]', "{{scoop_dir}}\\modules\\ImageResizer\\").
        Replace('[PowerRenameInstallFolder]', "{{scoop_dir}}\\modules\\PowerRename\\").
        Replace('[WinUI3AppsInstallFolder]', "{{scoop_dir}}\\WinUI3Apps\\").
        Replace('$(var.InstallScope)', 'perUser').
        Replace('$(var.RegistryScope)', 'HKEY_CURRENT_USER')
}

$RegistryObject = $RegistryObject `
| Select-Object -Property Root, Key, Name, Type, Value, Attributes `
| ForEach-Object {
    if ($_.Name -Match '.*installed$') {
        return
    }
    $_.Root = Format-String -Value $_.Root
    $_.Key = Format-String -Value $_.Key
    $_.Name = Format-String -Value $_.Name
    $_.Value = Format-String -Value $_.Value
    $_
}

$RegistryHeader = "Windows Registry Editor Version 5.00"

Set-Content -Path $PSScriptRoot\install-context.reg -Encoding UTF8 -Value `
    $RegistryHeader, `
    $($RegistryObject `
    | ForEach-Object {
        Write-Output "`n[$(
            $_.Root
        )\$(
            $_.Key
        )]`n$(
            if ('Name' -In $_.Attributes.Name) {
                '"'+$_.Name+'"'
            } else {
                '@'
            }
        )=$(
            if ($_.Type -Eq "string") {
                '"'
            }
        )$(
            $_.Value.Replace('"', '\"')
        )$(
            if ($_.Type -Eq "string") {
                '"'
            }
        )"
    }
)

Set-Content -Path $PSScriptRoot\uninstall-context.reg -Encoding UTF8 -Value `
    $RegistryHeader, `
    $($RegistryObject `
    | ForEach-Object {
        Write-Output "`n[$(
            if ($_.Key -NotMatch '.*Software\\Microsoft\\Internet Explorer.*') {
                '-'
            }
        )$(
            $_.Root
        )\$(
            $_.Key
        )]$(
            if ($_.Key -Match '.*Software\\Microsoft\\Internet Explorer.*') {
                "`n-"+'"'+$_.Name+'"'
            }
        )"
    }
)
