param(
    [Parameter(Mandatory=$true)][string]$ParamFile,
    [Parameter(Mandatory=$true)][string]$OutPath
)
# Read the KMZ path from the param file — avoids all command-line quoting issues
$KmzPath = (Get-Content -LiteralPath $ParamFile -Raw).Trim()

$ErrorActionPreference = 'Stop'
$statusPath = "$OutPath.status"
function Write-Status($text) {
    try { Set-Content -LiteralPath $statusPath -Value $text -Encoding ASCII } catch {}
}

trap {
    Write-Status ("ERROR: " + $_.Exception.Message)
    exit 1
}

$work = Join-Path $env:TEMP ("bskmz_" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
$zip = Join-Path $work 'src.zip'
Copy-Item -LiteralPath $KmzPath -Destination $zip -Force
Expand-Archive -LiteralPath $zip -DestinationPath $work -Force

$kml = Get-ChildItem -Path $work -Filter 'doc.kml' -Recurse | Select-Object -First 1
if (-not $kml) {
    $kml = Get-ChildItem -Path $work -Filter '*.kml' -Recurse | Select-Object -First 1
}
if (-not $kml) { throw "No KML found inside KMZ" }

[xml]$x = Get-Content -LiteralPath $kml.FullName -Encoding UTF8
$ns = New-Object System.Xml.XmlNamespaceManager $x.NameTable
$ns.AddNamespace('k','http://www.opengis.net/kml/2.2')

$lines = New-Object System.Collections.Generic.List[string]
function Get-KmzFolderName($placemark) {
    $n = $placemark.ParentNode
    while ($n) {
        if ($n.LocalName -eq 'Folder' -or $n.LocalName -eq 'Document') {
            $nameNode = $n.SelectSingleNode('k:name', $ns)
            if ($nameNode -and -not [string]::IsNullOrWhiteSpace($nameNode.InnerText)) {
                return $nameNode.InnerText.Trim().ToUpper()
            }
        }
        $n = $n.ParentNode
    }
    return ''
}

$pms = $x.SelectNodes('//k:Placemark', $ns)
foreach ($p in $pms) {
    $docName = Get-KmzFolderName $p
    $pts = $p.SelectNodes('.//k:Point/k:coordinates', $ns)
    $lns = $p.SelectNodes('.//k:LineString/k:coordinates', $ns)
    foreach ($pt in $pts) {
        if ($pt) {
            $c = $pt.InnerText.Trim()
            $parts = $c -split ','
            if ($parts.Count -ge 2) {
                $lon = $parts[0].Trim()
                $lat = $parts[1].Trim()
                $lines.Add("P|$docName|$lon|$lat") | Out-Null
            }
        }
    }
    foreach ($ln in $lns) {
        if ($ln) {
            $raw = $ln.InnerText.Trim() -replace '\s+',' '
            $verts = $raw -split ' '
            $vlist = New-Object System.Collections.Generic.List[string]
            foreach ($v in $verts) {
                if ([string]::IsNullOrWhiteSpace($v)) { continue }
                $vp = $v -split ','
                if ($vp.Count -ge 2) {
                    $vlist.Add("$($vp[0].Trim()),$($vp[1].Trim())") | Out-Null
                }
            }
            if ($vlist.Count -ge 2) {
                $lines.Add("L|$docName|" + ($vlist -join ';')) | Out-Null
            }
        }
    }
}

Set-Content -LiteralPath $OutPath -Value $lines -Encoding ASCII
Write-Status ("OK " + $lines.Count)

try { Remove-Item -Recurse -Force -LiteralPath $work } catch {}
